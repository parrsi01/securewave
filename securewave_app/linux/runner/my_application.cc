#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif
#include <gio/gio.h>
#include <glib/gstdio.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

#include <cerrno>
#include <cstdint>
#include <cstring>
#include <map>
#include <string>
#include <vector>

#include "flutter/generated_plugin_registrant.h"

namespace {

const char* kChannelName = "securewave/vpn";
const char* kHelperSocketPath = "/run/securewave/helper.sock";
const char* kHelperDaemonPath = "/usr/local/libexec/securewave-helperd";
const char* kHelperContractPath = "/usr/local/libexec/securewave-wg-quick.contract";
const char* kWireGuardConfigFileName = "sw-wg.conf";
const char* kOpenVpnConfigFileName = "securewave.ovpn";
const char* kOpenVpnPidFileName = "securewave-openvpn.pid";
const char* kOpenVpnLogFileName = "securewave-openvpn.log";
const char* kIkev2ConfigFileName = "securewave-ikev2.conf";
const char* kActiveProtocolFileName = "securewave-active-protocol";
const char* kBundledHelperScriptRelativePath = "packaging/linux/securewave-wg-quick";
const char* kBundledHelperDaemonRelativePath = "packaging/linux/securewave-helperd";
const char* kBundledHelperContractRelativePath = "packaging/linux/securewave-wg-quick.contract";
const char* kBundledHelperServiceRelativePath = "packaging/linux/securewave-helper.service";
const char* kBundledHelperTmpfilesRelativePath = "packaging/linux/securewave-helper.tmpfiles";
const guint kSecureWaveHelperContractVersion = 13;
const gsize kMaxHelperResponseBytes = 1024 * 1024;

using Fields = std::map<std::string, std::string>;

typedef struct {
  FlMethodChannel* channel;
  gchar* config_path;
  gchar* openvpn_pid_path;
  gchar* openvpn_log_path;
  gchar* active_protocol_path;
  gchar* active_protocol;
} VpnChannelState;

typedef struct {
  gboolean ok;
  Fields fields;
} HelperResponse;

static void vpn_channel_state_free(VpnChannelState* state) {
  if (!state) {
    return;
  }
  g_clear_object(&state->channel);
  g_clear_pointer(&state->config_path, g_free);
  g_clear_pointer(&state->openvpn_pid_path, g_free);
  g_clear_pointer(&state->openvpn_log_path, g_free);
  g_clear_pointer(&state->active_protocol_path, g_free);
  g_clear_pointer(&state->active_protocol, g_free);
  g_free(state);
}

static const gchar* get_string_arg(FlValue* args, const gchar* key) {
  if (!args || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return nullptr;
  }
  FlValue* value = fl_value_lookup_string(args, key);
  if (!value || fl_value_get_type(value) != FL_VALUE_TYPE_STRING) {
    return nullptr;
  }
  return fl_value_get_string(value);
}

static gboolean get_bool_arg(FlValue* args, const gchar* key) {
  if (!args || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return FALSE;
  }
  FlValue* value = fl_value_lookup_string(args, key);
  if (!value || fl_value_get_type(value) != FL_VALUE_TYPE_BOOL) {
    return FALSE;
  }
  return fl_value_get_bool(value);
}

static std::string field(const Fields& fields, const std::string& key) {
  const auto it = fields.find(key);
  return it == fields.end() ? "" : it->second;
}

static guint64 field_uint64(const Fields& fields, const std::string& key) {
  const std::string value = field(fields, key);
  if (value.empty()) {
    return 0;
  }
  return g_ascii_strtoull(value.c_str(), nullptr, 10);
}

static std::string escape_value(const std::string& value) {
  std::string escaped;
  escaped.reserve(value.size());
  for (char c : value) {
    if (c == '\\') {
      escaped += "\\\\";
    } else if (c == '\n') {
      escaped += "\\n";
    } else if (c == '\r') {
      escaped += "\\r";
    } else {
      escaped += c;
    }
  }
  return escaped;
}

static std::string unescape_value(const std::string& value) {
  std::string out;
  out.reserve(value.size());
  for (size_t i = 0; i < value.size(); i++) {
    if (value[i] != '\\' || i + 1 >= value.size()) {
      out += value[i];
      continue;
    }
    const char next = value[++i];
    if (next == 'n') {
      out += '\n';
    } else if (next == 'r') {
      out += '\r';
    } else {
      out += next;
    }
  }
  return out;
}

static Fields parse_fields(const std::string& body) {
  Fields fields;
  size_t start = 0;
  while (start < body.size()) {
    size_t end = body.find('\n', start);
    if (end == std::string::npos) {
      end = body.size();
    }
    std::string line = body.substr(start, end - start);
    if (!line.empty() && line.back() == '\r') {
      line.pop_back();
    }
    const size_t eq = line.find('=');
    if (eq != std::string::npos) {
      fields[line.substr(0, eq)] = unescape_value(line.substr(eq + 1));
    }
    start = end + 1;
  }
  return fields;
}

static std::string serialize_fields(const Fields& fields) {
  std::string body;
  for (const auto& item : fields) {
    body += item.first;
    body += '=';
    body += escape_value(item.second);
    body += '\n';
  }
  return body;
}

static gboolean write_all(int fd, const std::string& data) {
  const char* cursor = data.data();
  size_t remaining = data.size();
  while (remaining > 0) {
    const ssize_t written = write(fd, cursor, remaining);
    if (written < 0 && errno == EINTR) {
      continue;
    }
    if (written <= 0) {
      return FALSE;
    }
    cursor += written;
    remaining -= static_cast<size_t>(written);
  }
  return TRUE;
}

static gboolean read_all(int fd, std::string* out) {
  out->clear();
  char buffer[4096];
  while (true) {
    const ssize_t count = read(fd, buffer, sizeof(buffer));
    if (count < 0 && errno == EINTR) {
      continue;
    }
    if (count < 0) {
      return FALSE;
    }
    if (count == 0) {
      return TRUE;
    }
    if (out->size() + static_cast<size_t>(count) > kMaxHelperResponseBytes) {
      return FALSE;
    }
    out->append(buffer, static_cast<size_t>(count));
  }
}

static gboolean helper_request(const Fields& request,
                               HelperResponse* response,
                               gchar** detail) {
  if (response != nullptr) {
    response->ok = FALSE;
    response->fields.clear();
  }

  int fd = socket(AF_UNIX, SOCK_STREAM, 0);
  if (fd < 0) {
    if (detail) {
      *detail = g_strdup("Unable to create SecureWave helper socket.");
    }
    return FALSE;
  }

  const struct timeval send_timeout = {5, 0};
  const struct timeval receive_timeout = {60, 0};
  setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &send_timeout, sizeof(send_timeout));
  setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &receive_timeout, sizeof(receive_timeout));

  sockaddr_un address {};
  address.sun_family = AF_UNIX;
  g_strlcpy(address.sun_path, kHelperSocketPath, sizeof(address.sun_path));
  if (connect(fd, reinterpret_cast<sockaddr*>(&address), sizeof(address)) != 0) {
    const int saved_errno = errno;
    close(fd);
    if (detail) {
      if (saved_errno == ENOENT || saved_errno == ECONNREFUSED) {
        *detail = g_strdup(
            "SecureWave helper service is not running. Install the SecureWave .deb package for full no-prompt VPN routing, then retry.");
      } else if (saved_errno == EACCES || saved_errno == EPERM) {
        *detail = g_strdup(
            "Current user is not authorized for the SecureWave helper service. Reinstall SecureWave or add the user to the securewave group.");
      } else {
        *detail = g_strdup_printf(
            "Unable to contact SecureWave helper service: %s",
            g_strerror(saved_errno));
      }
    }
    return FALSE;
  }

  Fields wire_request = request;
  wire_request["version"] = "1";
  const std::string body = serialize_fields(wire_request);
  if (!write_all(fd, body)) {
    close(fd);
    if (detail) {
      *detail = g_strdup("Unable to send request to SecureWave helper service.");
    }
    return FALSE;
  }
  shutdown(fd, SHUT_WR);

  std::string response_body;
  const gboolean read_ok = read_all(fd, &response_body);
  close(fd);
  if (!read_ok) {
    if (detail) {
      *detail = g_strdup("Unable to read SecureWave helper service response.");
    }
    return FALSE;
  }

  Fields parsed = parse_fields(response_body);
  const gboolean ok = field(parsed, "ok") == "true";
  const std::string contract_field = field(parsed, "contract");
  gchar* contract_end = nullptr;
  errno = 0;
  const guint64 contract_value =
      g_ascii_strtoull(contract_field.c_str(), &contract_end, 10);
  const gboolean contract_valid =
      !contract_field.empty() &&
      errno == 0 &&
      contract_end != contract_field.c_str() &&
      contract_end != nullptr &&
      *contract_end == '\0' &&
      contract_value <= G_MAXUINT;
  const guint contract =
      contract_valid ? static_cast<guint>(contract_value) : 0;
  if (response != nullptr) {
    response->ok = ok;
    response->fields = parsed;
  }
  if (!contract_valid) {
    if (detail) {
      *detail = g_strdup(
          "SecureWave helper service returned an invalid contract. Reinstall SecureWave and retry.");
    }
    return FALSE;
  }
  if (contract < kSecureWaveHelperContractVersion) {
    if (detail) {
      *detail = g_strdup_printf(
          "SecureWave helper service is out of date (contract %u, need %u). Reinstall SecureWave and retry.",
          contract,
          kSecureWaveHelperContractVersion);
    }
    return FALSE;
  }
  if (!ok) {
    if (detail) {
      const std::string message = field(parsed, "message");
      *detail = g_strdup(message.empty()
                             ? "SecureWave helper service rejected the request."
                             : message.c_str());
    }
    return FALSE;
  }
  return TRUE;
}

