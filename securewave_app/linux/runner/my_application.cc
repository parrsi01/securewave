#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif
#include <gio/gio.h>
#include <glib/gstdio.h>
#include <errno.h>
#include <signal.h>
#include <unistd.h>

#include "flutter/generated_plugin_registrant.h"

// g_spawn_check_exit_status was renamed to g_spawn_check_wait_status in
// glib 2.70.  Provide a compatibility shim so the build succeeds on both
// older and newer versions of glib.
#if !GLIB_CHECK_VERSION(2, 70, 0)
static inline gboolean g_spawn_check_wait_status(gint wait_status,
                                                  GError** error) {
  return g_spawn_check_exit_status(wait_status, error);
}
#endif

namespace {
const char* kChannelName = "securewave/vpn";
const char* kWireGuardInterfaceName = "sw-wg";
const char* kWireGuardConfigFileName = "sw-wg.conf";
const char* kWireGuardHelperPath = "/usr/local/libexec/securewave-wg-quick";
const char* kWireGuardHelperContractPath = "/usr/local/libexec/securewave-wg-quick.contract";
const char* kOpenVpnConfigFileName = "securewave.ovpn";
const char* kOpenVpnPidFileName = "securewave-openvpn.pid";
const char* kOpenVpnLogFileName = "securewave-openvpn.log";
const char* kIkev2ConfigFileName = "securewave-ikev2.conf";
const char* kIkev2CaFileName = "securewave-ikev2-ca.pem";
const char* kIkev2ConnectionName = "SecureWave-IKEv2";
const char* kActiveProtocolFileName = "securewave-active-protocol";
const guint kSecureWaveHelperContractVersion = 7;
const guint kWgQuickTimeoutMs = 30000;
const guint kOpenVpnTimeoutMs = 20000;

typedef struct {
  FlMethodChannel* channel;
  gchar* config_path;
  gchar* openvpn_pid_path;
  gchar* openvpn_log_path;
  gchar* active_protocol_path;
  gchar* active_protocol;
} VpnChannelState;

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

static gboolean wg_quick_available() {
  g_autofree gchar* wg_quick = g_find_program_in_path("wg-quick");
  return wg_quick != nullptr;
}

static gboolean wireguard_helper_available() {
  return g_file_test(kWireGuardHelperPath, G_FILE_TEST_IS_EXECUTABLE);
}

static guint securewave_helper_contract_version() {
  g_autofree gchar* contents = nullptr;
  if (!g_file_get_contents(kWireGuardHelperContractPath, &contents, nullptr, nullptr) ||
      contents == nullptr) {
    return 0;
  }
  g_strstrip(contents);
  if (*contents == '\0') {
    return 0;
  }
  return static_cast<guint>(g_ascii_strtoull(contents, nullptr, 10));
}

static gboolean securewave_helper_contract_available(gchar** detail) {
  if (!wireguard_helper_available()) {
    if (detail != nullptr) {
      *detail = g_strdup("SecureWave VPN helper not found. Reinstall SecureWave and retry.");
    }
    return FALSE;
  }
  const guint contract_version = securewave_helper_contract_version();
  if (contract_version < kSecureWaveHelperContractVersion) {
    if (detail != nullptr) {
      *detail = g_strdup_printf(
          "SecureWave VPN helper is out of date (contract %u, need %u). Reinstall SecureWave to update /usr/local/libexec/securewave-wg-quick.",
          contract_version,
          kSecureWaveHelperContractVersion);
    }
    return FALSE;
  }
  return TRUE;
}

static gboolean openvpn_available() {
  g_autofree gchar* openvpn = g_find_program_in_path("openvpn");
  return openvpn != nullptr;
}

static gboolean ikev2_tooling_available() {
  g_autofree gchar* nmcli = g_find_program_in_path("nmcli");
  g_autofree gchar* ipsec = g_find_program_in_path("ipsec");
  return nmcli != nullptr && ipsec != nullptr;
}

static gboolean ikev2_available() {
  return ikev2_tooling_available() && securewave_helper_contract_available(nullptr);
}

static gboolean elevated_runner_available() {
  if (geteuid() == 0) {
    return TRUE;
  }
  g_autofree gchar* pkexec = g_find_program_in_path("pkexec");
  return pkexec != nullptr;
}

static gboolean linux_native_runtime_available(gchar** detail) {
  if (!elevated_runner_available()) {
    if (detail != nullptr) {
      *detail = g_strdup("PolicyKit/pkexec not found. Install PolicyKit so SecureWave can start VPN protocols.");
    }
    return FALSE;
  }

  if (!securewave_helper_contract_available(detail)) {
    return FALSE;
  }

  if (!wg_quick_available() && !openvpn_available() && !ikev2_tooling_available()) {
    if (detail != nullptr) {
      *detail = g_strdup("No supported Linux VPN runtime tools found. Install wireguard-tools, openvpn, and network-manager-strongswan.");
    }
    return FALSE;
  }

  return TRUE;
}

static gchar* build_state_path(const gchar* filename) {
  g_autofree gchar* config_dir = g_build_filename(g_get_user_config_dir(), "securewave", nullptr);
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

typedef struct {
  gint ref_count;
  FlMethodCall* method_call;
  gchar* error_code;
  gchar* action;
  GPid pid;
  guint timeout_id;
  guint timeout_ms;
  gboolean responded;
  gboolean verify_wireguard_interface;
  gboolean verify_openvpn_started;
  gboolean verify_openvpn_stopped;
  gchar* openvpn_pid_path;
  gchar* openvpn_log_path;
  gint stdout_fd;
  gint stderr_fd;
} WgQuickSpawnContext;

static WgQuickSpawnContext* wg_quick_spawn_context_ref(WgQuickSpawnContext* ctx) {
  g_atomic_int_inc(&ctx->ref_count);
  return ctx;
}

static void wg_quick_spawn_context_unref(WgQuickSpawnContext* ctx) {
  if (!ctx) {
    return;
  }
  if (!g_atomic_int_dec_and_test(&ctx->ref_count)) {
    return;
  }
  g_clear_object(&ctx->method_call);
  g_clear_pointer(&ctx->error_code, g_free);
  g_clear_pointer(&ctx->action, g_free);
  g_clear_pointer(&ctx->openvpn_pid_path, g_free);
  g_clear_pointer(&ctx->openvpn_log_path, g_free);
  if (ctx->stdout_fd >= 0) {
    close(ctx->stdout_fd);
    ctx->stdout_fd = -1;
  }
  if (ctx->stderr_fd >= 0) {
    close(ctx->stderr_fd);
    ctx->stderr_fd = -1;
  }
  g_free(ctx);
}

static void wg_quick_respond_ok_once(WgQuickSpawnContext* ctx) {
  if (ctx->responded) {
    return;
  }
  ctx->responded = TRUE;
  g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
      fl_method_success_response_new(nullptr));
  fl_method_call_respond(ctx->method_call, response, nullptr);
}

static void wg_quick_respond_error_once(WgQuickSpawnContext* ctx, const gchar* message) {
  if (ctx->responded) {
    return;
  }
  ctx->responded = TRUE;
  respond_error(ctx->method_call, ctx->error_code, message, nullptr);
}

static gchar* read_fd_to_string(gint* fd) {
  if (fd == nullptr || *fd < 0) {
    return g_strdup("");
  }
  GString* contents = g_string_new(nullptr);
  gchar buffer[4096];
  while (true) {
    const ssize_t bytes_read = read(*fd, buffer, sizeof(buffer));
    if (bytes_read > 0) {
      g_string_append_len(contents, buffer, bytes_read);
      continue;
    }
    if (bytes_read < 0 && errno == EINTR) {
      continue;
    }
    break;
  }
  close(*fd);
  *fd = -1;
  return g_string_free(contents, FALSE);
}

static gchar* command_failure_message(
    const gchar* fallback,
    const gchar* stdout_text,
    const gchar* stderr_text) {
  g_autofree gchar* stderr_clean = g_strdup(stderr_text ? stderr_text : "");
  g_autofree gchar* stdout_clean = g_strdup(stdout_text ? stdout_text : "");
  g_strstrip(stderr_clean);
  g_strstrip(stdout_clean);
  if (*stderr_clean != '\0') {
    return g_strdup_printf("%s: %s", fallback, stderr_clean);
  }
  if (*stdout_clean != '\0') {
    return g_strdup_printf("%s: %s", fallback, stdout_clean);
  }
  return g_strdup(fallback);
}

static gboolean wireguard_interface_exists() {
  gint wait_status = 0;
  g_autoptr(GError) error = nullptr;
  const gchar* argv[] = {"ip", "link", "show", kWireGuardInterfaceName, nullptr};
  if (!g_spawn_sync(nullptr,
                    const_cast<gchar**>(argv),
                    nullptr,
                    G_SPAWN_SEARCH_PATH,
                    nullptr,
                    nullptr,
                    nullptr,
                    nullptr,
                    &wait_status,
                    &error)) {
    return FALSE;
  }
  return g_spawn_check_wait_status(wait_status, nullptr);
}

static gboolean wireguard_route_exists() {
  gint wait_status = 0;
  g_autoptr(GError) error = nullptr;
  g_autofree gchar* output = nullptr;
  const gchar* argv[] = {"ip", "route", "get", "1.1.1.1", nullptr};
  if (!g_spawn_sync(nullptr,
                    const_cast<gchar**>(argv),
                    nullptr,
                    G_SPAWN_SEARCH_PATH,
                    nullptr,
                    nullptr,
                    &output,
                    nullptr,
                    &wait_status,
                    &error)) {
    return FALSE;
  }
  return g_spawn_check_wait_status(wait_status, nullptr) &&
         output != nullptr &&
         g_strstr_len(output, -1, " dev sw-wg") != nullptr;
}

static gboolean read_pid_from_file(const gchar* pid_path, GPid* pid) {
  if (pid_path == nullptr || pid == nullptr) {
    return FALSE;
  }
  g_autofree gchar* contents = nullptr;
  if (!g_file_get_contents(pid_path, &contents, nullptr, nullptr) || contents == nullptr) {
    return FALSE;
  }
  g_strstrip(contents);
  if (*contents == '\0') {
    return FALSE;
  }
  gchar* end = nullptr;
  const gint64 parsed = g_ascii_strtoll(contents, &end, 10);
  if (end == contents || *end != '\0' || parsed <= 0 || parsed > G_MAXINT) {
    return FALSE;
  }
  *pid = static_cast<GPid>(parsed);
  return TRUE;
}

static gboolean process_is_running(GPid pid) {
  if (pid <= 0) {
    return FALSE;
  }
  if (kill(pid, 0) == 0) {
    return TRUE;
  }
  return errno == EPERM;
}

static gboolean openvpn_pid_running(const gchar* pid_path) {
  GPid pid = 0;
  return read_pid_from_file(pid_path, &pid) && process_is_running(pid);
}

static gboolean openvpn_tun_interface_exists() {
  if (g_file_test("/sys/class/net/tun0", G_FILE_TEST_IS_DIR)) {
    return TRUE;
  }
  g_autoptr(GDir) dir = g_dir_open("/sys/class/net", 0, nullptr);
  if (dir == nullptr) {
    return FALSE;
  }
  const gchar* name = nullptr;
  while ((name = g_dir_read_name(dir)) != nullptr) {
    if (g_str_has_prefix(name, "tun")) {
      return TRUE;
    }
  }
  return FALSE;
}

static gboolean openvpn_route_exists() {
  gint wait_status = 0;
  g_autoptr(GError) error = nullptr;
  g_autofree gchar* output = nullptr;
  const gchar* argv[] = {"ip", "route", "get", "1.1.1.1", nullptr};
  if (!g_spawn_sync(nullptr,
                    const_cast<gchar**>(argv),
                    nullptr,
                    G_SPAWN_SEARCH_PATH,
                    nullptr,
                    nullptr,
                    &output,
                    nullptr,
                    &wait_status,
                    &error)) {
    return FALSE;
  }
  return g_spawn_check_wait_status(wait_status, nullptr) &&
         output != nullptr &&
         g_strstr_len(output, -1, " dev tun") != nullptr;
}

static gboolean openvpn_initialization_completed(const gchar* log_path) {
  if (log_path == nullptr || *log_path == '\0') {
    return FALSE;
  }
  g_autofree gchar* contents = nullptr;
  if (!g_file_get_contents(log_path, &contents, nullptr, nullptr) || contents == nullptr) {
    return FALSE;
  }
  return g_strstr_len(contents, -1, "Initialization Sequence Completed") != nullptr;
}

static gchar* openvpn_log_tail(const gchar* log_path) {
  if (log_path == nullptr || *log_path == '\0') {
    return nullptr;
  }
  g_autofree gchar* contents = nullptr;
  if (!g_file_get_contents(log_path, &contents, nullptr, nullptr) || contents == nullptr) {
    return nullptr;
  }
  g_auto(GStrv) lines = g_strsplit(contents, "\n", -1);
  guint count = 0;
  while (lines[count] != nullptr) {
    count++;
  }
  const guint start = count > 12 ? count - 12 : 0;
  GString* tail = g_string_new(nullptr);
  for (guint i = start; lines[i] != nullptr; i++) {
    g_autofree gchar* line = g_strdup(lines[i]);
    g_strstrip(line);
    if (*line == '\0') {
      continue;
    }
    if (tail->len > 0) {
      g_string_append(tail, " | ");
    }
    g_string_append(tail, line);
  }
  if (tail->len == 0) {
    g_string_free(tail, TRUE);
    return nullptr;
  }
  return g_string_free(tail, FALSE);
}

static gboolean openvpn_runtime_evidence_exists(const gchar* pid_path, const gchar* log_path) {
  return openvpn_pid_running(pid_path) &&
         openvpn_initialization_completed(log_path) &&
         (openvpn_route_exists() || openvpn_tun_interface_exists());
}

static gboolean wait_for_openvpn_runtime_evidence(const gchar* pid_path, const gchar* log_path) {
  for (guint i = 0; i < 20; i++) {
    if (openvpn_runtime_evidence_exists(pid_path, log_path)) {
      return TRUE;
    }
    g_usleep(500000);
  }
  return FALSE;
}

static gboolean wait_for_openvpn_stop_evidence(const gchar* pid_path) {
  for (guint i = 0; i < 10; i++) {
    if (!openvpn_pid_running(pid_path) && !openvpn_route_exists()) {
      return TRUE;
    }
    g_usleep(500000);
  }
  return !openvpn_pid_running(pid_path) && !openvpn_route_exists();
}

static void remove_openvpn_pid_file(const gchar* pid_path) {
  if (pid_path != nullptr) {
    g_unlink(pid_path);
  }
}

static gchar* unquote_config_value(const gchar* raw_value) {
  if (raw_value == nullptr) {
    return nullptr;
  }
  g_autofree gchar* value = g_strdup(raw_value);
  g_strstrip(value);
  const gsize length = strlen(value);
  if (length >= 2 && value[0] == '"' && value[length - 1] == '"') {
    GString* unquoted = g_string_new(nullptr);
    for (gsize i = 1; i + 1 < length; i++) {
      if (value[i] == '\\' && i + 2 < length) {
        i++;
      }
      g_string_append_c(unquoted, value[i]);
    }
    return g_string_free(unquoted, FALSE);
  }
  return g_strdup(value);
}

static gchar* parse_config_assignment(const gchar* line, const gchar* key) {
  if (line == nullptr || key == nullptr) {
    return nullptr;
  }
  g_autofree gchar* trimmed = g_strdup(line);
  g_strstrip(trimmed);
  const gsize key_length = strlen(key);
  if (!g_str_has_prefix(trimmed, key)) {
    return nullptr;
  }
  gchar* cursor = trimmed + key_length;
  while (g_ascii_isspace(*cursor)) {
    cursor++;
  }
  if (*cursor != '=') {
    return nullptr;
  }
  cursor++;
  return unquote_config_value(cursor);
}

static gchar* parse_config_value(const gchar* config, const gchar* key) {
  if (config == nullptr || key == nullptr) {
    return nullptr;
  }
  g_auto(GStrv) lines = g_strsplit(config, "\n", -1);
  for (guint i = 0; lines[i] != nullptr; i++) {
    g_autofree gchar* value = parse_config_assignment(lines[i], key);
    if (value != nullptr && *value != '\0') {
      return g_strdup(value);
    }
  }
  return nullptr;
}

static gchar* parse_ikev2_remote_id(const gchar* config) {
  if (config == nullptr) {
    return nullptr;
  }
  g_auto(GStrv) lines = g_strsplit(config, "\n", -1);
  gboolean in_remote_block = FALSE;
  for (guint i = 0; lines[i] != nullptr; i++) {
    g_autofree gchar* line = g_strdup(lines[i]);
    g_strstrip(line);
    if (g_str_has_prefix(line, "remote {")) {
      in_remote_block = TRUE;
      continue;
    }
    if (in_remote_block && g_str_has_prefix(line, "}")) {
      in_remote_block = FALSE;
      continue;
    }
    if (!in_remote_block) {
      continue;
    }
    g_autofree gchar* value = parse_config_assignment(line, "id");
    if (value != nullptr && *value != '\0') {
      return g_strdup(value);
    }
  }
  return nullptr;
}

static gchar* parse_ikev2_ca_cert_pem(const gchar* config) {
  if (config == nullptr) {
    return nullptr;
  }
  g_auto(GStrv) lines = g_strsplit(config, "\n", -1);
  GString* pem = g_string_new(nullptr);
  gboolean in_ca_block = FALSE;
  for (guint i = 0; lines[i] != nullptr; i++) {
    g_autofree gchar* line = g_strdup(lines[i]);
    g_strstrip(line);
    if (g_strcmp0(line, "# ca_cert_pem_begin") == 0) {
      in_ca_block = TRUE;
      continue;
    }
    if (g_strcmp0(line, "# ca_cert_pem_end") == 0) {
      break;
    }
    if (!in_ca_block || *line == '\0') {
      continue;
    }
    g_string_append(pem, line);
    g_string_append_c(pem, '\n');
  }
  if (pem->len == 0 ||
      strstr(pem->str, "-----BEGIN CERTIFICATE-----") == nullptr ||
      strstr(pem->str, "-----END CERTIFICATE-----") == nullptr) {
    g_string_free(pem, TRUE);
    return nullptr;
  }
  return g_string_free(pem, FALSE);
}

static gboolean run_securewave_helper_capture_sync(
    const gchar* action,
    const gchar* const* args,
    gchar** stdout_out,
    gchar** detail) {
  if (stdout_out != nullptr) {
    *stdout_out = nullptr;
  }
  if (!wireguard_helper_available()) {
    if (detail != nullptr) {
      *detail = g_strdup("SecureWave VPN helper not found. Reinstall SecureWave and retry.");
    }
    return FALSE;
  }

  g_autofree gchar* pkexec = nullptr;
  GPtrArray* argv_array = g_ptr_array_new_with_free_func(g_free);
  if (geteuid() != 0) {
    pkexec = g_find_program_in_path("pkexec");
    if (pkexec == nullptr) {
      g_ptr_array_free(argv_array, TRUE);
      if (detail != nullptr) {
        *detail = g_strdup("PolicyKit/pkexec not found. Install PolicyKit or run SecureWave with the required permissions.");
      }
      return FALSE;
    }
    g_ptr_array_add(argv_array, g_strdup(pkexec));
    g_ptr_array_add(argv_array, g_strdup("--disable-internal-agent"));
  }
  g_ptr_array_add(argv_array, g_strdup(kWireGuardHelperPath));
  g_ptr_array_add(argv_array, g_strdup(action));
  if (args != nullptr) {
    for (guint i = 0; args[i] != nullptr; i++) {
      g_ptr_array_add(argv_array, g_strdup(args[i]));
    }
  }
  g_ptr_array_add(argv_array, nullptr);

  gint wait_status = 0;
  g_autoptr(GError) error = nullptr;
  g_autofree gchar* stdout_text = nullptr;
  g_autofree gchar* stderr_text = nullptr;
  const gboolean spawned = g_spawn_sync(
      nullptr,
      reinterpret_cast<gchar**>(argv_array->pdata),
      nullptr,
      G_SPAWN_SEARCH_PATH,
      nullptr,
      nullptr,
      &stdout_text,
      &stderr_text,
      &wait_status,
      &error);
  g_ptr_array_free(argv_array, TRUE);

  if (!spawned) {
    if (detail != nullptr) {
      *detail = g_strdup(error ? error->message : "Failed to run SecureWave helper.");
    }
    return FALSE;
  }
  if (!g_spawn_check_wait_status(wait_status, nullptr)) {
    if (detail != nullptr) {
      g_autofree gchar* stderr_clean = g_strdup(stderr_text ? stderr_text : "");
      g_autofree gchar* stdout_clean = g_strdup(stdout_text ? stdout_text : "");
      g_strstrip(stderr_clean);
      g_strstrip(stdout_clean);
      *detail = g_strdup(*stderr_clean != '\0' ? stderr_clean :
                         (*stdout_clean != '\0' ? stdout_clean : "SecureWave helper exited with an error."));
    }
    return FALSE;
  }
  if (stdout_out != nullptr) {
    *stdout_out = g_steal_pointer(&stdout_text);
  }
  return TRUE;
}

static gboolean run_securewave_helper_sync(
    const gchar* action,
    const gchar* const* args,
    gchar** detail) {
  return run_securewave_helper_capture_sync(action, args, nullptr, detail);
}

static void stop_openvpn_after_failed_start(const gchar* pid_path) {
  GPid openvpn_pid = 0;
  if (!read_pid_from_file(pid_path, &openvpn_pid)) {
    return;
  }
  g_autofree gchar* pid_arg = g_strdup_printf("%d", static_cast<int>(openvpn_pid));
  const gchar* stop_args[] = {pid_arg, nullptr};
  run_securewave_helper_sync("openvpn-stop", stop_args, nullptr);
  wait_for_openvpn_stop_evidence(pid_path);
}

static gboolean nmcli_active_connection_exists(const gchar* connection_name) {
  gint wait_status = 0;
  g_autoptr(GError) error = nullptr;
  g_autofree gchar* output = nullptr;
  const gchar* argv[] = {"nmcli", "-t", "-f", "NAME,TYPE", "connection", "show", "--active", nullptr};
  if (!g_spawn_sync(nullptr,
                    const_cast<gchar**>(argv),
                    nullptr,
                    G_SPAWN_SEARCH_PATH,
                    nullptr,
                    nullptr,
                    &output,
                    nullptr,
                    &wait_status,
                    &error)) {
    return FALSE;
  }
  if (!g_spawn_check_wait_status(wait_status, nullptr) || output == nullptr) {
    return FALSE;
  }
  g_autofree gchar* expected = g_strdup_printf("%s:vpn", connection_name);
  g_auto(GStrv) lines = g_strsplit(output, "\n", -1);
  for (guint i = 0; lines[i] != nullptr; i++) {
    if (g_strcmp0(lines[i], expected) == 0) {
      return TRUE;
    }
  }
  return FALSE;
}

static gboolean ikev2_route_or_dns_evidence_exists() {
  gint wait_status = 0;
  g_autoptr(GError) error = nullptr;
  g_autofree gchar* output = nullptr;
  const gchar* argv[] = {
      "nmcli", "-t", "-f", "IP4.DNS,IP4.ROUTE,IP6.DNS,IP6.ROUTE",
      "connection", "show", kIkev2ConnectionName, nullptr};
  if (!g_spawn_sync(nullptr,
                    const_cast<gchar**>(argv),
                    nullptr,
                    G_SPAWN_SEARCH_PATH,
                    nullptr,
                    nullptr,
                    &output,
                    nullptr,
                    &wait_status,
                    &error)) {
    return FALSE;
  }
  if (!g_spawn_check_wait_status(wait_status, nullptr) || output == nullptr) {
    return FALSE;
  }
  g_auto(GStrv) lines = g_strsplit(output, "\n", -1);
  for (guint i = 0; lines[i] != nullptr; i++) {
    g_autofree gchar* line = g_strdup(lines[i]);
    g_strstrip(line);
    if (*line == '\0') {
      continue;
    }
    gchar* separator = strchr(line, ':');
    if (separator == nullptr) {
      continue;
    }
    separator++;
    g_strstrip(separator);
    if (*separator != '\0' && g_strcmp0(separator, "--") != 0) {
      return TRUE;
    }
  }
  return FALSE;
}

static gboolean xfrm_state_output_has_esp(const gchar* output) {
  if (output == nullptr) {
    return FALSE;
  }
  g_auto(GStrv) lines = g_strsplit(output, "\n", -1);
  for (guint i = 0; lines[i] != nullptr; i++) {
    g_autofree gchar* line = g_strdup(lines[i]);
    g_strstrip(line);
    if (strstr(line, "proto esp") != nullptr) {
      return TRUE;
    }
  }
  return FALSE;
}

static gboolean ikev2_xfrm_state_evidence_exists() {
  const gchar* no_args[] = {nullptr};
  g_autofree gchar* helper_output = nullptr;
  g_autofree gchar* helper_detail = nullptr;
  if (run_securewave_helper_capture_sync(
          "xfrm-state", no_args, &helper_output, &helper_detail) &&
      xfrm_state_output_has_esp(helper_output)) {
    return TRUE;
  }

  gint wait_status = 0;
  g_autoptr(GError) error = nullptr;
  g_autofree gchar* output = nullptr;
  const gchar* argv[] = {"ip", "xfrm", "state", nullptr};
  if (!g_spawn_sync(nullptr,
                    const_cast<gchar**>(argv),
                    nullptr,
                    G_SPAWN_SEARCH_PATH,
                    nullptr,
                    nullptr,
                    &output,
                    nullptr,
                    &wait_status,
                    &error)) {
    return FALSE;
  }
  return g_spawn_check_wait_status(wait_status, nullptr) &&
         xfrm_state_output_has_esp(output);
}

static gboolean ikev2_runtime_evidence_exists() {
  return nmcli_active_connection_exists(kIkev2ConnectionName) &&
         ikev2_route_or_dns_evidence_exists() &&
         ikev2_xfrm_state_evidence_exists();
}

static gboolean wait_for_ikev2_runtime_evidence() {
  for (guint i = 0; i < 30; i++) {
    if (ikev2_runtime_evidence_exists()) {
      return TRUE;
    }
    g_usleep(1000000);
  }
  return FALSE;
}

static gboolean wait_for_ikev2_stop_evidence() {
  for (guint i = 0; i < 10; i++) {
    if (!nmcli_active_connection_exists(kIkev2ConnectionName)) {
      return TRUE;
    }
    g_usleep(500000);
  }
  return !nmcli_active_connection_exists(kIkev2ConnectionName);
}

static guint64 read_interface_counter(const gchar* interface_name,
                                      const gchar* counter_name) {
  g_autofree gchar* path = g_build_filename(
      "/sys/class/net", interface_name, "statistics", counter_name, nullptr);
  g_autofree gchar* contents = nullptr;
  if (!g_file_get_contents(path, &contents, nullptr, nullptr) || contents == nullptr) {
    return 0;
  }
  g_strstrip(contents);
  return g_ascii_strtoull(contents, nullptr, 10);
}

static gboolean interface_counter_available(const gchar* interface_name) {
  if (interface_name == nullptr || *interface_name == '\0') {
    return FALSE;
  }
  g_autofree gchar* rx_path = g_build_filename(
      "/sys/class/net", interface_name, "statistics", "rx_bytes", nullptr);
  g_autofree gchar* tx_path = g_build_filename(
      "/sys/class/net", interface_name, "statistics", "tx_bytes", nullptr);
  return g_file_test(rx_path, G_FILE_TEST_IS_REGULAR) &&
         g_file_test(tx_path, G_FILE_TEST_IS_REGULAR);
}

static gchar* parse_address_token(const gchar* line, const gchar* key) {
  if (line == nullptr || key == nullptr) {
    return nullptr;
  }
  g_auto(GStrv) parts = g_strsplit_set(line, " \t", -1);
  for (guint i = 0; parts[i] != nullptr; i++) {
    if (*parts[i] == '\0' || g_strcmp0(parts[i], key) != 0) {
      continue;
    }
    for (guint j = i + 1; parts[j] != nullptr; j++) {
      if (*parts[j] != '\0') {
        return g_strdup(parts[j]);
      }
    }
  }
  return nullptr;
}

static GPtrArray* collect_local_ip_addresses() {
  GPtrArray* addresses = g_ptr_array_new_with_free_func(g_free);
  gint wait_status = 0;
  g_autoptr(GError) error = nullptr;
  g_autofree gchar* output = nullptr;
  const gchar* argv[] = {"ip", "-o", "addr", "show", nullptr};
  if (!g_spawn_sync(nullptr,
                    const_cast<gchar**>(argv),
                    nullptr,
                    G_SPAWN_SEARCH_PATH,
                    nullptr,
                    nullptr,
                    &output,
                    nullptr,
                    &wait_status,
                    &error) ||
      !g_spawn_check_wait_status(wait_status, nullptr) ||
      output == nullptr) {
    return addresses;
  }

  g_auto(GStrv) lines = g_strsplit(output, "\n", -1);
  for (guint i = 0; lines[i] != nullptr; i++) {
    g_auto(GStrv) parts = g_strsplit_set(lines[i], " \t", -1);
    for (guint j = 0; parts[j] != nullptr; j++) {
      if (g_strcmp0(parts[j], "inet") != 0 &&
          g_strcmp0(parts[j], "inet6") != 0) {
        continue;
      }
      for (guint k = j + 1; parts[k] != nullptr; k++) {
        if (*parts[k] == '\0') {
          continue;
        }
        g_autofree gchar* address = g_strdup(parts[k]);
        gchar* slash = strchr(address, '/');
        if (slash != nullptr) {
          *slash = '\0';
        }
        if (*address != '\0') {
          g_ptr_array_add(addresses, g_strdup(address));
        }
        break;
      }
      break;
    }
  }
  return addresses;
}

static gboolean address_list_contains(GPtrArray* addresses, const gchar* value) {
  if (addresses == nullptr || value == nullptr || *value == '\0') {
    return FALSE;
  }
  for (guint i = 0; i < addresses->len; i++) {
    const gchar* address = static_cast<const gchar*>(g_ptr_array_index(addresses, i));
    if (g_strcmp0(address, value) == 0) {
      return TRUE;
    }
  }
  return FALSE;
}

static gboolean parse_xfrm_lifetime_bytes(const gchar* line, guint64* bytes) {
  if (line == nullptr || bytes == nullptr) {
    return FALSE;
  }
  const gchar* marker = strstr(line, "(bytes)");
  if (marker == nullptr) {
    return FALSE;
  }
  const gchar* start = marker;
  while (start > line && g_ascii_isdigit(*(start - 1))) {
    start--;
  }
  if (start == marker) {
    return FALSE;
  }
  *bytes = g_ascii_strtoull(start, nullptr, 10);
  return TRUE;
}

static gboolean read_wireguard_transfer_counters(
    guint64* rx_bytes,
    guint64* tx_bytes,
    gchar** detail) {
  if (rx_bytes == nullptr || tx_bytes == nullptr) {
    return FALSE;
  }
  *rx_bytes = 0;
  *tx_bytes = 0;

  g_autofree gchar* output = nullptr;
  g_autofree gchar* helper_detail = nullptr;
  const gchar* no_args[] = {nullptr};
  if (!run_securewave_helper_capture_sync(
          "wireguard-transfer", no_args, &output, &helper_detail)) {
    if (detail != nullptr) {
      *detail = g_strdup(helper_detail != nullptr
                             ? helper_detail
                             : "Unable to read WireGuard transfer counters.");
    }
    return FALSE;
  }
  if (output == nullptr || *output == '\0') {
    if (detail != nullptr) {
      *detail = g_strdup("No WireGuard transfer counters found.");
    }
    return FALSE;
  }

  guint peers = 0;
  g_auto(GStrv) lines = g_strsplit(output, "\n", -1);
  for (guint i = 0; lines[i] != nullptr; i++) {
    g_auto(GStrv) parts = g_strsplit_set(lines[i], " \t", -1);
    guint field = 0;
    guint64 rx = 0;
    guint64 tx = 0;
    for (guint j = 0; parts[j] != nullptr; j++) {
      if (*parts[j] == '\0') {
        continue;
      }
      field++;
      if (field == 2) {
        rx = g_ascii_strtoull(parts[j], nullptr, 10);
      } else if (field == 3) {
        tx = g_ascii_strtoull(parts[j], nullptr, 10);
      }
    }
    if (field >= 3) {
      *rx_bytes += rx;
      *tx_bytes += tx;
      peers++;
    }
  }

  if (peers > 0) {
    return TRUE;
  }
  if (detail != nullptr) {
    *detail = g_strdup("No parseable WireGuard peer transfer counters found.");
  }
  return FALSE;
}

static gboolean parse_ikev2_xfrm_counter_output(
    const gchar* output,
    guint64* rx_bytes,
    guint64* tx_bytes,
    gchar** detail) {
  if (output == nullptr || *output == '\0') {
    if (detail != nullptr) {
      *detail = g_strdup("No IKEv2 XFRM state counters found.");
    }
    return FALSE;
  }

  *rx_bytes = 0;
  *tx_bytes = 0;
  g_autoptr(GPtrArray) local_addresses = collect_local_ip_addresses();
  g_auto(GStrv) lines = g_strsplit(output, "\n", -1);
  g_autofree gchar* current_src = nullptr;
  g_autofree gchar* current_dst = nullptr;
  gboolean awaiting_current_lifetime = FALSE;
  guint classified_states = 0;
  guint unclassified_states = 0;

  for (guint i = 0; lines[i] != nullptr; i++) {
    g_autofree gchar* line = g_strdup(lines[i]);
    g_strstrip(line);
    if (g_str_has_prefix(line, "src ")) {
      g_clear_pointer(&current_src, g_free);
      g_clear_pointer(&current_dst, g_free);
      current_src = parse_address_token(line, "src");
      current_dst = parse_address_token(line, "dst");
      awaiting_current_lifetime = FALSE;
      continue;
    }
    if (strstr(line, "lifetime current:") != nullptr) {
      awaiting_current_lifetime = TRUE;
    }
    if (!awaiting_current_lifetime) {
      continue;
    }
    guint64 state_bytes = 0;
    if (!parse_xfrm_lifetime_bytes(line, &state_bytes)) {
      continue;
    }
    if (address_list_contains(local_addresses, current_dst)) {
      *rx_bytes += state_bytes;
      classified_states++;
    } else if (address_list_contains(local_addresses, current_src)) {
      *tx_bytes += state_bytes;
      classified_states++;
    } else {
      unclassified_states++;
    }
    awaiting_current_lifetime = FALSE;
  }

  if (classified_states > 0) {
    return TRUE;
  }
  if (detail != nullptr) {
    *detail = g_strdup(unclassified_states > 0
                           ? "IKEv2 XFRM counters were present but could not be matched to local tunnel direction."
                           : "No IKEv2 XFRM lifetime byte counters found.");
  }
  return FALSE;
}

static gboolean read_ikev2_xfrm_counters(
    guint64* rx_bytes,
    guint64* tx_bytes,
    gchar** detail) {
  if (rx_bytes == nullptr || tx_bytes == nullptr) {
    return FALSE;
  }
  *rx_bytes = 0;
  *tx_bytes = 0;

  gint wait_status = 0;
  g_autoptr(GError) error = nullptr;
  g_autofree gchar* output = nullptr;
  g_autofree gchar* stderr_text = nullptr;
  const gchar* argv[] = {"ip", "-s", "xfrm", "state", nullptr};
  const gboolean direct_spawned = g_spawn_sync(nullptr,
                                              const_cast<gchar**>(argv),
                                              nullptr,
                                              G_SPAWN_SEARCH_PATH,
                                              nullptr,
                                              nullptr,
                                              &output,
                                              &stderr_text,
                                              &wait_status,
                                              &error);
  if (direct_spawned && g_spawn_check_wait_status(wait_status, nullptr)) {
    g_autofree gchar* parse_detail = nullptr;
    if (parse_ikev2_xfrm_counter_output(output, rx_bytes, tx_bytes, &parse_detail)) {
      return TRUE;
    }
    if (detail != nullptr && parse_detail != nullptr) {
      *detail = g_strdup(parse_detail);
    }
  }

  g_autofree gchar* direct_detail = nullptr;
  if (!direct_spawned) {
    direct_detail = g_strdup(error ? error->message : "Unable to read IKEv2 XFRM counters.");
  } else if (!g_spawn_check_wait_status(wait_status, nullptr)) {
    g_autofree gchar* clean = g_strdup(stderr_text ? stderr_text : "");
    g_strstrip(clean);
    direct_detail = g_strdup(*clean != '\0'
                                 ? clean
                                 : "IKEv2 XFRM counters require elevated network privileges.");
  } else if (detail != nullptr && *detail != nullptr) {
    direct_detail = g_strdup(*detail);
    g_clear_pointer(detail, g_free);
  }

  g_autofree gchar* helper_output = nullptr;
  g_autofree gchar* helper_detail = nullptr;
  const gchar* no_args[] = {nullptr};
  if (run_securewave_helper_capture_sync("xfrm-state", no_args, &helper_output, &helper_detail) &&
      parse_ikev2_xfrm_counter_output(helper_output, rx_bytes, tx_bytes, detail)) {
    return TRUE;
  }

  if (detail != nullptr && *detail == nullptr) {
    *detail = g_strdup(helper_detail != nullptr
                           ? helper_detail
                           : (direct_detail != nullptr
                                  ? direct_detail
                                  : "No readable IKEv2 tunnel counters found."));
  }
  return FALSE;
}

static gchar* traffic_interface_for_protocol(const gchar* protocol) {
  if (g_strcmp0(protocol, "openvpn") == 0) {
    if (g_file_test("/sys/class/net/tun0", G_FILE_TEST_IS_DIR)) {
      return g_strdup("tun0");
    }
    g_autoptr(GDir) dir = g_dir_open("/sys/class/net", 0, nullptr);
    if (dir != nullptr) {
      const gchar* name = nullptr;
      while ((name = g_dir_read_name(dir)) != nullptr) {
        if (g_str_has_prefix(name, "tun")) {
          return g_strdup(name);
        }
      }
    }
    return g_strdup("tun0");
  }
  if (g_strcmp0(protocol, "ikev2") == 0) {
    g_autoptr(GDir) dir = g_dir_open("/sys/class/net", 0, nullptr);
    if (dir != nullptr) {
      const gchar* name = nullptr;
      while ((name = g_dir_read_name(dir)) != nullptr) {
        if (g_str_has_prefix(name, "ipsec") || g_str_has_prefix(name, "xfrm")) {
          return g_strdup(name);
        }
      }
    }
    return g_strdup("ipsec0");
  }
  return g_strdup(kWireGuardInterfaceName);
}

static void respond_traffic_stats(FlMethodCall* method_call, const gchar* protocol) {
  g_autofree gchar* interface_name = traffic_interface_for_protocol(protocol);
  gboolean counters_available = FALSE;
  guint64 rx_bytes = 0;
  guint64 tx_bytes = 0;
  g_autofree gchar* unavailable_reason = nullptr;

  if (g_strcmp0(protocol, "wireguard") == 0) {
    g_autofree gchar* wg_detail = nullptr;
    if (read_wireguard_transfer_counters(&rx_bytes, &tx_bytes, &wg_detail)) {
      counters_available = TRUE;
      g_free(interface_name);
      interface_name = g_strdup(kWireGuardInterfaceName);
    } else {
      unavailable_reason = g_strdup(wg_detail != nullptr
                                        ? wg_detail
                                        : "No readable WireGuard transfer counters found.");
    }
  }

  if (!counters_available) {
    counters_available = interface_counter_available(interface_name);
    rx_bytes = counters_available
        ? read_interface_counter(interface_name, "rx_bytes")
        : 0;
    tx_bytes = counters_available
        ? read_interface_counter(interface_name, "tx_bytes")
        : 0;
  }

  if (!counters_available && g_strcmp0(protocol, "ikev2") == 0) {
    g_autofree gchar* xfrm_detail = nullptr;
    if (read_ikev2_xfrm_counters(&rx_bytes, &tx_bytes, &xfrm_detail)) {
      counters_available = TRUE;
      g_free(interface_name);
      interface_name = g_strdup("xfrm");
      g_clear_pointer(&unavailable_reason, g_free);
    } else {
      g_clear_pointer(&unavailable_reason, g_free);
      unavailable_reason = g_strdup(xfrm_detail != nullptr
                                        ? xfrm_detail
                                        : "No readable IKEv2 tunnel counters found.");
    }
  }

  g_autoptr(FlValue) response = fl_value_new_map();
  fl_value_set_string_take(
      response,
      "interface",
      fl_value_new_string(interface_name));
  fl_value_set_string_take(
      response,
      "rx_bytes",
      fl_value_new_int(static_cast<int64_t>(rx_bytes)));
  fl_value_set_string_take(
      response,
      "tx_bytes",
      fl_value_new_int(static_cast<int64_t>(tx_bytes)));
  fl_value_set_string_take(
      response,
      "counters_available",
      fl_value_new_bool(counters_available));
  if (!counters_available) {
    if (unavailable_reason == nullptr) {
      unavailable_reason = g_strdup_printf(
          "No readable %s rx_bytes/tx_bytes counters found.",
          interface_name);
    }
    fl_value_set_string_take(
        response,
        "unavailable_reason",
        fl_value_new_string(unavailable_reason));
  }
  g_autoptr(FlMethodResponse) method_response = FL_METHOD_RESPONSE(
      fl_method_success_response_new(response));
  fl_method_call_respond(method_call, method_response, nullptr);
}

static void wg_quick_child_watch_cb(GPid pid, gint wait_status, gpointer user_data) {
  WgQuickSpawnContext* ctx = static_cast<WgQuickSpawnContext*>(user_data);
  if (ctx->timeout_id != 0) {
    g_source_remove(ctx->timeout_id);
    ctx->timeout_id = 0;
  }
  g_autofree gchar* stdout_text = read_fd_to_string(&ctx->stdout_fd);
  g_autofree gchar* stderr_text = read_fd_to_string(&ctx->stderr_fd);
  g_autoptr(GError) error = nullptr;
  if (!g_spawn_check_wait_status(wait_status, &error)) {
    g_autofree gchar* message = command_failure_message(
        error ? error->message : "VPN helper command failed.",
        stdout_text,
        stderr_text);
    wg_quick_respond_error_once(ctx, message);
  } else {
    if (ctx->verify_wireguard_interface) {
      const gboolean exists = wireguard_interface_exists();
      if (g_strcmp0(ctx->action, "up") == 0 && !exists) {
        g_autofree gchar* message = g_strdup_printf(
            "WireGuard command completed but interface %s was not found.",
            kWireGuardInterfaceName);
        wg_quick_respond_error_once(
            ctx,
            message);
        g_spawn_close_pid(pid);
        return;
      }
      if (g_strcmp0(ctx->action, "up") == 0 && !wireguard_route_exists()) {
        g_autofree gchar* message = g_strdup_printf(
            "WireGuard command completed but route traffic was not using interface %s.",
            kWireGuardInterfaceName);
        wg_quick_respond_error_once(
            ctx,
            message);
        g_spawn_close_pid(pid);
        return;
      }
      if (g_strcmp0(ctx->action, "down") == 0 && exists) {
        g_autofree gchar* message = g_strdup_printf(
            "WireGuard command completed but interface %s is still present.",
            kWireGuardInterfaceName);
        wg_quick_respond_error_once(
            ctx,
            message);
        g_spawn_close_pid(pid);
        return;
      }
    }
    if (ctx->verify_openvpn_started) {
      if (!wait_for_openvpn_runtime_evidence(ctx->openvpn_pid_path, ctx->openvpn_log_path)) {
        g_autofree gchar* log_tail = openvpn_log_tail(ctx->openvpn_log_path);
        g_autofree gchar* message = g_strdup_printf(
            "OpenVPN process started but Initialization Sequence Completed and tunnel route evidence were not detected.%s%s",
            log_tail != nullptr ? " Last log lines: " : "",
            log_tail != nullptr ? log_tail : "");
        stop_openvpn_after_failed_start(ctx->openvpn_pid_path);
        remove_openvpn_pid_file(ctx->openvpn_pid_path);
        wg_quick_respond_error_once(ctx, message);
        g_spawn_close_pid(pid);
        return;
      }
    }
    if (ctx->verify_openvpn_stopped) {
      if (!wait_for_openvpn_stop_evidence(ctx->openvpn_pid_path)) {
        wg_quick_respond_error_once(
            ctx,
            "OpenVPN stop command completed but process or tunnel route evidence remains.");
        g_spawn_close_pid(pid);
        return;
      }
      remove_openvpn_pid_file(ctx->openvpn_pid_path);
    }
    wg_quick_respond_ok_once(ctx);
  }
  g_spawn_close_pid(pid);
}

static gboolean wg_quick_timeout_cb(gpointer user_data) {
  WgQuickSpawnContext* ctx = static_cast<WgQuickSpawnContext*>(user_data);
  ctx->timeout_id = 0;
  wg_quick_respond_error_once(
      ctx,
      "VPN operation timed out. Ensure you have the required permissions and retry.");
  if (ctx->pid != 0) {
    kill(ctx->pid, SIGKILL);
  }
  return G_SOURCE_REMOVE;
}

static void spawn_wg_quick_async(
    FlMethodCall* method_call,
    const gchar* error_code,
    const gchar* action,
    const gchar* config_path,
    gboolean verify_interface) {
  g_autoptr(GError) error = nullptr;
  g_autofree gchar* wg_quick = g_find_program_in_path("wg-quick");
  if (wg_quick == nullptr) {
    respond_error(
        method_call,
        "vpn_unavailable",
        "wg-quick not found. Install wireguard-tools and retry.",
        nullptr);
    return;
  }

  g_autofree gchar* pkexec = nullptr;
  GPtrArray* argv_array = g_ptr_array_new();
  if (geteuid() != 0) {
    pkexec = g_find_program_in_path("pkexec");
    if (pkexec == nullptr) {
      g_ptr_array_free(argv_array, TRUE);
      respond_error(
          method_call,
          "vpn_permission_required",
          "Starting WireGuard requires administrator privileges. Install PolicyKit/pkexec or run SecureWave with the required permissions.",
          nullptr);
      return;
    }
    g_ptr_array_add(argv_array, pkexec);
    g_ptr_array_add(argv_array, const_cast<gchar*>("--disable-internal-agent"));
    if (wireguard_helper_available()) {
      g_ptr_array_add(argv_array, const_cast<gchar*>(kWireGuardHelperPath));
    } else {
      g_ptr_array_add(argv_array, wg_quick);
    }
  } else {
    g_ptr_array_add(argv_array, wg_quick);
  }
  g_ptr_array_add(argv_array, const_cast<gchar*>(action));
  g_ptr_array_add(argv_array, const_cast<gchar*>(config_path));
  g_ptr_array_add(argv_array, nullptr);
  gchar** argv = reinterpret_cast<gchar**>(argv_array->pdata);

  GPid pid = 0;
  gint stdout_fd = -1;
  gint stderr_fd = -1;
  if (!g_spawn_async_with_pipes(
          nullptr,
          argv,
          nullptr,
          static_cast<GSpawnFlags>(G_SPAWN_SEARCH_PATH | G_SPAWN_DO_NOT_REAP_CHILD),
          nullptr,
          nullptr,
          &pid,
          nullptr,
          &stdout_fd,
          &stderr_fd,
          &error)) {
    g_ptr_array_free(argv_array, TRUE);
    respond_error(method_call, error_code, error ? error->message : "Failed to spawn wg-quick.", nullptr);
    return;
  }
  g_ptr_array_free(argv_array, TRUE);

  WgQuickSpawnContext* ctx = g_new0(WgQuickSpawnContext, 1);
  ctx->ref_count = 1;
  ctx->method_call = FL_METHOD_CALL(g_object_ref(method_call));
  ctx->error_code = g_strdup(error_code);
  ctx->action = g_strdup(action);
  ctx->pid = pid;
  ctx->timeout_ms = kWgQuickTimeoutMs;
  ctx->responded = FALSE;
  ctx->verify_wireguard_interface = verify_interface;
  ctx->stdout_fd = stdout_fd;
  ctx->stderr_fd = stderr_fd;
  g_child_watch_add_full(
      G_PRIORITY_DEFAULT,
      pid,
      wg_quick_child_watch_cb,
      wg_quick_spawn_context_ref(ctx),
      reinterpret_cast<GDestroyNotify>(wg_quick_spawn_context_unref));
  ctx->timeout_id = g_timeout_add_full(
      G_PRIORITY_DEFAULT,
      ctx->timeout_ms,
      wg_quick_timeout_cb,
      wg_quick_spawn_context_ref(ctx),
      reinterpret_cast<GDestroyNotify>(wg_quick_spawn_context_unref));
  wg_quick_spawn_context_unref(ctx);
}

static void spawn_openvpn_up_async(
    FlMethodCall* method_call,
    const gchar* config_path,
    const gchar* pid_path,
    const gchar* log_path) {
  g_autofree gchar* openvpn = g_find_program_in_path("openvpn");
  if (openvpn == nullptr) {
    respond_error(method_call, "vpn_unavailable", "openvpn not found. Install OpenVPN and retry.", nullptr);
    return;
  }
  if (!wireguard_helper_available()) {
    respond_error(
        method_call,
        "vpn_unavailable",
        "SecureWave VPN helper not found. Reinstall SecureWave and retry.",
        nullptr);
    return;
  }
  g_autofree gchar* helper_detail = nullptr;
  if (!securewave_helper_contract_available(&helper_detail)) {
    respond_error(
        method_call,
        "vpn_unavailable",
        helper_detail != nullptr ? helper_detail : "SecureWave VPN helper is out of date. Reinstall SecureWave and retry.",
        nullptr);
    return;
  }

  g_autoptr(GError) error = nullptr;
  g_autofree gchar* pkexec = nullptr;
  GPtrArray* argv_array = g_ptr_array_new();
  if (geteuid() != 0) {
    pkexec = g_find_program_in_path("pkexec");
    if (pkexec == nullptr) {
      g_ptr_array_free(argv_array, TRUE);
      respond_error(
          method_call,
          "vpn_permission_required",
          "Starting OpenVPN requires administrator privileges. Install PolicyKit/pkexec or run SecureWave with the required permissions.",
          nullptr);
      return;
    }
    g_ptr_array_add(argv_array, pkexec);
    g_ptr_array_add(argv_array, const_cast<gchar*>("--disable-internal-agent"));
  }
  g_ptr_array_add(argv_array, const_cast<gchar*>(kWireGuardHelperPath));
  g_ptr_array_add(argv_array, const_cast<gchar*>("openvpn-start"));
  g_ptr_array_add(argv_array, const_cast<gchar*>(config_path));
  g_ptr_array_add(argv_array, const_cast<gchar*>(pid_path));
  g_ptr_array_add(argv_array, const_cast<gchar*>(log_path));
  g_ptr_array_add(argv_array, nullptr);
  gchar** argv = reinterpret_cast<gchar**>(argv_array->pdata);

  GPid pid = 0;
  gint stdout_fd = -1;
  gint stderr_fd = -1;
  if (!g_spawn_async_with_pipes(
          nullptr,
          argv,
          nullptr,
          static_cast<GSpawnFlags>(G_SPAWN_SEARCH_PATH | G_SPAWN_DO_NOT_REAP_CHILD),
          nullptr,
          nullptr,
          &pid,
          nullptr,
          &stdout_fd,
          &stderr_fd,
          &error)) {
    g_ptr_array_free(argv_array, TRUE);
    respond_error(method_call, "vpn_connect_failed", error ? error->message : "Failed to spawn OpenVPN helper.", nullptr);
    return;
  }
  g_ptr_array_free(argv_array, TRUE);

  WgQuickSpawnContext* ctx = g_new0(WgQuickSpawnContext, 1);
  ctx->ref_count = 1;
  ctx->method_call = FL_METHOD_CALL(g_object_ref(method_call));
  ctx->error_code = g_strdup("vpn_connect_failed");
  ctx->action = g_strdup("openvpn-up");
  ctx->pid = pid;
  ctx->timeout_ms = kOpenVpnTimeoutMs;
  ctx->responded = FALSE;
  ctx->verify_openvpn_started = TRUE;
  ctx->openvpn_pid_path = g_strdup(pid_path);
  ctx->openvpn_log_path = g_strdup(log_path);
  ctx->stdout_fd = stdout_fd;
  ctx->stderr_fd = stderr_fd;
  g_child_watch_add_full(
      G_PRIORITY_DEFAULT,
      pid,
      wg_quick_child_watch_cb,
      wg_quick_spawn_context_ref(ctx),
      reinterpret_cast<GDestroyNotify>(wg_quick_spawn_context_unref));
  ctx->timeout_id = g_timeout_add_full(
      G_PRIORITY_DEFAULT,
      ctx->timeout_ms,
      wg_quick_timeout_cb,
      wg_quick_spawn_context_ref(ctx),
      reinterpret_cast<GDestroyNotify>(wg_quick_spawn_context_unref));
  wg_quick_spawn_context_unref(ctx);
}

static void spawn_openvpn_down_async(
    FlMethodCall* method_call,
    const gchar* pid_path) {
  GPid openvpn_pid = 0;
  if (!read_pid_from_file(pid_path, &openvpn_pid)) {
    if (openvpn_route_exists()) {
      respond_error(
          method_call,
          "vpn_disconnect_failed",
          "OpenVPN PID file is missing but tunnel route evidence remains.",
          nullptr);
      return;
    }
    remove_openvpn_pid_file(pid_path);
    respond_success(method_call);
    return;
  }
  if (!wireguard_helper_available()) {
    respond_error(
        method_call,
        "vpn_unavailable",
        "SecureWave VPN helper not found. Reinstall SecureWave and retry.",
        nullptr);
    return;
  }

  g_autoptr(GError) error = nullptr;
  g_autofree gchar* pkexec = nullptr;
  g_autofree gchar* pid_arg = g_strdup_printf("%d", static_cast<int>(openvpn_pid));
  GPtrArray* argv_array = g_ptr_array_new();
  if (geteuid() != 0) {
    pkexec = g_find_program_in_path("pkexec");
    if (pkexec == nullptr) {
      g_ptr_array_free(argv_array, TRUE);
      respond_error(
          method_call,
          "vpn_permission_required",
          "Stopping OpenVPN requires administrator privileges. Install PolicyKit/pkexec or run SecureWave with the required permissions.",
          nullptr);
      return;
    }
    g_ptr_array_add(argv_array, pkexec);
    g_ptr_array_add(argv_array, const_cast<gchar*>("--disable-internal-agent"));
  }
  g_ptr_array_add(argv_array, const_cast<gchar*>(kWireGuardHelperPath));
  g_ptr_array_add(argv_array, const_cast<gchar*>("openvpn-stop"));
  g_ptr_array_add(argv_array, pid_arg);
  g_ptr_array_add(argv_array, nullptr);
  gchar** argv = reinterpret_cast<gchar**>(argv_array->pdata);

  GPid pid = 0;
  gint stdout_fd = -1;
  gint stderr_fd = -1;
  if (!g_spawn_async_with_pipes(
          nullptr,
          argv,
          nullptr,
          static_cast<GSpawnFlags>(G_SPAWN_SEARCH_PATH | G_SPAWN_DO_NOT_REAP_CHILD),
          nullptr,
          nullptr,
          &pid,
          nullptr,
          &stdout_fd,
          &stderr_fd,
          &error)) {
    g_ptr_array_free(argv_array, TRUE);
    respond_error(method_call, "vpn_disconnect_failed", error ? error->message : "Failed to spawn OpenVPN helper.", nullptr);
    return;
  }
  g_ptr_array_free(argv_array, TRUE);

  WgQuickSpawnContext* ctx = g_new0(WgQuickSpawnContext, 1);
  ctx->ref_count = 1;
  ctx->method_call = FL_METHOD_CALL(g_object_ref(method_call));
  ctx->error_code = g_strdup("vpn_disconnect_failed");
  ctx->action = g_strdup("openvpn-down");
  ctx->pid = pid;
  ctx->timeout_ms = kOpenVpnTimeoutMs;
  ctx->responded = FALSE;
  ctx->verify_openvpn_stopped = TRUE;
  ctx->openvpn_pid_path = g_strdup(pid_path);
  ctx->stdout_fd = stdout_fd;
  ctx->stderr_fd = stderr_fd;
  g_child_watch_add_full(
      G_PRIORITY_DEFAULT,
      pid,
      wg_quick_child_watch_cb,
      wg_quick_spawn_context_ref(ctx),
      reinterpret_cast<GDestroyNotify>(wg_quick_spawn_context_unref));
  ctx->timeout_id = g_timeout_add_full(
      G_PRIORITY_DEFAULT,
      ctx->timeout_ms,
      wg_quick_timeout_cb,
      wg_quick_spawn_context_ref(ctx),
      reinterpret_cast<GDestroyNotify>(wg_quick_spawn_context_unref));
  wg_quick_spawn_context_unref(ctx);
}

typedef struct {
  FlMethodCall* method_call;
  gchar* error_code;
  gboolean connect;
  gchar* server;
  gchar* username;
  gchar* password;
  gchar* remote_id;
  gchar* ca_cert_path;
} Ikev2TaskContext;

static void ikev2_task_context_free(Ikev2TaskContext* ctx) {
  if (ctx == nullptr) {
    return;
  }
  g_clear_object(&ctx->method_call);
  g_clear_pointer(&ctx->error_code, g_free);
  g_clear_pointer(&ctx->server, g_free);
  g_clear_pointer(&ctx->username, g_free);
  g_clear_pointer(&ctx->password, g_free);
  g_clear_pointer(&ctx->remote_id, g_free);
  g_clear_pointer(&ctx->ca_cert_path, g_free);
  g_free(ctx);
}

static void ikev2_task_worker(GTask* task,
                              gpointer source_object,
                              gpointer task_data,
                              GCancellable* cancellable) {
  (void)source_object;
  (void)cancellable;
  Ikev2TaskContext* ctx = static_cast<Ikev2TaskContext*>(task_data);
  g_autofree gchar* detail = nullptr;

  if (ctx->connect) {
    const gchar* delete_args[] = {nullptr};
    run_securewave_helper_sync("ikev2-delete", delete_args, nullptr);

    const gchar* add_args[] = {
        ctx->server, ctx->username, ctx->password, ctx->remote_id, ctx->ca_cert_path, nullptr};
    if (!run_securewave_helper_sync("ikev2-add-eap", add_args, &detail)) {
      g_task_return_new_error(
          task,
          G_IO_ERROR,
          G_IO_ERROR_FAILED,
          "Failed to configure IKEv2 NetworkManager profile with CA certificate: %s",
          detail ? detail : "unknown helper error");
      return;
    }

    const gchar* no_args[] = {nullptr};
    g_clear_pointer(&detail, g_free);
    if (!run_securewave_helper_sync("ikev2-up", no_args, &detail)) {
      run_securewave_helper_sync("ikev2-down", no_args, nullptr);
      run_securewave_helper_sync("ikev2-delete", no_args, nullptr);
      g_task_return_new_error(
          task,
          G_IO_ERROR,
          G_IO_ERROR_FAILED,
          "Failed to start IKEv2 NetworkManager connection: %s",
          detail ? detail : "unknown helper error");
      return;
    }

    if (!wait_for_ikev2_runtime_evidence()) {
      run_securewave_helper_sync("ikev2-down", no_args, nullptr);
      run_securewave_helper_sync("ikev2-delete", no_args, nullptr);
      g_task_return_new_error(
          task,
          G_IO_ERROR,
          G_IO_ERROR_FAILED,
          "IKEv2 command completed but active NetworkManager VPN route/DNS and XFRM ESP evidence was not detected.");
      return;
    }

    g_task_return_boolean(task, TRUE);
    return;
  }

  const gchar* no_args[] = {nullptr};
  run_securewave_helper_sync("ikev2-down", no_args, nullptr);
  run_securewave_helper_sync("ikev2-delete", no_args, nullptr);
  if (!wait_for_ikev2_stop_evidence()) {
    g_task_return_new_error(
        task,
        G_IO_ERROR,
        G_IO_ERROR_FAILED,
        "IKEv2 stop command completed but active NetworkManager VPN evidence remains.");
    return;
  }
  g_task_return_boolean(task, TRUE);
}

static void ikev2_task_complete(GObject* source_object,
                                GAsyncResult* result,
                                gpointer user_data) {
  (void)source_object;
  Ikev2TaskContext* ctx = static_cast<Ikev2TaskContext*>(user_data);
  g_autoptr(GError) error = nullptr;
  const gboolean ok = g_task_propagate_boolean(G_TASK(result), &error);
  if (ok) {
    respond_success(ctx->method_call);
  } else {
    respond_error(
        ctx->method_call,
        ctx->error_code,
        error ? error->message : "IKEv2 operation failed.",
        nullptr);
  }
  ikev2_task_context_free(ctx);
}

static void run_ikev2_task(Ikev2TaskContext* ctx) {
  g_autoptr(GTask) task = g_task_new(nullptr, nullptr, ikev2_task_complete, ctx);
  g_task_set_task_data(task, ctx, nullptr);
  g_task_run_in_thread(task, ikev2_task_worker);
}

static void spawn_ikev2_up_async(
    FlMethodCall* method_call,
    const gchar* config_path) {
  if (!ikev2_tooling_available()) {
    respond_error(
        method_call,
        "vpn_unavailable",
        "IKEv2 requires NetworkManager strongSwan tooling, ipsec, and the SecureWave helper. Install network-manager-strongswan and retry.",
        fl_value_new_map());
    return;
  }
  g_autofree gchar* helper_detail = nullptr;
  if (!securewave_helper_contract_available(&helper_detail)) {
    respond_error(
        method_call,
        "vpn_unavailable",
        helper_detail ? helper_detail : "SecureWave VPN helper is unavailable.",
        fl_value_new_map());
    return;
  }

  g_autofree gchar* config = nullptr;
  g_autoptr(GError) file_error = nullptr;
  if (!g_file_get_contents(config_path, &config, nullptr, &file_error) || config == nullptr) {
    respond_error(
        method_call,
        "vpn_config_missing",
        file_error ? file_error->message : "IKEv2 config file not found.",
        nullptr);
    return;
  }

  g_autofree gchar* server = parse_config_value(config, "remote_addrs");
  g_autofree gchar* username = parse_config_value(config, "eap_id");
  g_autofree gchar* password = parse_config_value(config, "secret");
  g_autofree gchar* remote_id = parse_ikev2_remote_id(config);
  g_autofree gchar* ca_cert_pem = parse_ikev2_ca_cert_pem(config);
  if (server == nullptr || *server == '\0' ||
      username == nullptr || *username == '\0' ||
      password == nullptr || *password == '\0' ||
      ca_cert_pem == nullptr || *ca_cert_pem == '\0') {
    respond_error(
        method_call,
        "invalid_config",
        "IKEv2 profile is missing server, username, EAP secret, or CA certificate.",
        nullptr);
    return;
  }

  g_autofree gchar* ca_cert_path = build_state_path(kIkev2CaFileName);
  if (ca_cert_path == nullptr) {
    respond_error(method_call, "vpn_config_write_failed", "Unable to write IKEv2 CA certificate file.", nullptr);
    return;
  }
  g_autoptr(GError) write_error = nullptr;
  if (!g_file_set_contents(ca_cert_path, ca_cert_pem, -1, &write_error)) {
    respond_error(
        method_call,
        "vpn_config_write_failed",
        write_error ? write_error->message : "Unable to write IKEv2 CA certificate file.",
        nullptr);
    return;
  }
  g_chmod(ca_cert_path, 0600);

  Ikev2TaskContext* ctx = g_new0(Ikev2TaskContext, 1);
  ctx->method_call = FL_METHOD_CALL(g_object_ref(method_call));
  ctx->error_code = g_strdup("vpn_connect_failed");
  ctx->connect = TRUE;
  ctx->server = g_strdup(server);
  ctx->username = g_strdup(username);
  ctx->password = g_strdup(password);
  ctx->remote_id = g_strdup(remote_id != nullptr ? remote_id : server);
  ctx->ca_cert_path = g_strdup(ca_cert_path);
  run_ikev2_task(ctx);
}

static void spawn_ikev2_down_async(FlMethodCall* method_call) {
  Ikev2TaskContext* ctx = g_new0(Ikev2TaskContext, 1);
  ctx->method_call = FL_METHOD_CALL(g_object_ref(method_call));
  ctx->error_code = g_strdup("vpn_disconnect_failed");
  ctx->connect = FALSE;
  run_ikev2_task(ctx);
}

static gboolean active_runtime_evidence_exists(
    VpnChannelState* state,
    const gchar* protocol) {
  if (g_strcmp0(protocol, "openvpn") == 0) {
    if (!state->openvpn_pid_path) {
      state->openvpn_pid_path = build_state_path(kOpenVpnPidFileName);
    }
    if (!state->openvpn_log_path) {
      state->openvpn_log_path = build_state_path(kOpenVpnLogFileName);
    }
    return state->openvpn_pid_path != nullptr &&
           state->openvpn_log_path != nullptr &&
           openvpn_runtime_evidence_exists(state->openvpn_pid_path, state->openvpn_log_path);
  }
  if (g_strcmp0(protocol, "ikev2") == 0) {
    return ikev2_runtime_evidence_exists();
  }
  return wireguard_interface_exists() && wireguard_route_exists();
}

static void respond_runtime_status(
    FlMethodCall* method_call,
    VpnChannelState* state) {
  const gchar* protocol = load_active_protocol(state);
  const gboolean connected = active_runtime_evidence_exists(state, protocol);
  g_autoptr(FlValue) response = fl_value_new_map();
  fl_value_set_string_take(
      response,
      "status",
      fl_value_new_string(connected ? "connected" : "disconnected"));
  fl_value_set_string_take(
      response,
      "protocol",
      fl_value_new_string(protocol));
  g_autoptr(FlMethodResponse) method_response = FL_METHOD_RESPONSE(
      fl_method_success_response_new(response));
  fl_method_call_respond(method_call, method_response, nullptr);
}

static void handle_vpn_call(FlMethodChannel* channel,
                            FlMethodCall* method_call,
                            gpointer user_data) {
  (void)channel;  // Unused; the channel is already held in VpnChannelState.
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
    if (!protocol || *protocol == '\0') {
      protocol = load_active_protocol(state);
    }
    respond_traffic_stats(method_call, protocol);
    return;
  }
  if (g_strcmp0(method, "connect") == 0) {
    FlValue* args = fl_method_call_get_args(method_call);
    const gchar* protocol = get_string_arg(args, "protocol");
    if (!protocol || *protocol == '\0') {
      protocol = "wireguard";
    }
    const gchar* config = get_string_arg(args, "config");
    if (!config || *config == '\0') {
      respond_error(method_call, "invalid_config", "Missing VPN configuration.", nullptr);
      return;
    }

    if (g_strcmp0(protocol, "wireguard") == 0) {
      if (!wg_quick_available()) {
        respond_error(
            method_call,
            "vpn_unavailable",
            "wg-quick not found. Install wireguard-tools (e.g. sudo apt-get install wireguard-tools) and retry.",
            fl_value_new_map());
        return;
      }
      g_clear_pointer(&state->config_path, g_free);
      state->config_path = build_state_path(kWireGuardConfigFileName);
      if (state->config_path == nullptr) {
        respond_error(method_call, "vpn_config_write_failed", "Unable to write config file.", nullptr);
        return;
      }
      g_autoptr(GError) error = nullptr;
      if (!g_file_set_contents(state->config_path, config, -1, &error)) {
        respond_error(method_call, "vpn_config_write_failed", error->message, nullptr);
        return;
      }
      g_chmod(state->config_path, 0600);
      persist_active_protocol(state, "wireguard");
      spawn_wg_quick_async(method_call, "vpn_connect_failed", "up", state->config_path, TRUE);
      return;
    }

    if (g_strcmp0(protocol, "openvpn") == 0) {
      if (!openvpn_available()) {
        respond_error(
            method_call,
            "vpn_unavailable",
            "openvpn not found. Install OpenVPN (e.g. sudo apt-get install openvpn) and retry.",
            fl_value_new_map());
        return;
      }
      g_clear_pointer(&state->config_path, g_free);
      g_clear_pointer(&state->openvpn_pid_path, g_free);
      g_clear_pointer(&state->openvpn_log_path, g_free);
      state->config_path = build_state_path(kOpenVpnConfigFileName);
      state->openvpn_pid_path = build_state_path(kOpenVpnPidFileName);
      state->openvpn_log_path = build_state_path(kOpenVpnLogFileName);
      if (state->config_path == nullptr || state->openvpn_pid_path == nullptr || state->openvpn_log_path == nullptr) {
        respond_error(method_call, "vpn_config_write_failed", "Unable to write OpenVPN state files.", nullptr);
        return;
      }
      g_autoptr(GError) error = nullptr;
      if (!g_file_set_contents(state->config_path, config, -1, &error)) {
        respond_error(method_call, "vpn_config_write_failed", error->message, nullptr);
        return;
      }
      g_chmod(state->config_path, 0600);
      persist_active_protocol(state, "openvpn");
      spawn_openvpn_up_async(method_call, state->config_path, state->openvpn_pid_path, state->openvpn_log_path);
      return;
    }

    if (g_strcmp0(protocol, "ikev2") == 0) {
      if (!ikev2_available()) {
        respond_error(
            method_call,
            "vpn_unavailable",
            "IKEv2 requires NetworkManager strongSwan tooling, ipsec, and the SecureWave helper. Install network-manager-strongswan and retry.",
            fl_value_new_map());
        return;
      }
      g_clear_pointer(&state->config_path, g_free);
      state->config_path = build_state_path(kIkev2ConfigFileName);
      if (state->config_path == nullptr) {
        respond_error(method_call, "vpn_config_write_failed", "Unable to write IKEv2 config file.", nullptr);
        return;
      }
      g_autoptr(GError) error = nullptr;
      if (!g_file_set_contents(state->config_path, config, -1, &error)) {
        respond_error(method_call, "vpn_config_write_failed", error->message, nullptr);
        return;
      }
      g_chmod(state->config_path, 0600);
      persist_active_protocol(state, "ikev2");
      spawn_ikev2_up_async(method_call, state->config_path);
      return;
    }

    respond_error(method_call, "protocol_unavailable", "Unsupported VPN protocol.", nullptr);
    return;
  }
  if (g_strcmp0(method, "disconnect") == 0) {
    const gchar* active_protocol = load_active_protocol(state);
    if (g_strcmp0(active_protocol, "openvpn") == 0) {
      if (!state->openvpn_pid_path) {
        state->openvpn_pid_path = build_state_path(kOpenVpnPidFileName);
      }
      if (!state->openvpn_pid_path) {
        respond_error(method_call, "vpn_config_missing", "OpenVPN PID file path unavailable.", nullptr);
        return;
      }
      spawn_openvpn_down_async(method_call, state->openvpn_pid_path);
      return;
    }

    if (g_strcmp0(active_protocol, "ikev2") == 0) {
      spawn_ikev2_down_async(method_call);
      return;
    }

    if (!wg_quick_available()) {
      respond_error(
          method_call,
          "vpn_unavailable",
          "wg-quick not found. Install wireguard-tools (e.g. sudo apt-get install wireguard-tools) and retry.",
          fl_value_new_map());
      return;
    }
    if (!state->config_path || !g_file_test(state->config_path, G_FILE_TEST_EXISTS)) {
      state->config_path = build_state_path(kWireGuardConfigFileName);
    }
    if (!state->config_path || !g_file_test(state->config_path, G_FILE_TEST_EXISTS)) {
      respond_error(method_call, "vpn_config_missing", "WireGuard config file not found.", nullptr);
      return;
    }
    spawn_wg_quick_async(method_call, "vpn_disconnect_failed", "down", state->config_path, TRUE);
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

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  // gtk_widget_get_toplevel is deprecated in GTK 3.24 (preparing for GTK4)
  // but remains the correct API for GTK3 Flutter embedder builds.
  G_GNUC_BEGIN_IGNORE_DEPRECATIONS
  GtkWidget* toplevel = gtk_widget_get_toplevel(GTK_WIDGET(view));
  G_GNUC_END_IGNORE_DEPRECATIONS
  gtk_widget_show(toplevel);
}

// Implements GApplication::activate.
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

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
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
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  // gtk_container_add is deprecated in GTK 3.24 (preparing for GTK4) but
  // remains required for the GTK3 Flutter embedder.
  G_GNUC_BEGIN_IGNORE_DEPRECATIONS
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));
  G_GNUC_END_IGNORE_DEPRECATIONS

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  // gtk_widget_realize is deprecated in GTK 3.24, but still used by the GTK3
  // Flutter embedder to ensure the view is ready before rendering starts.
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
}

// Implements GApplication::command_line. Secondary launches are forwarded to
// the primary process, which presents the existing window instead of creating
// another Flutter engine.
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

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
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
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID,
                                     "flags", G_APPLICATION_HANDLES_COMMAND_LINE,
                                     nullptr));
}
