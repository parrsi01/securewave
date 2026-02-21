#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif
#include <gio/gio.h>
#include <glib/gstdio.h>
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
const char* kWireGuardConfigFileName = "securewave-wireguard.conf";
const char* kOpenVpnConfigFileName = "securewave-openvpn.ovpn";
const char* kOpenVpnAuthFileName = "securewave-openvpn.auth";
const char* kOpenVpnPidFileName = "securewave-openvpn.pid";
const char* kIkev2ConnectionName = "SecureWave-IKEv2";
const guint kWgQuickTimeoutMs = 30000;

typedef struct {
  FlMethodChannel* channel;
  gchar* wg_config_path;
  gchar* openvpn_config_path;
  gchar* openvpn_auth_path;
  gchar* openvpn_pid_path;
  gchar* active_protocol;
  gboolean last_connected;
} VpnChannelState;

static void vpn_channel_state_free(VpnChannelState* state) {
  if (!state) {
    return;
  }
  g_clear_object(&state->channel);
  g_clear_pointer(&state->wg_config_path, g_free);
  g_clear_pointer(&state->openvpn_config_path, g_free);
  g_clear_pointer(&state->openvpn_auth_path, g_free);
  g_clear_pointer(&state->openvpn_pid_path, g_free);
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

static FlValue* get_map_arg(FlValue* args, const gchar* key) {
  if (!args || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return nullptr;
  }
  FlValue* value = fl_value_lookup_string(args, key);
  if (!value || fl_value_get_type(value) != FL_VALUE_TYPE_MAP) {
    return nullptr;
  }
  return value;
}

static const gchar* get_string_from_map(FlValue* map, const gchar* key) {
  if (!map || fl_value_get_type(map) != FL_VALUE_TYPE_MAP) {
    return nullptr;
  }
  FlValue* value = fl_value_lookup_string(map, key);
  if (!value || fl_value_get_type(value) != FL_VALUE_TYPE_STRING) {
    return nullptr;
  }
  return fl_value_get_string(value);
}

static gboolean wg_quick_available() {
  g_autofree gchar* wg_quick = g_find_program_in_path("wg-quick");
  return wg_quick != nullptr;
}

static gboolean openvpn_available() {
  g_autofree gchar* openvpn = g_find_program_in_path("openvpn");
  return openvpn != nullptr;
}

static gboolean nmcli_available() {
  g_autofree gchar* nmcli = g_find_program_in_path("nmcli");
  return nmcli != nullptr;
}

static gboolean ipsec_available() {
  g_autofree gchar* ipsec = g_find_program_in_path("ipsec");
  return ipsec != nullptr;
}

static gboolean pkexec_available() {
  g_autofree gchar* pkexec = g_find_program_in_path("pkexec");
  return pkexec != nullptr;
}

static gboolean has_desktop_auth_session() {
  const gchar* display = g_getenv("DISPLAY");
  if (display && *display != '\0') {
    return TRUE;
  }
  const gchar* wayland_display = g_getenv("WAYLAND_DISPLAY");
  if (wayland_display && *wayland_display != '\0') {
    return TRUE;
  }
  return FALSE;
}

static gboolean elevation_available() {
  if (geteuid() == 0) {
    return TRUE;
  }
  // GUI apps can't reliably prompt for sudo passwords; prefer pkexec + a
  // desktop auth session so users get a permission dialog instead of a silent
  // shell failure path.
  return pkexec_available() && has_desktop_auth_session();
}

static gboolean native_vpn_available() {
  const gboolean can_elevate = elevation_available();
  if (!can_elevate) {
    return FALSE;
  }
  return wg_quick_available() || openvpn_available() ||
         (nmcli_available() && ipsec_available());
}

static const gchar* wireguard_install_hint_message() {
  return "Install wireguard-tools (e.g. sudo apt-get install wireguard-tools) and retry.";
}

static const gchar* openvpn_install_hint_message() {
  return "Install OpenVPN (e.g. sudo apt-get install openvpn) and retry.";
}

static const gchar* ikev2_install_hint_message() {
  return "IKEv2 on Linux requires system components. Install NetworkManager, "
         "network-manager-strongswan, and strongSwan (ipsec), then retry.";
}

static const gchar* elevation_hint_message() {
  return "Administrator privileges are required. Install PolicyKit (pkexec) and "
         "run a desktop authentication agent, or launch SecureWave as root.";
}

static gchar* build_runtime_path(const gchar* file_name) {
  if (!file_name || *file_name == '\0') {
    return nullptr;
  }
  g_autofree gchar* config_dir = g_build_filename(g_get_user_config_dir(), "securewave", nullptr);
  if (g_mkdir_with_parents(config_dir, 0700) != 0) {
    return nullptr;
  }
  return g_build_filename(config_dir, file_name, nullptr);
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

static gchar* read_all_from_fd(gint fd) {
  if (fd < 0) {
    return nullptr;
  }
  GString* out = g_string_new(nullptr);
  char buffer[4096];
  ssize_t n = 0;
  while ((n = read(fd, buffer, sizeof(buffer))) > 0) {
    g_string_append_len(out, buffer, static_cast<gssize>(n));
  }
  return g_string_free(out, FALSE);
}

static gchar* last_non_empty_line(const gchar* text) {
  if (!text) {
    return nullptr;
  }
  g_auto(GStrv) lines = g_strsplit(text, "\n", -1);
  if (!lines) {
    return nullptr;
  }
  const gint len = static_cast<gint>(g_strv_length(lines));
  for (gint idx = len - 1; idx >= 0; idx--) {
    if (!lines[idx]) {
      continue;
    }
    g_autofree gchar* candidate = g_strdup(lines[idx]);
    g_strstrip(candidate);
    if (candidate && *candidate != '\0') {
      return g_strdup(candidate);
    }
  }
  return nullptr;
}

static gboolean looks_like_permission_error(const gchar* stderr_text) {
  if (!stderr_text || *stderr_text == '\0') {
    return FALSE;
  }
  g_autofree gchar* lower = g_ascii_strdown(stderr_text, -1);
  return g_strrstr(lower, "permission denied") != nullptr ||
         g_strrstr(lower, "not authorized") != nullptr ||
         g_strrstr(lower, "authentication failed") != nullptr ||
         g_strrstr(lower, "no authentication agent") != nullptr;
}

static void set_active_protocol(VpnChannelState* state, const gchar* protocol) {
  if (!state) {
    return;
  }
  g_free(state->active_protocol);
  state->active_protocol = protocol ? g_strdup(protocol) : nullptr;
}

static gboolean run_command_step(
    gchar** argv,
    const gchar* error_code,
    const gchar* fallback_message,
    gchar** out_code,
    gchar** out_message) {
  g_autoptr(GError) spawn_error = nullptr;
  g_autofree gchar* stdout_text = nullptr;
  g_autofree gchar* stderr_text = nullptr;
  gint wait_status = 0;

  if (!g_spawn_sync(
          nullptr,
          argv,
          nullptr,
          static_cast<GSpawnFlags>(G_SPAWN_SEARCH_PATH),
          nullptr,
          nullptr,
          &stdout_text,
          &stderr_text,
          &wait_status,
          &spawn_error)) {
    const gchar* message =
        (spawn_error && spawn_error->message && *spawn_error->message != '\0')
            ? spawn_error->message
            : fallback_message;
    *out_code = g_strdup(
        looks_like_permission_error(message)
            ? "vpn_permission_required"
            : error_code);
    *out_message = g_strdup(message);
    return FALSE;
  }

  g_autoptr(GError) wait_error = nullptr;
  if (!g_spawn_check_wait_status(wait_status, &wait_error)) {
    const gchar* code = error_code;
    const gchar* base =
        (wait_error && wait_error->message && *wait_error->message != '\0')
            ? wait_error->message
            : fallback_message;
    g_autofree gchar* stderr_line = last_non_empty_line(stderr_text);
    if (looks_like_permission_error(stderr_text) || looks_like_permission_error(base)) {
      code = "vpn_permission_required";
    }
    *out_code = g_strdup(code);
    *out_message =
        stderr_line ? g_strdup_printf("%s: %s", base, stderr_line) : g_strdup(base);
    return FALSE;
  }

  return TRUE;
}

typedef struct {
  gint ref_count;
  FlMethodCall* method_call;
  VpnChannelState* state;
  gchar* error_code;
  gchar* success_protocol;
  GPid pid;
  gint stdout_fd;
  gint stderr_fd;
  guint timeout_id;
  gboolean responded;
  gboolean update_connected;
  gboolean connected_value;
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
  g_clear_pointer(&ctx->success_protocol, g_free);
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
  if (ctx->update_connected && ctx->state) {
    ctx->state->last_connected = ctx->connected_value;
    if (ctx->connected_value) {
      set_active_protocol(ctx->state, ctx->success_protocol);
    } else {
      set_active_protocol(ctx->state, nullptr);
    }
  }
  ctx->responded = TRUE;
  g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
      fl_method_success_response_new(nullptr));
  fl_method_call_respond(ctx->method_call, response, nullptr);
}

static void wg_quick_respond_error_once(
    WgQuickSpawnContext* ctx,
    const gchar* code,
    const gchar* message) {
  if (ctx->responded) {
    return;
  }
  if (ctx->update_connected && ctx->state && ctx->connected_value) {
    ctx->state->last_connected = FALSE;
    set_active_protocol(ctx->state, nullptr);
  }
  ctx->responded = TRUE;
  respond_error(ctx->method_call, code ? code : ctx->error_code, message, nullptr);
}

static void wg_quick_child_watch_cb(GPid pid, gint wait_status, gpointer user_data) {
  WgQuickSpawnContext* ctx = static_cast<WgQuickSpawnContext*>(user_data);
  if (ctx->timeout_id != 0) {
    g_source_remove(ctx->timeout_id);
    ctx->timeout_id = 0;
  }
  g_autofree gchar* stdout_text = read_all_from_fd(ctx->stdout_fd);
  (void)stdout_text;  // Reserved for future troubleshooting; stderr is more actionable.
  g_autofree gchar* stderr_text = read_all_from_fd(ctx->stderr_fd);
  g_autofree gchar* stderr_line = last_non_empty_line(stderr_text);

  if (ctx->stdout_fd >= 0) {
    close(ctx->stdout_fd);
    ctx->stdout_fd = -1;
  }
  if (ctx->stderr_fd >= 0) {
    close(ctx->stderr_fd);
    ctx->stderr_fd = -1;
  }
  g_autoptr(GError) error = nullptr;
  if (!g_spawn_check_wait_status(wait_status, &error)) {
    const gchar* base = error ? error->message : "wg-quick failed.";
    g_autofree gchar* message =
        stderr_line ? g_strdup_printf("%s: %s", base, stderr_line) : g_strdup(base);
    const gchar* code = ctx->error_code;
    if (looks_like_permission_error(stderr_text)) {
      code = "vpn_permission_required";
    }
    wg_quick_respond_error_once(ctx, code, message);
  } else {
    wg_quick_respond_ok_once(ctx);
  }
  g_spawn_close_pid(pid);
}

static gboolean wg_quick_timeout_cb(gpointer user_data) {
  WgQuickSpawnContext* ctx = static_cast<WgQuickSpawnContext*>(user_data);
  ctx->timeout_id = 0;
  wg_quick_respond_error_once(
      ctx,
      ctx->error_code,
      "WireGuard operation timed out. Ensure you have the required permissions and retry.");
  if (ctx->pid != 0) {
    kill(ctx->pid, SIGKILL);
  }
  return G_SOURCE_REMOVE;
}

static void spawn_wg_quick_async(
    FlMethodCall* method_call,
    VpnChannelState* state,
    const gchar* error_code,
    const gchar* success_protocol,
    const gchar* action,
    const gchar* config_path,
    gboolean update_connected,
    gboolean connected_value) {
  g_autoptr(GError) error = nullptr;

  g_autofree gchar* wg_quick_path = g_find_program_in_path("wg-quick");
  if (!wg_quick_path) {
    respond_error(
        method_call,
        "vpn_unavailable",
        wireguard_install_hint_message(),
        nullptr);
    return;
  }

  const bool needs_elevation = geteuid() != 0;
  if (needs_elevation && !has_desktop_auth_session()) {
    respond_error(
        method_call,
        "vpn_permission_required",
        "No desktop authentication session detected for privilege escalation. "
        "Start a polkit agent or run SecureWave as root.",
        nullptr);
    return;
  }
  g_autofree gchar* pkexec_path = nullptr;
  if (needs_elevation) {
    pkexec_path = g_find_program_in_path("pkexec");
    if (!pkexec_path) {
      respond_error(
          method_call,
          "vpn_permission_required",
          elevation_hint_message(),
          nullptr);
      return;
    }
  }

  gchar* argv[8] = {nullptr};
  int idx = 0;
  if (needs_elevation) {
    argv[idx++] = pkexec_path;
  }
  argv[idx++] = wg_quick_path;
  argv[idx++] = const_cast<gchar*>(action);
  argv[idx++] = const_cast<gchar*>(config_path);
  argv[idx] = nullptr;

  GPid pid = 0;
  gint stdout_fd = -1;
  gint stderr_fd = -1;
  if (!g_spawn_async_with_pipes(
          nullptr,
          argv,
          nullptr,
          static_cast<GSpawnFlags>(G_SPAWN_DO_NOT_REAP_CHILD),
          nullptr,
          nullptr,
          &pid,
          nullptr,
          &stdout_fd,
          &stderr_fd,
          &error)) {
    respond_error(
        method_call,
        error_code,
        error ? error->message : "Failed to spawn wg-quick.",
        nullptr);
    return;
  }

  WgQuickSpawnContext* ctx = g_new0(WgQuickSpawnContext, 1);
  ctx->ref_count = 1;
  ctx->method_call = FL_METHOD_CALL(g_object_ref(method_call));
  ctx->state = state;
  ctx->error_code = g_strdup(error_code);
  ctx->success_protocol = g_strdup(success_protocol);
  ctx->pid = pid;
  ctx->stdout_fd = stdout_fd;
  ctx->stderr_fd = stderr_fd;
  ctx->responded = FALSE;
  ctx->update_connected = update_connected;
  ctx->connected_value = connected_value;
  g_child_watch_add_full(
      G_PRIORITY_DEFAULT,
      pid,
      wg_quick_child_watch_cb,
      wg_quick_spawn_context_ref(ctx),
      reinterpret_cast<GDestroyNotify>(wg_quick_spawn_context_unref));
  ctx->timeout_id = g_timeout_add_full(
      G_PRIORITY_DEFAULT,
      kWgQuickTimeoutMs,
      wg_quick_timeout_cb,
      wg_quick_spawn_context_ref(ctx),
      reinterpret_cast<GDestroyNotify>(wg_quick_spawn_context_unref));
  wg_quick_spawn_context_unref(ctx);
}

static gboolean read_pid_file(const gchar* path, gint* out_pid) {
  if (!path || !out_pid || !g_file_test(path, G_FILE_TEST_EXISTS)) {
    return FALSE;
  }
  g_autofree gchar* contents = nullptr;
  gsize length = 0;
  g_autoptr(GError) error = nullptr;
  if (!g_file_get_contents(path, &contents, &length, &error)) {
    return FALSE;
  }
  if (!contents || length == 0) {
    return FALSE;
  }
  g_strstrip(contents);
  if (*contents == '\0') {
    return FALSE;
  }
  gchar* end = nullptr;
  const glong value = g_ascii_strtoll(contents, &end, 10);
  if (end == contents || value <= 1 || value > G_MAXINT) {
    return FALSE;
  }
  *out_pid = static_cast<gint>(value);
  return TRUE;
}

static gboolean run_command_or_error(
    FlMethodCall* method_call,
    gchar** argv,
    const gchar* error_code,
    const gchar* fallback_message,
    const gchar* success_protocol,
    VpnChannelState* state) {
  g_autofree gchar* code = nullptr;
  g_autofree gchar* message = nullptr;
  if (!run_command_step(argv, error_code, fallback_message, &code, &message)) {
    respond_error(method_call, code, message, nullptr);
    return FALSE;
  }
  if (state) {
    state->last_connected = success_protocol != nullptr;
    set_active_protocol(state, success_protocol);
  }
  g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
      fl_method_success_response_new(nullptr));
  fl_method_call_respond(method_call, response, nullptr);
  return TRUE;
}