static gboolean helper_operation(const gchar* op,
                                 const Fields& args,
                                 HelperResponse* response,
                                 gchar** detail) {
  Fields request = args;
  request["op"] = op;
  return helper_request(request, response, detail);
}

static gchar* executable_bundle_root() {
  g_autoptr(GError) error = nullptr;
  g_autofree gchar* executable = g_file_read_link("/proc/self/exe", &error);
  if (executable == nullptr || *executable == '\0') {
    return nullptr;
  }
  return g_path_get_dirname(executable);
}

static gchar* bundled_runtime_path(const gchar* relative_path) {
  g_autofree gchar* root = executable_bundle_root();
  if (root == nullptr) {
    return nullptr;
  }
  return g_build_filename(root, relative_path, nullptr);
}

static gboolean bundled_runtime_payload_available(gchar** detail) {
  g_autofree gchar* helper_script = bundled_runtime_path(kBundledHelperScriptRelativePath);
  g_autofree gchar* helper_daemon = bundled_runtime_path(kBundledHelperDaemonRelativePath);
  g_autofree gchar* contract = bundled_runtime_path(kBundledHelperContractRelativePath);
  g_autofree gchar* service = bundled_runtime_path(kBundledHelperServiceRelativePath);
  g_autofree gchar* tmpfiles = bundled_runtime_path(kBundledHelperTmpfilesRelativePath);

  if (helper_script == nullptr || !g_file_test(helper_script, G_FILE_TEST_IS_EXECUTABLE)) {
    if (detail != nullptr) {
      *detail = g_strdup("Bundled SecureWave VPN helper script is missing from this Flutter build.");
    }
    return FALSE;
  }
  if (helper_daemon == nullptr || !g_file_test(helper_daemon, G_FILE_TEST_IS_EXECUTABLE)) {
    if (detail != nullptr) {
      *detail = g_strdup("Bundled SecureWave helper service binary is missing from this Flutter build.");
    }
    return FALSE;
  }
  if (contract == nullptr || !g_file_test(contract, G_FILE_TEST_IS_REGULAR)) {
    if (detail != nullptr) {
      *detail = g_strdup("Bundled SecureWave helper contract is missing from this Flutter build.");
    }
    return FALSE;
  }
  if (service == nullptr || !g_file_test(service, G_FILE_TEST_IS_REGULAR)) {
    if (detail != nullptr) {
      *detail = g_strdup("Bundled SecureWave helper service unit is missing from this Flutter build.");
    }
    return FALSE;
  }
  if (tmpfiles == nullptr || !g_file_test(tmpfiles, G_FILE_TEST_IS_REGULAR)) {
    if (detail != nullptr) {
      *detail = g_strdup("Bundled SecureWave helper runtime directory config is missing from this Flutter build.");
    }
    return FALSE;
  }
  return TRUE;
}

static guint installed_contract_version() {
  g_autofree gchar* contents = nullptr;
  if (!g_file_get_contents(kHelperContractPath, &contents, nullptr, nullptr) ||
      contents == nullptr) {
    return 0;
  }
  g_strstrip(contents);
  if (*contents == '\0' || *contents == '+' || *contents == '-') {
    return 0;
  }
  gchar* end = nullptr;
  errno = 0;
  const guint64 parsed = g_ascii_strtoull(contents, &end, 10);
  if (errno != 0 || end == contents || *end != '\0' || parsed == 0 ||
      parsed > UINT32_MAX) {
    return 0;
  }
  return static_cast<guint>(parsed);
}

static gboolean helper_daemon_installed() {
  return g_file_test(kHelperDaemonPath, G_FILE_TEST_IS_EXECUTABLE);
}

static gboolean linux_native_runtime_available(gchar** detail) {
  const gchar* protocols[] = {"wireguard", "openvpn", "ikev2"};
  g_autofree gchar* last_detail = nullptr;
  gboolean service_seen = FALSE;
  for (const gchar* protocol : protocols) {
    HelperResponse response {};
    g_autofree gchar* op_detail = nullptr;
    Fields args;
    args["protocol"] = protocol;
    if (helper_operation("probe", args, &response, &op_detail)) {
      return TRUE;
    }
    if (!field(response.fields, "service_version").empty()) {
      service_seen = TRUE;
    }
    g_clear_pointer(&last_detail, g_free);
    last_detail = g_strdup(op_detail ? op_detail : "SecureWave helper probe failed.");
  }

  if (detail != nullptr) {
    if (!service_seen) {
      *detail = g_strdup(last_detail
                             ? last_detail
                             : "SecureWave helper service is unavailable.");
    } else {
      *detail = g_strdup("No supported Linux VPN runtime tools are available. Install WireGuard, OpenVPN, or NetworkManager strongSwan support.");
    }
  }
  return FALSE;
}

static gchar* build_state_path(const gchar* filename) {
  const gchar* home_dir = g_get_home_dir();
  if (home_dir == nullptr || *home_dir != '/') {
    return nullptr;
  }
  g_autofree gchar* config_dir = g_build_filename(home_dir, ".config", "securewave", nullptr);
  if (g_mkdir_with_parents(config_dir, 0700) != 0) {
    return nullptr;
  }
  return g_build_filename(config_dir, filename, nullptr);
}