static void handle_vpn_call(FlMethodChannel* channel,
                            FlMethodCall* method_call,
                            gpointer user_data) {
  (void)channel;  // Unused; the channel is already held in VpnChannelState.
  VpnChannelState* state = static_cast<VpnChannelState*>(user_data);
  const gchar* method = fl_method_call_get_name(method_call);
  if (g_strcmp0(method, "isAvailable") == 0) {
    g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
        fl_method_success_response_new(fl_value_new_bool(native_vpn_available())));
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }
  if (g_strcmp0(method, "getStatus") == 0) {
    g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
        fl_method_success_response_new(fl_value_new_string(
            state->last_connected ? "connected" : "disconnected")));
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }
  if (g_strcmp0(method, "getCapabilities") == 0) {
    const gboolean wg_installed = wg_quick_available();
    const gboolean ovpn_installed = openvpn_available();
    const gboolean nmcli_installed = nmcli_available();
    const gboolean ipsec_installed = ipsec_available();
    const gboolean can_elevate = elevation_available();
    const gboolean has_auth_session = has_desktop_auth_session();
    g_autoptr(FlValue) map = fl_value_new_map();
    fl_value_set_string_take(map, "wireguard", fl_value_new_bool(wg_installed && can_elevate));
    fl_value_set_string_take(map, "openvpn", fl_value_new_bool(ovpn_installed && can_elevate));
    fl_value_set_string_take(
        map,
        "ikev2",
        fl_value_new_bool(nmcli_installed && ipsec_installed && can_elevate));
    fl_value_set_string_take(map, "windows_thread_safe", fl_value_new_bool(FALSE));
    fl_value_set_string_take(map, "android_vpnservice_based", fl_value_new_bool(FALSE));
    fl_value_set_string_take(map, "macos_entitlements_ready", fl_value_new_bool(TRUE));
    fl_value_set_string_take(map, "linux_wg_installed", fl_value_new_bool(wg_installed));
    fl_value_set_string_take(map, "linux_elevation_available", fl_value_new_bool(can_elevate));
    if (!wg_installed || !can_elevate) {
      const gchar* hint = !wg_installed
                              ? wireguard_install_hint_message()
                              : elevation_hint_message();
      fl_value_set_string_take(
          map,
          "wireguard_install_hint",
          fl_value_new_string(hint));
    }
    if (!ovpn_installed || !can_elevate) {
      const gchar* hint = !ovpn_installed
                              ? openvpn_install_hint_message()
                              : elevation_hint_message();
      fl_value_set_string_take(
          map,
          "openvpn_install_hint",
          fl_value_new_string(hint));
    }
    if (!nmcli_installed || !ipsec_installed || !can_elevate) {
      const gchar* hint = nullptr;
      if (!can_elevate) {
        hint = elevation_hint_message();
      } else if (!nmcli_installed || !ipsec_installed) {
        hint = ikev2_install_hint_message();
      }
      if (hint) {
        fl_value_set_string_take(
            map,
            "ikev2_install_hint",
            fl_value_new_string(hint));
      }
    }
    if (!can_elevate || !has_auth_session) {
      fl_value_set_string_take(
          map,
          "linux_elevation_hint",
          fl_value_new_string(elevation_hint_message()));
    }
    g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
        fl_method_success_response_new(map));
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }
  if (g_strcmp0(method, "connect") == 0) {
    FlValue* args = fl_method_call_get_args(method_call);
    const gchar* protocol = get_string_arg(args, "protocol");
    const gchar* normalized = protocol ? protocol : "wireguard";
    if (g_strcmp0(normalized, "auto") == 0) {
      normalized = "wireguard";
    }

    if (g_strcmp0(normalized, "wireguard") == 0 || g_strcmp0(normalized, "wg") == 0) {
      if (!wg_quick_available()) {
        respond_error(
            method_call,
            "vpn_unavailable",
            wireguard_install_hint_message(),
            fl_value_new_map());
        return;
      }
      if (!elevation_available()) {
        respond_error(
            method_call,
            "vpn_permission_required",
            elevation_hint_message(),
            fl_value_new_map());
        return;
      }
      const gchar* config = get_string_arg(args, "config");
      if (!config || *config == '\0') {
        FlValue* profile = get_map_arg(args, "profile");
        config = get_string_from_map(profile, "wireguard_config");
      }
      if (!config || *config == '\0') {
        respond_error(method_call, "invalid_config", "Missing WireGuard configuration.", nullptr);
        return;
      }
      if (state->wg_config_path == nullptr) {
        state->wg_config_path = build_runtime_path(kWireGuardConfigFileName);
      }
      if (state->wg_config_path == nullptr) {
        respond_error(method_call, "vpn_config_write_failed", "Unable to write config file.", nullptr);
        return;
      }
      g_autoptr(GError) error = nullptr;
      if (!g_file_set_contents(state->wg_config_path, config, -1, &error)) {
        respond_error(method_call, "vpn_config_write_failed", error->message, nullptr);
        return;
      }
      spawn_wg_quick_async(
          method_call,
          state,
          "vpn_connect_failed",
          "wireguard",
          "up",
          state->wg_config_path,
          TRUE,
          TRUE);
      return;
    }

    if (g_strcmp0(normalized, "openvpn") == 0) {
      if (!openvpn_available()) {
        respond_error(
            method_call,
            "vpn_unavailable",
            openvpn_install_hint_message(),
            nullptr);
        return;
      }
      if (!elevation_available()) {
        respond_error(
            method_call,
            "vpn_permission_required",
            elevation_hint_message(),
            nullptr);
        return;
      }
      FlValue* profile = get_map_arg(args, "profile");
      const gchar* ovpn_config = get_string_from_map(profile, "ovpn_config");
      const gchar* username = get_string_from_map(profile, "username");
      const gchar* password = get_string_from_map(profile, "password");
      if (!ovpn_config || *ovpn_config == '\0') {
        respond_error(
            method_call,
            "invalid_profile",
            "OpenVPN profile is missing ovpn_config.",
            nullptr);
        return;
      }
      if ((username && *username != '\0') != (password && *password != '\0')) {
        respond_error(
            method_call,
            "invalid_profile",
            "OpenVPN profile must include both username and password, or neither.",
            nullptr);
        return;
      }
      if (state->openvpn_config_path == nullptr) {
        state->openvpn_config_path = build_runtime_path(kOpenVpnConfigFileName);
      }
      if (state->openvpn_auth_path == nullptr) {
        state->openvpn_auth_path = build_runtime_path(kOpenVpnAuthFileName);
      }
      if (state->openvpn_pid_path == nullptr) {
        state->openvpn_pid_path = build_runtime_path(kOpenVpnPidFileName);
      }
      if (!state->openvpn_config_path || !state->openvpn_auth_path ||
          !state->openvpn_pid_path) {
        respond_error(
            method_call,
            "vpn_config_write_failed",
            "Unable to prepare OpenVPN runtime files.",
            nullptr);
        return;
      }
      g_autoptr(GError) error = nullptr;
      if (!g_file_set_contents(state->openvpn_config_path, ovpn_config, -1, &error)) {
        respond_error(method_call, "vpn_config_write_failed", error->message, nullptr);
        return;
      }
      if (username && *username != '\0' && password && *password != '\0') {
        g_autofree gchar* auth_contents = g_strdup_printf("%s\n%s\n", username, password);
        if (!g_file_set_contents(state->openvpn_auth_path, auth_contents, -1, &error)) {
          respond_error(method_call, "vpn_config_write_failed", error->message, nullptr);
          return;
        }
      }

      const gboolean needs_elevation = geteuid() != 0;
      g_autofree gchar* openvpn_path = g_find_program_in_path("openvpn");
      g_autofree gchar* pkexec_path = nullptr;
      if (needs_elevation) {
        pkexec_path = g_find_program_in_path("pkexec");
        if (!pkexec_path) {
          respond_error(
              method_call,
              "vpn_permission_required",
              elevation_hint_message(),
              nullptr);
          return;
        }
      }

      gchar* argv[16] = {nullptr};
      int idx = 0;
      if (needs_elevation) {
        argv[idx++] = pkexec_path;
      }
      argv[idx++] = openvpn_path;
      argv[idx++] = const_cast<gchar*>("--config");
      argv[idx++] = state->openvpn_config_path;
      argv[idx++] = const_cast<gchar*>("--writepid");
      argv[idx++] = state->openvpn_pid_path;
      if (username && *username != '\0') {
        argv[idx++] = const_cast<gchar*>("--auth-user-pass");
        argv[idx++] = state->openvpn_auth_path;
      }
      argv[idx++] = const_cast<gchar*>("--daemon");
      argv[idx] = nullptr;

      run_command_or_error(
          method_call,
          argv,
          "vpn_connect_failed",
          "Failed to start OpenVPN.",
          "openvpn",
          state);
      return;
    }

    if (g_strcmp0(normalized, "ikev2") == 0 || g_strcmp0(normalized, "ipsec") == 0) {
      if (!nmcli_available() || !ipsec_available()) {
        respond_error(
            method_call,
            "protocol_unavailable",
            ikev2_install_hint_message(),
            nullptr);
        return;
      }
      if (!elevation_available()) {
        respond_error(
            method_call,
            "vpn_permission_required",
            elevation_hint_message(),
            nullptr);
        return;
      }

      FlValue* profile = get_map_arg(args, "profile");
      const gchar* auth_method = get_string_from_map(profile, "auth_method");
      if (!auth_method || *auth_method == '\0') {
        auth_method = "eap-mschapv2";
      }
      if (g_strcmp0(auth_method, "eap-mschapv2") != 0) {
        respond_error(
            method_call,
            "protocol_unavailable",
            "Linux IKEv2 automation currently supports EAP-MSCHAPv2. "
            "Use Setup help for EAP-TLS manual import requirements.",
            nullptr);
        return;
      }

      const gchar* server = get_string_from_map(profile, "server");
      const gchar* username = get_string_from_map(profile, "username");
      const gchar* password = get_string_from_map(profile, "password");
      const gchar* remote_id = get_string_from_map(profile, "remote_id");

      if (!server || *server == '\0' || !username || *username == '\0' ||
          !password || *password == '\0') {
        respond_error(
            method_call,
            "invalid_profile",
            "IKEv2 profile requires server, username, and password.",
            nullptr);
        return;
      }

      g_autofree gchar* vpn_data = nullptr;
      if (remote_id && *remote_id != '\0') {
        vpn_data = g_strdup_printf(
            "address=%s,user=%s,method=eap,virtual=yes,encap=no,ipcomp=no,remote-identity=%s",
            server,
            username,
            remote_id);
      } else {
        vpn_data = g_strdup_printf(
            "address=%s,user=%s,method=eap,virtual=yes,encap=no,ipcomp=no",
            server,
            username);
      }
      g_autofree gchar* vpn_secrets = g_strdup_printf("password=%s", password);

      const gboolean needs_elevation = geteuid() != 0;
      g_autofree gchar* pkexec_path = nullptr;
      if (needs_elevation) {
        pkexec_path = g_find_program_in_path("pkexec");
        if (!pkexec_path) {
          respond_error(
              method_call,
              "vpn_permission_required",
              elevation_hint_message(),
              nullptr);
          return;
        }
      }

      gchar* delete_argv[8] = {nullptr};
      int didx = 0;
      if (needs_elevation) {
        delete_argv[didx++] = pkexec_path;
      }
      delete_argv[didx++] = const_cast<gchar*>("nmcli");
      delete_argv[didx++] = const_cast<gchar*>("connection");
      delete_argv[didx++] = const_cast<gchar*>("delete");
      delete_argv[didx++] = const_cast<gchar*>("id");
      delete_argv[didx++] = const_cast<gchar*>(kIkev2ConnectionName);
      delete_argv[didx] = nullptr;
      g_autofree gchar* ignored_code = nullptr;
      g_autofree gchar* ignored_message = nullptr;
      run_command_step(
          delete_argv,
          "vpn_setup_failed",
          "Unable to clean up existing IKEv2 profile.",
          &ignored_code,
          &ignored_message);

      gchar* add_argv[20] = {nullptr};
      int aidx = 0;
      if (needs_elevation) {
        add_argv[aidx++] = pkexec_path;
      }
      add_argv[aidx++] = const_cast<gchar*>("nmcli");
      add_argv[aidx++] = const_cast<gchar*>("connection");
      add_argv[aidx++] = const_cast<gchar*>("add");
      add_argv[aidx++] = const_cast<gchar*>("type");
      add_argv[aidx++] = const_cast<gchar*>("vpn");
      add_argv[aidx++] = const_cast<gchar*>("ifname");
      add_argv[aidx++] = const_cast<gchar*>("*");
      add_argv[aidx++] = const_cast<gchar*>("con-name");
      add_argv[aidx++] = const_cast<gchar*>(kIkev2ConnectionName);
      add_argv[aidx++] = const_cast<gchar*>("vpn-type");
      add_argv[aidx++] = const_cast<gchar*>("strongswan");
      add_argv[aidx++] = const_cast<gchar*>("vpn.data");
      add_argv[aidx++] = vpn_data;
      add_argv[aidx++] = const_cast<gchar*>("vpn.secrets");
      add_argv[aidx++] = vpn_secrets;
      add_argv[aidx] = nullptr;

      g_autofree gchar* add_code = nullptr;
      g_autofree gchar* add_message = nullptr;
      if (!run_command_step(
              add_argv,
              "vpn_setup_failed",
              "Failed to configure IKEv2 connection profile.",
              &add_code,
              &add_message)) {
        respond_error(method_call, add_code, add_message, nullptr);
        return;
      }

      gchar* up_argv[10] = {nullptr};
      int uidx = 0;
      if (needs_elevation) {
        up_argv[uidx++] = pkexec_path;
      }
      up_argv[uidx++] = const_cast<gchar*>("nmcli");
      up_argv[uidx++] = const_cast<gchar*>("connection");
      up_argv[uidx++] = const_cast<gchar*>("up");
      up_argv[uidx++] = const_cast<gchar*>("id");
      up_argv[uidx++] = const_cast<gchar*>(kIkev2ConnectionName);
      up_argv[uidx] = nullptr;

      run_command_or_error(
          method_call,
          up_argv,
          "vpn_connect_failed",
          "Failed to establish IKEv2 connection.",
          "ikev2",
          state);
      return;
    }

    respond_error(
        method_call,
        "protocol_unavailable",
        "Requested VPN protocol is unavailable on this Linux build.",
        nullptr);
    return;
  }
  if (g_strcmp0(method, "disconnect") == 0) {
    const gchar* active = state->active_protocol;
    if (active && g_strcmp0(active, "openvpn") == 0) {
      if (!elevation_available()) {
        respond_error(
            method_call,
            "vpn_permission_required",
            elevation_hint_message(),
            nullptr);
        return;
      }
      gint openvpn_pid = 0;
      if (!read_pid_file(state->openvpn_pid_path, &openvpn_pid)) {
        state->last_connected = FALSE;
        set_active_protocol(state, nullptr);
        g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
            fl_method_success_response_new(nullptr));
        fl_method_call_respond(method_call, response, nullptr);
        return;
      }
      const gboolean needs_elevation = geteuid() != 0;
      g_autofree gchar* pkexec_path = nullptr;
      if (needs_elevation) {
        pkexec_path = g_find_program_in_path("pkexec");
        if (!pkexec_path) {
          respond_error(
              method_call,
              "vpn_permission_required",
              elevation_hint_message(),
              nullptr);
          return;
        }
      }
      gchar pid_arg[32];
      g_snprintf(pid_arg, sizeof(pid_arg), "%d", openvpn_pid);
      gchar* argv[8] = {nullptr};
      int idx = 0;
      if (needs_elevation) {
        argv[idx++] = pkexec_path;
      }
      argv[idx++] = const_cast<gchar*>("kill");
      argv[idx++] = const_cast<gchar*>("-TERM");
      argv[idx++] = pid_arg;
      argv[idx] = nullptr;
      run_command_or_error(
          method_call,
          argv,
          "vpn_disconnect_failed",
          "Failed to stop OpenVPN tunnel.",
          nullptr,
          state);
      return;
    }

    if (active && g_strcmp0(active, "ikev2") == 0) {
      if (!nmcli_available()) {
        respond_error(
            method_call,
            "vpn_unavailable",
            ikev2_install_hint_message(),
            nullptr);
        return;
      }
      if (!elevation_available()) {
        respond_error(
            method_call,
            "vpn_permission_required",
            elevation_hint_message(),
            nullptr);
        return;
      }
      const gboolean needs_elevation = geteuid() != 0;
      g_autofree gchar* pkexec_path = nullptr;
      if (needs_elevation) {
        pkexec_path = g_find_program_in_path("pkexec");
        if (!pkexec_path) {
          respond_error(
              method_call,
              "vpn_permission_required",
              elevation_hint_message(),
              nullptr);
          return;
        }
      }
      gchar* argv[10] = {nullptr};
      int idx = 0;
      if (needs_elevation) {
        argv[idx++] = pkexec_path;
      }
      argv[idx++] = const_cast<gchar*>("nmcli");
      argv[idx++] = const_cast<gchar*>("connection");
      argv[idx++] = const_cast<gchar*>("down");
      argv[idx++] = const_cast<gchar*>("id");
      argv[idx++] = const_cast<gchar*>(kIkev2ConnectionName);
      argv[idx] = nullptr;

      g_autofree gchar* code = nullptr;
      g_autofree gchar* message = nullptr;
      if (!run_command_step(
              argv,
              "vpn_disconnect_failed",
              "Failed to disconnect IKEv2 tunnel.",
              &code,
              &message)) {
        g_autofree gchar* lower = g_ascii_strdown(message, -1);
        if (!lower || (g_strrstr(lower, "not active") == nullptr &&
                       g_strrstr(lower, "unknown connection") == nullptr)) {
          respond_error(method_call, code, message, nullptr);
          return;
        }
      }
      state->last_connected = FALSE;
      set_active_protocol(state, nullptr);
      g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
          fl_method_success_response_new(nullptr));
      fl_method_call_respond(method_call, response, nullptr);
      return;
    }

    if (!wg_quick_available()) {
      state->last_connected = FALSE;
      set_active_protocol(state, nullptr);
      g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
          fl_method_success_response_new(nullptr));
      fl_method_call_respond(method_call, response, nullptr);
      return;
    }
    if (!elevation_available()) {
      respond_error(
          method_call,
          "vpn_permission_required",
          elevation_hint_message(),
          fl_value_new_map());
      return;
    }
    if (!state->wg_config_path || !g_file_test(state->wg_config_path, G_FILE_TEST_EXISTS)) {
      state->last_connected = FALSE;
      set_active_protocol(state, nullptr);
      g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
          fl_method_success_response_new(nullptr));
      fl_method_call_respond(method_call, response, nullptr);
      return;
    }
    spawn_wg_quick_async(
        method_call,
        state,
        "vpn_disconnect_failed",
        nullptr,
        "down",
        state->wg_config_path,
        TRUE,
        FALSE);
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
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

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
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

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
  vpn_state->last_connected = FALSE;
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

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
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
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
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
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