static void persist_active_protocol(VpnChannelState* state, const gchar* protocol) {
  if (!state->active_protocol_path) {
    state->active_protocol_path = build_state_path(kActiveProtocolFileName);
  }
  if (state->active_protocol_path) {
    g_file_set_contents(state->active_protocol_path, protocol, -1, nullptr);
    g_chmod(state->active_protocol_path, 0600);
  }
  g_clear_pointer(&state->active_protocol, g_free);
  state->active_protocol = g_strdup(protocol);
}

static const gchar* load_active_protocol(VpnChannelState* state) {
  if (state->active_protocol && *state->active_protocol != '\0') {
    return state->active_protocol;
  }
  if (!state->active_protocol_path) {
    state->active_protocol_path = build_state_path(kActiveProtocolFileName);
  }
  if (!state->active_protocol_path) {
    return "wireguard";
  }
  g_autofree gchar* stored = nullptr;
  if (!g_file_get_contents(state->active_protocol_path, &stored, nullptr, nullptr) || !stored) {
    return "wireguard";
  }
  g_strstrip(stored);
  if (g_strcmp0(stored, "openvpn") == 0 ||
      g_strcmp0(stored, "ikev2") == 0 ||
      g_strcmp0(stored, "wireguard") == 0) {
    state->active_protocol = g_strdup(stored);
    return state->active_protocol;
  }
  return "wireguard";
}

static void ensure_protocol_paths(VpnChannelState* state, const gchar* protocol) {
  if (g_strcmp0(protocol, "openvpn") == 0) {
    if (!state->config_path) {
      state->config_path = build_state_path(kOpenVpnConfigFileName);
    }
    if (!state->openvpn_pid_path) {
      state->openvpn_pid_path = build_state_path(kOpenVpnPidFileName);
    }
    if (!state->openvpn_log_path) {
      state->openvpn_log_path = build_state_path(kOpenVpnLogFileName);
    }
    return;
  }
  if (!state->config_path) {
    state->config_path = build_state_path(
        g_strcmp0(protocol, "ikev2") == 0
            ? kIkev2ConfigFileName
            : kWireGuardConfigFileName);
  }
}

static Fields helper_args_for_protocol(VpnChannelState* state, const gchar* protocol) {
  ensure_protocol_paths(state, protocol);
  Fields args;
  if (state->config_path) {
    args["config_path"] = state->config_path;
  }
  if (g_strcmp0(protocol, "openvpn") == 0) {
    if (state->openvpn_pid_path) {
      args["pid_path"] = state->openvpn_pid_path;
    }
    if (state->openvpn_log_path) {
      args["log_path"] = state->openvpn_log_path;
    }
  }
  return args;
}

static void respond_error(
    FlMethodCall* method_call,
    const gchar* code,
    const gchar* message,
    FlValue* details) {
  g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
      fl_method_error_response_new(code, message, details));
  fl_method_call_respond(method_call, response, nullptr);
}

static void respond_success(FlMethodCall* method_call) {
  g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
      fl_method_success_response_new(nullptr));
  fl_method_call_respond(method_call, response, nullptr);
}

static void respond_runtime_install_state(FlMethodCall* method_call) {
  g_autofree gchar* payload_detail = nullptr;
  const gboolean payload_available = bundled_runtime_payload_available(&payload_detail);
  const guint contract_version = installed_contract_version();
  gboolean service_seen = FALSE;
  gboolean wireguard_helper_probe = FALSE;
  gboolean openvpn_helper_probe = FALSE;
  gboolean ikev2_helper_probe = FALSE;
  g_autofree gchar* probe_detail = nullptr;
  const gchar* protocols[] = {"wireguard", "openvpn", "ikev2"};
  for (const gchar* protocol : protocols) {
    HelperResponse probe_response {};
    g_autofree gchar* op_detail = nullptr;
    Fields args;
    args["protocol"] = protocol;
    const gboolean ok = helper_operation("probe", args, &probe_response, &op_detail);
    if (!field(probe_response.fields, "service_version").empty()) {
      service_seen = TRUE;
    }
    if (ok && g_strcmp0(protocol, "wireguard") == 0) {
      wireguard_helper_probe = TRUE;
    } else if (ok && g_strcmp0(protocol, "openvpn") == 0) {
      openvpn_helper_probe = TRUE;
    } else if (ok && g_strcmp0(protocol, "ikev2") == 0) {
      ikev2_helper_probe = TRUE;
    }
    if (probe_detail == nullptr && op_detail != nullptr) {
      probe_detail = g_strdup(op_detail);
    }
  }
  const gboolean installed =
      helper_daemon_installed() &&
      service_seen &&
      contract_version >= kSecureWaveHelperContractVersion;

  g_autofree gchar* message = nullptr;
  if (installed) {
    message = g_strdup("SecureWave VPN helper service is installed.");
  } else if (!payload_available) {
    message = g_strdup(
        "This portable Linux build can run the SecureWave UI only. Install the SecureWave .deb package for full no-prompt VPN routing.");
  } else if (!helper_daemon_installed() || !service_seen) {
    message = g_strdup(probe_detail != nullptr
                           ? probe_detail
                           : "SecureWave VPN helper service is bundled but not installed or running. Install or repair the SecureWave .deb package.");
  } else {
    message = g_strdup_printf(
        "SecureWave VPN helper is out of date (contract %u, need %u).",
        contract_version,
        kSecureWaveHelperContractVersion);
  }

  g_autoptr(FlValue) response = fl_value_new_map();
  fl_value_set_string_take(response, "installed", fl_value_new_bool(installed));
  fl_value_set_string_take(
      response,
      "payload_available",
      fl_value_new_bool(payload_available));
  fl_value_set_string_take(
      response,
      "installed_contract",
      fl_value_new_int(static_cast<int64_t>(contract_version)));
  fl_value_set_string_take(
      response,
      "required_contract",
      fl_value_new_int(static_cast<int64_t>(kSecureWaveHelperContractVersion)));
  // These are local helper probes only. Backend runtime and data-plane
  // evidence is required before OpenVPN/IKEv2 can be release-enabled.
  fl_value_set_string_take(response, "wireguard_helper_probe", fl_value_new_bool(wireguard_helper_probe));
  fl_value_set_string_take(response, "openvpn_helper_probe", fl_value_new_bool(openvpn_helper_probe));
  fl_value_set_string_take(response, "ikev2_helper_probe", fl_value_new_bool(ikev2_helper_probe));
  fl_value_set_string_take(response, "message", fl_value_new_string(message));
  g_autoptr(FlMethodResponse) method_response = FL_METHOD_RESPONSE(
      fl_method_success_response_new(response));
  fl_method_call_respond(method_call, method_response, nullptr);
}

static void respond_runtime_install_via_deb(FlMethodCall* method_call) {
  respond_error(
      method_call,
      "runtime_install_requires_deb",
      "SecureWave helper installation is handled by the SecureWave .deb package. Install or repair the .deb once; the app will not request administrator privileges at connect time.",
      nullptr);
}

typedef struct {
  FlMethodCall* method_call;
  gchar* error_code;
  gchar* op;
  Fields args;
} HelperTaskContext;

static void helper_task_context_free(HelperTaskContext* ctx) {
  if (!ctx) {
    return;
  }
  g_clear_object(&ctx->method_call);
  g_clear_pointer(&ctx->error_code, g_free);
  g_clear_pointer(&ctx->op, g_free);
  delete ctx;
}

static HelperTaskContext* helper_task_context_new(
    FlMethodCall* method_call,
    const gchar* error_code,
    const gchar* op,
    const Fields& args) {
  HelperTaskContext* ctx = new HelperTaskContext();
  ctx->args = args;
  ctx->method_call = FL_METHOD_CALL(g_object_ref(method_call));
  ctx->error_code = g_strdup(error_code);
  ctx->op = g_strdup(op);
  return ctx;
}

static void helper_operation_worker(GTask* task,
                                    gpointer source_object,
                                    gpointer task_data,
                                    GCancellable* cancellable) {
  (void)source_object;
  (void)cancellable;
  HelperTaskContext* ctx = static_cast<HelperTaskContext*>(task_data);
  HelperResponse response {};
  g_autofree gchar* detail = nullptr;
  if (!helper_operation(ctx->op, ctx->args, &response, &detail)) {
    g_task_return_new_error(
        task,
        G_IO_ERROR,
        G_IO_ERROR_FAILED,
        "%s",
        detail ? detail : "SecureWave helper operation failed.");
    return;
  }
  g_task_return_boolean(task, TRUE);
}

static void helper_operation_complete(GObject* source_object,
                                      GAsyncResult* result,
                                      gpointer user_data) {
  (void)source_object;
  HelperTaskContext* ctx = static_cast<HelperTaskContext*>(user_data);
  g_autoptr(GError) error = nullptr;
  const gboolean ok = g_task_propagate_boolean(G_TASK(result), &error);
  if (ok) {
    respond_success(ctx->method_call);
  } else {
    respond_error(
        ctx->method_call,
        ctx->error_code,
        error ? error->message : "SecureWave helper operation failed.",
        nullptr);
  }
  helper_task_context_free(ctx);
}

static void run_helper_operation_async(
    FlMethodCall* method_call,
    const gchar* error_code,
    const gchar* op,
    const Fields& args) {
  HelperTaskContext* ctx = helper_task_context_new(method_call, error_code, op, args);
  g_autoptr(GTask) task = g_task_new(nullptr, nullptr, helper_operation_complete, ctx);
  g_task_set_task_data(task, ctx, nullptr);
  g_task_run_in_thread(task, helper_operation_worker);
}

static gboolean write_config_file(FlMethodCall* method_call,
                                  const gchar* path,
                                  const gchar* contents) {
  if (path == nullptr || *path == '\0') {
    respond_error(method_call, "vpn_config_write_failed", "Unable to build SecureWave config path.", nullptr);
    return FALSE;
  }
  g_autoptr(GError) error = nullptr;
  if (!g_file_set_contents(path, contents, -1, &error)) {
    respond_error(
        method_call,
        "vpn_config_write_failed",
        error ? error->message : "Unable to write VPN configuration.",
        nullptr);
    return FALSE;
  }
  g_chmod(path, 0600);
  return TRUE;
}

static gboolean parse_wireguard_transfer(const std::string& output,
                                         guint64* rx_bytes,
                                         guint64* tx_bytes) {
  *rx_bytes = 0;
  *tx_bytes = 0;
  guint peers = 0;
  size_t start = 0;
  while (start < output.size()) {
    size_t end = output.find('\n', start);
    if (end == std::string::npos) {
      end = output.size();
    }
    std::string line = output.substr(start, end - start);
    std::vector<std::string> parts;
    size_t cursor = 0;
    while (cursor < line.size()) {
      while (cursor < line.size() && g_ascii_isspace(line[cursor])) {
        cursor++;
      }
      size_t token_start = cursor;
      while (cursor < line.size() && !g_ascii_isspace(line[cursor])) {
        cursor++;
      }
      if (cursor > token_start) {
        parts.push_back(line.substr(token_start, cursor - token_start));
      }
    }
    if (parts.size() >= 3) {
      *rx_bytes += g_ascii_strtoull(parts[1].c_str(), nullptr, 10);
      *tx_bytes += g_ascii_strtoull(parts[2].c_str(), nullptr, 10);
      peers++;
    }
    start = end + 1;
  }
  return peers > 0;
}

static void respond_traffic_stats(FlMethodCall* method_call,
                                  VpnChannelState* state,
                                  const gchar* protocol) {
  HelperResponse response {};
  g_autofree gchar* detail = nullptr;
  Fields args = helper_args_for_protocol(state, protocol);
  guint64 rx_bytes = 0;
  guint64 tx_bytes = 0;
  gboolean counters_available = FALSE;
  std::string interface_name =
      g_strcmp0(protocol, "openvpn") == 0
          ? "tun0"
          : (g_strcmp0(protocol, "ikev2") == 0 ? "xfrm" : "sw-wg");

  if (g_strcmp0(protocol, "wireguard") == 0 &&
      helper_operation("wireguard.counters", args, &response, &detail)) {
    counters_available = parse_wireguard_transfer(
        field(response.fields, "stdout"),
        &rx_bytes,
        &tx_bytes);
  }

  if (!counters_available) {
    const gchar* op =
        g_strcmp0(protocol, "openvpn") == 0
            ? "openvpn.status"
            : (g_strcmp0(protocol, "ikev2") == 0 ? "ikev2.status" : "wireguard.status");
    g_clear_pointer(&detail, g_free);
    if (helper_operation(op, args, &response, &detail)) {
      interface_name = field(response.fields, "interface");
      rx_bytes = field_uint64(response.fields, "rx_bytes");
      tx_bytes = field_uint64(response.fields, "tx_bytes");
      counters_available = field(response.fields, "counters_available") == "true";
    }
  }

  g_autoptr(FlValue) value = fl_value_new_map();
  fl_value_set_string_take(value, "interface", fl_value_new_string(interface_name.c_str()));
  fl_value_set_string_take(value, "rx_bytes", fl_value_new_int(static_cast<int64_t>(rx_bytes)));
  fl_value_set_string_take(value, "tx_bytes", fl_value_new_int(static_cast<int64_t>(tx_bytes)));
  fl_value_set_string_take(value, "counters_available", fl_value_new_bool(counters_available));
  if (!counters_available) {
    fl_value_set_string_take(
        value,
        "unavailable_reason",
        fl_value_new_string(detail ? detail : "SecureWave helper did not return readable traffic counters."));
  }
  g_autoptr(FlMethodResponse) method_response = FL_METHOD_RESPONSE(
      fl_method_success_response_new(value));
  fl_method_call_respond(method_call, method_response, nullptr);
}

static void respond_runtime_status(
    FlMethodCall* method_call,
    VpnChannelState* state) {
  const gchar* protocol = load_active_protocol(state);
  Fields args = helper_args_for_protocol(state, protocol);
  const gchar* op =
      g_strcmp0(protocol, "openvpn") == 0
          ? "openvpn.status"
          : (g_strcmp0(protocol, "ikev2") == 0 ? "ikev2.status" : "wireguard.status");
  HelperResponse response {};
  g_autofree gchar* detail = nullptr;
  const gboolean ok = helper_operation(op, args, &response, &detail);
  const std::string status = ok ? field(response.fields, "status") : "disconnected";

  g_autoptr(FlValue) value = fl_value_new_map();
  fl_value_set_string_take(
      value,
      "status",
      fl_value_new_string(status == "connected" ? "connected" : "disconnected"));
  fl_value_set_string_take(value, "protocol", fl_value_new_string(protocol));
  if (!ok && detail != nullptr) {
    fl_value_set_string_take(value, "message", fl_value_new_string(detail));
  }
  g_autoptr(FlMethodResponse) method_response = FL_METHOD_RESPONSE(
      fl_method_success_response_new(value));
  fl_method_call_respond(method_call, method_response, nullptr);
}

static const gchar* connect_op_for_protocol(const gchar* protocol) {
  if (g_strcmp0(protocol, "openvpn") == 0) {
    return "openvpn.start";
  }
  if (g_strcmp0(protocol, "ikev2") == 0) {
    return "ikev2.start";
  }
  return "wireguard.up";
}

static const gchar* disconnect_op_for_protocol(const gchar* protocol) {
  if (g_strcmp0(protocol, "openvpn") == 0) {
    return "openvpn.stop";
  }
  if (g_strcmp0(protocol, "ikev2") == 0) {
    return "ikev2.stop";
  }
  return "wireguard.down";
}

static const gchar* config_file_for_protocol(const gchar* protocol) {
  if (g_strcmp0(protocol, "openvpn") == 0) {
    return kOpenVpnConfigFileName;
  }
  if (g_strcmp0(protocol, "ikev2") == 0) {
    return kIkev2ConfigFileName;
  }
  return kWireGuardConfigFileName;
}

static gboolean supported_protocol(const gchar* protocol) {
  return g_strcmp0(protocol, "wireguard") == 0 ||
         g_strcmp0(protocol, "openvpn") == 0 ||
         g_strcmp0(protocol, "ikev2") == 0;
}

static void handle_vpn_call(FlMethodChannel* channel,
                            FlMethodCall* method_call,
                            gpointer user_data) {
  (void)channel;
  VpnChannelState* state = static_cast<VpnChannelState*>(user_data);
  const gchar* method = fl_method_call_get_name(method_call);

  if (g_strcmp0(method, "isAvailable") == 0) {
    g_autofree gchar* detail = nullptr;
    if (!linux_native_runtime_available(&detail)) {
      respond_error(
          method_call,
          "vpn_unavailable",
          detail ? detail : "SecureWave Linux VPN runtime is unavailable.",
          fl_value_new_map());
      return;
    }
    FlValue* args = fl_method_call_get_args(method_call);
    const gchar* protocol = get_string_arg(args, "protocol");
    if (protocol && *protocol != '\0') {
      if (!supported_protocol(protocol)) {
        respond_error(
            method_call,
            "protocol_unavailable",
            "Unsupported VPN protocol.",
            nullptr);
        return;
      }
      if (g_strcmp0(protocol, "wireguard") != 0 &&
          !get_bool_arg(args, "backend_evidence")) {
        respond_error(
            method_call,
            "protocol_unavailable",
            "OpenVPN and IKEv2 require fresh backend runtime and data-plane evidence.",
            nullptr);
        return;
      }
      Fields probe_args;
      probe_args["protocol"] = protocol;
      HelperResponse probe_response {};
      g_clear_pointer(&detail, g_free);
      if (!helper_operation("probe", probe_args, &probe_response, &detail)) {
        respond_error(
            method_call,
            "protocol_unavailable",
            detail ? detail : "Selected VPN protocol is unavailable.",
            nullptr);
        return;
      }
    }
    g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
        fl_method_success_response_new(fl_value_new_bool(TRUE)));
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }

  if (g_strcmp0(method, "getStatus") == 0) {
    respond_runtime_status(method_call, state);
    return;
  }

  if (g_strcmp0(method, "getTrafficStats") == 0) {
    FlValue* args = fl_method_call_get_args(method_call);
    const gchar* protocol = get_string_arg(args, "protocol");
    if (!protocol || *protocol == '\0' || !supported_protocol(protocol)) {
      protocol = load_active_protocol(state);
    }
    respond_traffic_stats(method_call, state, protocol);
    return;
  }

  if (g_strcmp0(method, "getRuntimeInstallState") == 0) {
    respond_runtime_install_state(method_call);
    return;
  }

  if (g_strcmp0(method, "installRuntimeHelper") == 0) {
    respond_runtime_install_via_deb(method_call);
    return;
  }

  if (g_strcmp0(method, "connect") == 0) {
    FlValue* args = fl_method_call_get_args(method_call);
    const gchar* protocol = get_string_arg(args, "protocol");
    if (!protocol || *protocol == '\0') {
      protocol = "wireguard";
    }
    if (!supported_protocol(protocol)) {
      respond_error(method_call, "protocol_unavailable", "Unsupported VPN protocol.", nullptr);
      return;
    }
    if (g_strcmp0(protocol, "wireguard") != 0 &&
        !get_bool_arg(args, "backend_evidence")) {
      respond_error(
          method_call,
          "protocol_unavailable",
          "OpenVPN and IKEv2 require fresh backend runtime and data-plane evidence.",
          nullptr);
      return;
    }
    HelperResponse probe_response {};
    g_autofree gchar* probe_detail = nullptr;
    Fields probe_args;
    probe_args["protocol"] = protocol;
    if (!helper_operation("probe", probe_args, &probe_response, &probe_detail)) {
      respond_error(
          method_call,
          "protocol_unavailable",
          probe_detail ? probe_detail : "Selected VPN protocol is not available on this runtime.",
          nullptr);
      return;
    }
    const gchar* config = get_string_arg(args, "config");
    if (!config || *config == '\0') {
      respond_error(method_call, "invalid_config", "Missing VPN configuration.", nullptr);
      return;
    }

    g_clear_pointer(&state->config_path, g_free);
    g_clear_pointer(&state->openvpn_pid_path, g_free);
    g_clear_pointer(&state->openvpn_log_path, g_free);
    state->config_path = build_state_path(config_file_for_protocol(protocol));
    if (g_strcmp0(protocol, "openvpn") == 0) {
      state->openvpn_pid_path = build_state_path(kOpenVpnPidFileName);
      state->openvpn_log_path = build_state_path(kOpenVpnLogFileName);
    }
    if (!write_config_file(method_call, state->config_path, config)) {
      return;
    }
    persist_active_protocol(state, protocol);
    Fields helper_args = helper_args_for_protocol(state, protocol);
    run_helper_operation_async(
        method_call,
        "vpn_connect_failed",
        connect_op_for_protocol(protocol),
        helper_args);
    return;
  }

  if (g_strcmp0(method, "disconnect") == 0) {
    const gchar* protocol = load_active_protocol(state);
    Fields helper_args = helper_args_for_protocol(state, protocol);
    run_helper_operation_async(
        method_call,
        "vpn_disconnect_failed",
        disconnect_op_for_protocol(protocol),
        helper_args);
    return;
  }

  g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
      fl_method_not_implemented_response_new());
  fl_method_call_respond(method_call, response, nullptr);
}

}  // namespace

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  GtkWindow* main_window;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

static void main_window_destroy_cb(MyApplication* self) {
  self->main_window = nullptr;
}

static void first_frame_cb(MyApplication* self, FlView* view) {
  (void)self;
  G_GNUC_BEGIN_IGNORE_DEPRECATIONS
  GtkWidget* toplevel = gtk_widget_get_toplevel(GTK_WIDGET(view));
  G_GNUC_END_IGNORE_DEPRECATIONS
  gtk_widget_show(toplevel);
}

static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  if (self->main_window != nullptr) {
    gtk_window_present(self->main_window);
    return;
  }

  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));
  self->main_window = window;
  g_signal_connect_swapped(window, "destroy",
                           G_CALLBACK(main_window_destroy_cb), self);

  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  G_GNUC_BEGIN_IGNORE_DEPRECATIONS
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
  G_GNUC_END_IGNORE_DEPRECATIONS
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    G_GNUC_BEGIN_IGNORE_DEPRECATIONS
    gtk_header_bar_set_title(header_bar, "SecureWave VPN");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    G_GNUC_END_IGNORE_DEPRECATIONS
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "SecureWave VPN");
  }

  gtk_window_set_default_size(window, 1280, 720);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  G_GNUC_BEGIN_IGNORE_DEPRECATIONS
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));
  G_GNUC_END_IGNORE_DEPRECATIONS

  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb), self);
  G_GNUC_BEGIN_IGNORE_DEPRECATIONS
  gtk_widget_realize(GTK_WIDGET(view));
  G_GNUC_END_IGNORE_DEPRECATIONS

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  FlEngine* engine = fl_view_get_engine(view);
  VpnChannelState* vpn_state = g_new0(VpnChannelState, 1);
  vpn_state->channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(engine),
      kChannelName,
      FL_METHOD_CODEC(fl_standard_method_codec_new()));
  fl_method_channel_set_method_call_handler(
      vpn_state->channel,
      handle_vpn_call,
      vpn_state,
      reinterpret_cast<GDestroyNotify>(vpn_channel_state_free));

  gtk_widget_grab_focus(GTK_WIDGET(view));
  gtk_widget_show(GTK_WIDGET(window));
}

static int my_application_command_line(GApplication* application,
                                       GApplicationCommandLine* command_line) {
  MyApplication* self = MY_APPLICATION(application);
  int argc = 0;
  g_auto(GStrv) argv = g_application_command_line_get_arguments(command_line, &argc);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  self->dart_entrypoint_arguments =
      argc > 1 ? g_strdupv(argv + 1) : g_new0(gchar*, 1);
  g_application_activate(application);
  return 0;
}

static void my_application_startup(GApplication* application) {
  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

static void my_application_shutdown(GApplication* application) {
  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->command_line = my_application_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  g_set_prgname(APPLICATION_ID);
  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID,
                                     "flags",
                                     G_APPLICATION_HANDLES_COMMAND_LINE |
                                         G_APPLICATION_NON_UNIQUE,
                                     nullptr));
}
