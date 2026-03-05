#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif
#include <gio/gio.h>
#include <glib/gstdio.h>
#include <errno.h>
#include <cstdio>
#include <signal.h>
#include <sys/wait.h>
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
// Keep basename short enough for wg-quick interface derivation (IFNAMSIZ<=15).
const char* kWireGuardConfigFileName = "sw-wg.conf";
const char* kOpenVpnConfigFileName = "securewave-openvpn.ovpn";
const char* kOpenVpnAuthFileName = "securewave-openvpn.auth";
const char* kOpenVpnPidFileName = "securewave-openvpn.pid";
const char* kIkev2ConnectionName = "SecureWave-IKEv2";
const guint kWgQuickTimeoutMs = 30000;
const guint kRuntimeSanityTimeoutMs = 7000;
const guint kRuntimeSanityPollIntervalMs = 200;
const char* kSecureWaveWgHelperPath = "/usr/local/libexec/securewave-wg-quick";

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

static gboolean securewave_wg_helper_available() {
  return g_file_test(kSecureWaveWgHelperPath, G_FILE_TEST_IS_EXECUTABLE);
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
  // Preferred path: scoped helper + polkit rule allows tunnel resets without
  // repetitive password prompts while preserving OS authorization controls.
  if (pkexec_available() && securewave_wg_helper_available()) {
    return TRUE;
  }
  // Fallback path: pkexec with a desktop auth agent.
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
  return "Administrator privileges are required. Install the SecureWave "
         "helper/polkit setup (preferred) or PolicyKit (pkexec) with a desktop "
         "authentication agent.";
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

static gboolean run_quiet_command(gchar** argv) {
  gint wait_status = 0;
  if (!g_spawn_sync(
          nullptr,
          argv,
          nullptr,
          static_cast<GSpawnFlags>(G_SPAWN_SEARCH_PATH |
                                   G_SPAWN_STDOUT_TO_DEV_NULL |
                                   G_SPAWN_STDERR_TO_DEV_NULL),
          nullptr,
          nullptr,
          nullptr,
          nullptr,
          &wait_status,
          nullptr)) {
    return FALSE;
  }
  g_autoptr(GError) wait_error = nullptr;
  return g_spawn_check_wait_status(wait_status, &wait_error);
}

static gboolean run_command_capture_stdout(gchar** argv, gchar** out_stdout) {
  if (out_stdout) {
    *out_stdout = nullptr;
  }
  gint wait_status = 0;
  g_autoptr(GError) spawn_error = nullptr;
  g_autofree gchar* stdout_text = nullptr;
  g_autofree gchar* stderr_text = nullptr;
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
    return FALSE;
  }
  g_autoptr(GError) wait_error = nullptr;
  if (!g_spawn_check_wait_status(wait_status, &wait_error)) {
    return FALSE;
  }
  if (out_stdout) {
    *out_stdout = g_steal_pointer(&stdout_text);
  }
  return TRUE;
}

static gboolean command_output_has_non_empty_line(gchar** argv) {
  g_autofree gchar* stdout_text = nullptr;
  if (!run_command_capture_stdout(argv, &stdout_text)) {
    return FALSE;
  }
  g_autofree gchar* line = last_non_empty_line(stdout_text);
  return line != nullptr;
}

static gboolean command_output_contains(gchar** argv, const gchar* needle) {
  if (!needle || *needle == '\0') {
    return FALSE;
  }
  g_autofree gchar* stdout_text = nullptr;
  if (!run_command_capture_stdout(argv, &stdout_text) || !stdout_text) {
    return FALSE;
  }
  return g_strrstr(stdout_text, needle) != nullptr;
}

static gboolean process_is_running(gint pid) {
  if (pid <= 1) {
    return FALSE;
  }
  if (kill(pid, 0) == 0) {
    return TRUE;
  }
  return errno == EPERM;
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

static void wg_preflight_cleanup(const gchar* config_path);
static gboolean interface_exists(const gchar* iface);
static gboolean read_pid_file(const gchar* path, gint* out_pid);
static gboolean verify_wireguard_runtime(gchar** out_error);
static gboolean verify_openvpn_runtime(VpnChannelState* state, gchar** out_error);
static gboolean verify_ikev2_runtime(gchar** out_error);
static void refresh_runtime_connection_state(VpnChannelState* state);

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
    if (ctx->state && ctx->state->wg_config_path) {
      wg_preflight_cleanup(ctx->state->wg_config_path);
    }
    wg_quick_respond_error_once(ctx, code, message);
  } else {
    if (ctx->connected_value) {
      g_autofree gchar* sanity_error = nullptr;
      if (!verify_wireguard_runtime(&sanity_error)) {
        if (ctx->state && ctx->state->wg_config_path) {
          wg_preflight_cleanup(ctx->state->wg_config_path);
        }
        wg_quick_respond_error_once(
            ctx,
            "vpn_connect_failed",
            sanity_error
                ? sanity_error
                : "WireGuard connect sanity check failed.");
        g_spawn_close_pid(pid);
        return;
      }
      // Tell NetworkManager not to manage the WireGuard interface.
      // NM 1.36+ recognises WireGuard interfaces and, without a matching NM
      // connection profile, marks them "disconnected" and may bring them down
      // within ~5 seconds of creation.  Marking the device unmanaged prevents
      // this interference while still allowing ip rule / ip route to work.
      if (nmcli_available()) {
        gchar* nmcli_argv[] = {
            const_cast<gchar*>("nmcli"),
            const_cast<gchar*>("device"),
            const_cast<gchar*>("set"),
            const_cast<gchar*>("sw-wg"),
            const_cast<gchar*>("managed"),
            const_cast<gchar*>("no"),
            nullptr};
        run_quiet_command(nmcli_argv);
      }
    }
    wg_quick_respond_ok_once(ctx);
  }
  g_spawn_close_pid(pid);
}

static gboolean wg_quick_timeout_cb(gpointer user_data) {
  WgQuickSpawnContext* ctx = static_cast<WgQuickSpawnContext*>(user_data);
  ctx->timeout_id = 0;
  if (ctx->pid != 0) {
    kill(ctx->pid, SIGKILL);
  }
  if (ctx->state && ctx->state->wg_config_path) {
    wg_preflight_cleanup(ctx->state->wg_config_path);
  }
  wg_quick_respond_error_once(
      ctx,
      ctx->error_code,
      "WireGuard operation timed out. Ensure you have the required permissions and retry.");
  return G_SOURCE_REMOVE;
}

// Preflight: tear down any stale sw-wg interface before bringing it up.
// Ensure NetworkManager will never auto-manage the sw-wg interface.
// NM 1.36+ auto-detects WireGuard interfaces and attempts activation,
// which races with wg-quick and produces a spurious "Activation failed"
// desktop notification.  A persistent [keyfile] unmanaged-devices rule
// eliminates the race entirely.
static void ensure_nm_unmanaged_rule() {
  static gboolean done = FALSE;
  if (done) return;
  done = TRUE;

  const gchar* conf_path = "/etc/NetworkManager/conf.d/securewave-unmanaged.conf";
  const gchar* expected = "[keyfile]\nunmanaged-devices=interface-name:sw-wg\n";

  // Check if rule already exists.
  g_autofree gchar* contents = nullptr;
  if (g_file_get_contents(conf_path, &contents, nullptr, nullptr)) {
    if (contents && g_strstr_len(contents, -1, "sw-wg")) {
      return;  // Already installed.
    }
  }

  // Needs root to write to /etc — use pkexec + tee.
  if (!pkexec_available()) return;
  g_autofree gchar* pkexec = g_find_program_in_path("pkexec");
  if (!pkexec) return;
  g_autofree gchar* tee = g_find_program_in_path("tee");
  if (!tee) return;

  // pkexec tee /etc/NetworkManager/conf.d/securewave-unmanaged.conf
  gint stdin_fd = -1;
  GPid pid = 0;
  gchar* argv[] = {pkexec, tee, const_cast<gchar*>(conf_path), nullptr};
  g_autoptr(GError) error = nullptr;
  if (!g_spawn_async_with_pipes(
          nullptr, argv, nullptr,
          static_cast<GSpawnFlags>(G_SPAWN_DO_NOT_REAP_CHILD),
          nullptr, nullptr, &pid, &stdin_fd,
          nullptr, nullptr, &error)) {
    return;
  }
  if (stdin_fd >= 0) {
    // Write the rule content and close stdin so tee completes.
    (void)write(stdin_fd, expected, strlen(expected));
    close(stdin_fd);
  }
  gint wait_status = 0;
  (void)waitpid(pid, &wait_status, 0);
  g_spawn_close_pid(pid);

  // Reload NM so the new rule takes effect immediately.
  g_autofree gchar* nmcli = g_find_program_in_path("nmcli");
  if (nmcli) {
    gchar* reload_argv[] = {
        const_cast<gchar*>("nmcli"),
        const_cast<gchar*>("general"),
        const_cast<gchar*>("reload"),
        nullptr};
    run_quiet_command(reload_argv);
  }
}

// Only touches SecureWave-owned resources (interface sw-wg, table 51820).
// Failures are soft — the subsequent wg-quick up surfaces real errors.
static void wg_preflight_cleanup(const gchar* config_path) {
  if (!config_path || *config_path == '\0') {
    return;
  }
  // 1. Graceful down via wg-quick (handles routes + interface together).
  {
    gchar* argv[] = {const_cast<gchar*>("wg-quick"), const_cast<gchar*>("down"),
                     const_cast<gchar*>(config_path), nullptr};
    run_quiet_command(argv);
    // Ignore exit code — interface may not have existed.
  }
  // 2. Force-delete interface if it still lingers.
  {
    gchar* argv[] = {const_cast<gchar*>("ip"), const_cast<gchar*>("link"),
                     const_cast<gchar*>("delete"), const_cast<gchar*>("sw-wg"),
                     nullptr};
    run_quiet_command(argv);
  }
  // 3. Flush SecureWave-owned policy routing table entries.
  {
    gchar* argv[] = {const_cast<gchar*>("ip"), const_cast<gchar*>("-4"),
                     const_cast<gchar*>("route"), const_cast<gchar*>("flush"),
                     const_cast<gchar*>("table"), const_cast<gchar*>("51820"),
                     nullptr};
    run_quiet_command(argv);
  }
  {
    gchar* argv[] = {const_cast<gchar*>("ip"), const_cast<gchar*>("-6"),
                     const_cast<gchar*>("route"), const_cast<gchar*>("flush"),
                     const_cast<gchar*>("table"), const_cast<gchar*>("51820"),
                     nullptr};
    run_quiet_command(argv);
  }
  // 4. Remove stale policy rules for table 51820 (SecureWave-owned only).
  {
    gchar* argv[] = {const_cast<gchar*>("ip"), const_cast<gchar*>("rule"),
                     const_cast<gchar*>("del"), const_cast<gchar*>("table"),
                     const_cast<gchar*>("51820"), nullptr};
    for (int i = 0; i < 8; i++) {
      if (!run_quiet_command(argv)) break;
    }
  }
  // 5. Best-effort DNS reset for SecureWave interface only.
  if (g_find_program_in_path("resolvectl")) {
    gchar* revert_argv[] = {const_cast<gchar*>("resolvectl"),
                            const_cast<gchar*>("revert"),
                            const_cast<gchar*>("sw-wg"), nullptr};
    run_quiet_command(revert_argv);
    gchar* flush_argv[] = {const_cast<gchar*>("resolvectl"),
                           const_cast<gchar*>("flush-caches"), nullptr};
    run_quiet_command(flush_argv);
  }
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
  const bool helper_ready = securewave_wg_helper_available();
  if (needs_elevation && !helper_ready && !has_desktop_auth_session()) {
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
  g_autofree gchar* helper_path = nullptr;
  int idx = 0;
  if (needs_elevation) {
    argv[idx++] = pkexec_path;
  }
  if (needs_elevation && helper_ready) {
    helper_path = g_strdup(kSecureWaveWgHelperPath);
    argv[idx++] = helper_path;
  } else {
    argv[idx++] = wg_quick_path;
  }
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

static gboolean interface_exists(const gchar* iface) {
  if (!iface || *iface == '\0') {
    return FALSE;
  }
  g_autofree gchar* path = g_build_filename("/sys/class/net", iface, nullptr);
  return g_file_test(path, G_FILE_TEST_IS_DIR);
}

static gboolean read_u64_from_file(const gchar* path, guint64* out_value) {
  if (!path || !out_value) {
    return FALSE;
  }
  g_autofree gchar* contents = nullptr;
  gsize length = 0;
  g_autoptr(GError) error = nullptr;
  if (!g_file_get_contents(path, &contents, &length, &error) || !contents) {
    return FALSE;
  }
  g_strstrip(contents);
  if (*contents == '\0') {
    return FALSE;
  }
  gchar* end = nullptr;
  const guint64 value = g_ascii_strtoull(contents, &end, 10);
  if (end == contents) {
    return FALSE;
  }
  *out_value = value;
  return TRUE;
}

static gboolean read_interface_counter(
    const gchar* iface,
    const gchar* counter,
    guint64* out_value) {
  if (!iface || !counter || !out_value || !interface_exists(iface)) {
    return FALSE;
  }
  // Primary source for live traffic counters: /proc/net/dev.
  // This avoids occasional stale zeros observed with /sys/class/net on some
  // kernels when interfaces are rapidly recreated.
  g_autofree gchar* contents = nullptr;
  gsize length = 0;
  g_autoptr(GError) error = nullptr;
  if (g_file_get_contents("/proc/net/dev", &contents, &length, &error) &&
      contents && length > 0) {
    g_auto(GStrv) lines = g_strsplit(contents, "\n", -1);
    if (lines) {
      for (gint i = 0; lines[i] != nullptr; i++) {
        gchar* line = lines[i];
        if (!line) continue;
        gchar* colon = g_strstr_len(line, -1, ":");
        if (!colon) continue;
        *colon = '\0';
        g_strstrip(line);
        if (g_strcmp0(line, iface) != 0) continue;

        unsigned long long rx = 0;
        unsigned long long tx = 0;
        const gint scanned = std::sscanf(
            colon + 1,
            " %llu %*llu %*llu %*llu %*llu %*llu %*llu %*llu %llu",
            &rx,
            &tx);
        if (scanned == 2) {
          if (g_strcmp0(counter, "rx_bytes") == 0) {
            *out_value = static_cast<guint64>(rx);
            return TRUE;
          }
          if (g_strcmp0(counter, "tx_bytes") == 0) {
            *out_value = static_cast<guint64>(tx);
            return TRUE;
          }
        }
      }
    }
  }

  // Fallback for environments where /proc parsing fails.
  g_autofree gchar* path =
      g_build_filename("/sys/class/net", iface, "statistics", counter, nullptr);
  return read_u64_from_file(path, out_value);
}

static gchar* detect_route_interface() {
  gchar* argv[] = {const_cast<gchar*>("ip"), const_cast<gchar*>("-o"),
                   const_cast<gchar*>("route"), const_cast<gchar*>("get"),
                   const_cast<gchar*>("1.1.1.1"), nullptr};
  g_autoptr(GError) spawn_error = nullptr;
  g_autofree gchar* stdout_text = nullptr;
  g_autofree gchar* stderr_text = nullptr;
  gint wait_status = 0;
  if (!g_spawn_sync(
          nullptr, argv, nullptr, static_cast<GSpawnFlags>(G_SPAWN_SEARCH_PATH),
          nullptr, nullptr, &stdout_text, &stderr_text, &wait_status,
          &spawn_error)) {
    return nullptr;
  }
  g_autoptr(GError) wait_error = nullptr;
  if (!g_spawn_check_wait_status(wait_status, &wait_error) || !stdout_text) {
    return nullptr;
  }
  g_auto(GStrv) tokens = g_strsplit_set(stdout_text, " \n\t", -1);
  if (!tokens) {
    return nullptr;
  }
  for (gint i = 0; tokens[i] != nullptr; i++) {
    if (g_strcmp0(tokens[i], "dev") == 0 && tokens[i + 1] != nullptr &&
        *tokens[i + 1] != '\0') {
      return g_strdup(tokens[i + 1]);
    }
  }
  return nullptr;
}

static gchar* detect_active_interface(const gchar* active_protocol) {
  if (active_protocol &&
      (g_strcmp0(active_protocol, "wireguard") == 0 ||
       g_strcmp0(active_protocol, "wg") == 0)) {
    if (interface_exists("sw-wg")) {
      return g_strdup("sw-wg");
    }
    if (interface_exists("wg0")) {
      return g_strdup("wg0");
    }
  }
  if (active_protocol && g_strcmp0(active_protocol, "openvpn") == 0 &&
      interface_exists("tun0")) {
    return g_strdup("tun0");
  }
  if (active_protocol && g_strcmp0(active_protocol, "ikev2") == 0) {
    if (interface_exists("ipsec0")) {
      return g_strdup("ipsec0");
    }
    if (interface_exists("tun0")) {
      return g_strdup("tun0");
    }
  }

  g_autofree gchar* routed = detect_route_interface();
  if (routed && interface_exists(routed)) {
    return g_strdup(routed);
  }

  if (interface_exists("sw-wg")) {
    return g_strdup("sw-wg");
  }
  if (interface_exists("wg0")) {
    return g_strdup("wg0");
  }
  if (interface_exists("tun0")) {
    return g_strdup("tun0");
  }
  return nullptr;
}

static gboolean route_exists_for_interface(const gchar* iface) {
  if (!iface || *iface == '\0' || !interface_exists(iface)) {
    return FALSE;
  }
  gchar* ipv4_argv[] = {
      const_cast<gchar*>("ip"),
      const_cast<gchar*>("-4"),
      const_cast<gchar*>("-o"),
      const_cast<gchar*>("route"),
      const_cast<gchar*>("show"),
      const_cast<gchar*>("dev"),
      const_cast<gchar*>(iface),
      nullptr};
  if (command_output_has_non_empty_line(ipv4_argv)) {
    return TRUE;
  }
  gchar* ipv6_argv[] = {
      const_cast<gchar*>("ip"),
      const_cast<gchar*>("-6"),
      const_cast<gchar*>("-o"),
      const_cast<gchar*>("route"),
      const_cast<gchar*>("show"),
      const_cast<gchar*>("dev"),
      const_cast<gchar*>(iface),
      nullptr};
  return command_output_has_non_empty_line(ipv6_argv);
}


static gboolean nmcli_connection_active(const gchar* connection_name) {
  if (!connection_name || *connection_name == '\0' || !nmcli_available()) {
    return FALSE;
  }
  gchar* argv[] = {const_cast<gchar*>("nmcli"),
                   const_cast<gchar*>("-t"),
                   const_cast<gchar*>("-f"),
                   const_cast<gchar*>("NAME"),
                   const_cast<gchar*>("connection"),
                   const_cast<gchar*>("show"),
                   const_cast<gchar*>("--active"),
                   nullptr};
  g_autofree gchar* stdout_text = nullptr;
  if (!run_command_capture_stdout(argv, &stdout_text) || !stdout_text) {
    return FALSE;
  }
  g_auto(GStrv) lines = g_strsplit(stdout_text, "\n", -1);
  if (!lines) {
    return FALSE;
  }
  for (gint i = 0; lines[i] != nullptr; i++) {
    g_strstrip(lines[i]);
    if (*lines[i] == '\0') {
      continue;
    }
    if (g_strcmp0(lines[i], connection_name) == 0) {
      return TRUE;
    }
  }
  return FALSE;
}

static gboolean openvpn_process_alive(const gchar* pid_path) {
  gint pid = 0;
  if (!read_pid_file(pid_path, &pid)) {
    return FALSE;
  }
  return process_is_running(pid);
}

// Check that the SecureWave policy routing table (51820) has a default route
// via the active WireGuard interface.  This is the definitive proof that the
// PostUp hook ("ip route add default dev <iface> table 51820") ran
// successfully.  Checking only the ip rule is insufficient — the rule can be
// a stale leftover from a previous session's PostDown cleanup failure.
static gboolean wireguard_table_route_exists(const gchar* iface) {
  if (!iface || *iface == '\0') {
    return FALSE;
  }
  // "ip -4 route show table 51820" — look for a default route via our iface.
  gchar* argv[] = {const_cast<gchar*>("ip"),
                   const_cast<gchar*>("-4"),
                   const_cast<gchar*>("route"),
                   const_cast<gchar*>("show"),
                   const_cast<gchar*>("table"),
                   const_cast<gchar*>("51820"),
                   nullptr};
  // The output will contain "default dev <iface>" if the PostUp route is set.
  g_autofree gchar* needle = g_strdup_printf("dev %s", iface);
  return command_output_contains(argv, needle);
}

static gboolean verify_wireguard_runtime(gchar** out_error) {
  const guint attempts =
      (kRuntimeSanityTimeoutMs / kRuntimeSanityPollIntervalMs) + 1;
  for (guint i = 0; i < attempts; i++) {
    const gboolean has_sw_wg = interface_exists("sw-wg");
    const gboolean has_wg0 = interface_exists("wg0");
    const gchar* iface = has_sw_wg ? "sw-wg" : (has_wg0 ? "wg0" : nullptr);
    // Require both the interface AND the policy route in table 51820.
    // The ip rule alone is not sufficient proof — it may be a stale leftover
    // from a previous session.  The table route proves PostUp completed.
    const gboolean has_table_route =
        iface ? wireguard_table_route_exists(iface) : FALSE;
    if (iface && has_table_route) {
      return TRUE;
    }
    g_usleep(static_cast<gulong>(kRuntimeSanityPollIntervalMs) * 1000);
  }
  if (out_error) {
    *out_error = g_strdup(
        "WireGuard sanity check failed: sw-wg/wg0 interface exists but "
        "no default route in policy routing table 51820. "
        "Check that PostUp hooks ran as root (requires pkexec or securewave helper).");
  }
  return FALSE;
}

static gboolean verify_openvpn_runtime(VpnChannelState* state, gchar** out_error) {
  const guint attempts =
      (kRuntimeSanityTimeoutMs / kRuntimeSanityPollIntervalMs) + 1;
  for (guint i = 0; i < attempts; i++) {
    const gboolean pid_alive =
        state && state->openvpn_pid_path
            ? openvpn_process_alive(state->openvpn_pid_path)
            : FALSE;
    const gboolean has_tun = interface_exists("tun0");
    const gboolean has_route = route_exists_for_interface("tun0");
    if (pid_alive && has_tun && has_route) {
      return TRUE;
    }
    g_usleep(static_cast<gulong>(kRuntimeSanityPollIntervalMs) * 1000);
  }
  if (out_error) {
    *out_error = g_strdup(
        "OpenVPN sanity check failed: daemon started but tun0 interface/route was not established.");
  }
  return FALSE;
}

static gboolean verify_ikev2_runtime(gchar** out_error) {
  const guint attempts =
      (kRuntimeSanityTimeoutMs / kRuntimeSanityPollIntervalMs) + 1;
  for (guint i = 0; i < attempts; i++) {
    const gboolean nm_active = nmcli_connection_active(kIkev2ConnectionName);
    const gboolean has_ipsec0 = interface_exists("ipsec0");
    const gboolean has_tun0 = interface_exists("tun0");
    const gboolean has_interface = has_ipsec0 || has_tun0;
    const gboolean has_route =
        (has_ipsec0 && route_exists_for_interface("ipsec0")) ||
        (has_tun0 && route_exists_for_interface("tun0"));
    // IKEv2 on Linux may rely on XFRM policy paths rather than explicit routes.
    if (nm_active && has_interface && (has_route || has_ipsec0)) {
      return TRUE;
    }
    g_usleep(static_cast<gulong>(kRuntimeSanityPollIntervalMs) * 1000);
  }
  if (out_error) {
    *out_error = g_strdup(
        "IKEv2 sanity check failed: connection is not active in NetworkManager or tunnel interface is missing.");
  }
  return FALSE;
}

static void refresh_runtime_connection_state(VpnChannelState* state) {
  if (!state) {
    return;
  }

  const gchar* active = state->active_protocol;
  if (active) {
    if (g_strcmp0(active, "wireguard") == 0 || g_strcmp0(active, "wg") == 0) {
      const gboolean has_sw_wg = interface_exists("sw-wg");
      const gboolean has_wg0 = interface_exists("wg0");
      const gchar* iface =
          has_sw_wg ? "sw-wg" : (has_wg0 ? "wg0" : nullptr);
      // Require interface AND the policy routing table entry.  Interface alone
      // is not sufficient: wg-quick down strips the IP and removes the table
      // route before deleting the interface — so a half-torn-down interface
      // will have no table route and must be treated as disconnected.
      const gboolean has_table_route =
          iface ? wireguard_table_route_exists(iface) : FALSE;
      if (iface && has_table_route) {
        state->last_connected = TRUE;
        set_active_protocol(state, "wireguard");
        return;
      }
      // Interface exists but routing is broken — treat as disconnected.
      state->last_connected = FALSE;
      set_active_protocol(state, nullptr);
      return;
    }
    if (g_strcmp0(active, "openvpn") == 0 &&
        (interface_exists("tun0") || openvpn_process_alive(state->openvpn_pid_path))) {
      state->last_connected = TRUE;
      set_active_protocol(state, "openvpn");
      return;
    }
    if (g_strcmp0(active, "ikev2") == 0 &&
        (nmcli_connection_active(kIkev2ConnectionName) || interface_exists("ipsec0"))) {
      state->last_connected = TRUE;
      set_active_protocol(state, "ikev2");
      return;
    }
  }

  {
    const gboolean has_sw_wg = interface_exists("sw-wg");
    const gboolean has_wg0 = interface_exists("wg0");
    const gchar* iface = has_sw_wg ? "sw-wg" : (has_wg0 ? "wg0" : nullptr);
    if (iface && wireguard_table_route_exists(iface)) {
      state->last_connected = TRUE;
      set_active_protocol(state, "wireguard");
      return;
    }
  }
  if (nmcli_connection_active(kIkev2ConnectionName) || interface_exists("ipsec0")) {
    state->last_connected = TRUE;
    set_active_protocol(state, "ikev2");
    return;
  }
  if (interface_exists("tun0") || openvpn_process_alive(state->openvpn_pid_path)) {
    state->last_connected = TRUE;
    set_active_protocol(state, "openvpn");
    return;
  }

  state->last_connected = FALSE;
  set_active_protocol(state, nullptr);
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
    refresh_runtime_connection_state(state);
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
  if (g_strcmp0(method, "getTrafficStats") == 0) {
    refresh_runtime_connection_state(state);
    g_autoptr(FlValue) map = fl_value_new_map();
    fl_value_set_string_take(
        map, "connected", fl_value_new_bool(state->last_connected));

    if (!state->last_connected) {
      fl_value_set_string_take(map, "rx_bytes", fl_value_new_int(0));
      fl_value_set_string_take(map, "tx_bytes", fl_value_new_int(0));
      fl_value_set_string_take(
          map, "timestamp_ms",
          fl_value_new_int(static_cast<gint64>(g_get_real_time() / 1000)));
      g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
          fl_method_success_response_new(map));
      fl_method_call_respond(method_call, response, nullptr);
      return;
    }

    g_autofree gchar* iface = detect_active_interface(state->active_protocol);
    guint64 rx_bytes = 0;
    guint64 tx_bytes = 0;
    if (iface) {
      fl_value_set_string_take(map, "interface", fl_value_new_string(iface));
      if (!read_interface_counter(iface, "rx_bytes", &rx_bytes) ||
          !read_interface_counter(iface, "tx_bytes", &tx_bytes)) {
        rx_bytes = 0;
        tx_bytes = 0;
      }
    } else {
      fl_value_set_string_take(map, "interface", fl_value_new_string(""));
    }
    if (state->active_protocol && *state->active_protocol != '\0') {
      fl_value_set_string_take(
          map, "protocol", fl_value_new_string(state->active_protocol));
    }
    fl_value_set_string_take(
        map, "rx_bytes",
        fl_value_new_int(static_cast<gint64>(rx_bytes)));
    fl_value_set_string_take(
        map, "tx_bytes",
        fl_value_new_int(static_cast<gint64>(tx_bytes)));
    fl_value_set_string_take(
        map, "timestamp_ms",
        fl_value_new_int(static_cast<gint64>(g_get_real_time() / 1000)));

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
      // Privileged preflight: bring down any stale tunnel + clear ip rules.
      // wg_preflight_cleanup runs unprivileged (best-effort for what it can
      // reach); the helper down call clears root-owned state (ip rule/route).
      wg_preflight_cleanup(state->wg_config_path);
      if (geteuid() != 0 && securewave_wg_helper_available()) {
        g_autofree gchar* pkexec_pre = g_find_program_in_path("pkexec");
        if (pkexec_pre) {
          gchar* pre_argv[] = {pkexec_pre,
                               const_cast<gchar*>(kSecureWaveWgHelperPath),
                               const_cast<gchar*>("down"),
                               state->wg_config_path, nullptr};
          run_quiet_command(pre_argv);
        }
      }
      // Prevent NM from auto-managing sw-wg (eliminates "Activation failed"
      // popup race — see comment on ensure_nm_unmanaged_rule).
      ensure_nm_unmanaged_rule();
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
      const gchar* auth_method = get_string_from_map(profile, "auth_method");
      if (!ovpn_config || *ovpn_config == '\0') {
        respond_error(
            method_call,
            "invalid_profile",
            "OpenVPN profile is missing ovpn_config.",
            nullptr);
        return;
      }
      // mTLS profiles supply username (CN) but no password — that is valid.
      // Only enforce the both-or-neither rule for userpass auth.
      const gboolean is_mtls = (g_strcmp0(auth_method, "mtls") == 0);
      if (!is_mtls &&
          (username && *username != '\0') != (password && *password != '\0')) {
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

      g_autofree gchar* code = nullptr;
      g_autofree gchar* message = nullptr;
      if (!run_command_step(
              argv,
              "vpn_connect_failed",
              "Failed to start OpenVPN.",
              &code,
              &message)) {
        respond_error(method_call, code, message, nullptr);
        return;
      }

      g_autofree gchar* sanity_error = nullptr;
      if (!verify_openvpn_runtime(state, &sanity_error)) {
        gint openvpn_pid = 0;
        if (read_pid_file(state->openvpn_pid_path, &openvpn_pid)) {
          kill(openvpn_pid, SIGTERM);
        }
        respond_error(
            method_call,
            "vpn_connect_failed",
            sanity_error ? sanity_error
                         : "OpenVPN connect sanity check failed.",
            nullptr);
        return;
      }

      state->last_connected = TRUE;
      set_active_protocol(state, "openvpn");
      g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
          fl_method_success_response_new(nullptr));
      fl_method_call_respond(method_call, response, nullptr);
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

      g_autofree gchar* up_code = nullptr;
      g_autofree gchar* up_message = nullptr;
      if (!run_command_step(
              up_argv,
              "vpn_connect_failed",
              "Failed to establish IKEv2 connection.",
              &up_code,
              &up_message)) {
        respond_error(method_call, up_code, up_message, nullptr);
        return;
      }

      g_autofree gchar* sanity_error = nullptr;
      if (!verify_ikev2_runtime(&sanity_error)) {
        gchar* down_argv[10] = {nullptr};
        int didx = 0;
        if (needs_elevation) {
          down_argv[didx++] = pkexec_path;
        }
        down_argv[didx++] = const_cast<gchar*>("nmcli");
        down_argv[didx++] = const_cast<gchar*>("connection");
        down_argv[didx++] = const_cast<gchar*>("down");
        down_argv[didx++] = const_cast<gchar*>("id");
        down_argv[didx++] = const_cast<gchar*>(kIkev2ConnectionName);
        down_argv[didx] = nullptr;
        run_quiet_command(down_argv);
        respond_error(
            method_call,
            "vpn_connect_failed",
            sanity_error ? sanity_error
                         : "IKEv2 connect sanity check failed.",
            nullptr);
        return;
      }

      state->last_connected = TRUE;
      set_active_protocol(state, "ikev2");
      g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
          fl_method_success_response_new(nullptr));
      fl_method_call_respond(method_call, response, nullptr);
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
    refresh_runtime_connection_state(state);
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
      g_autofree gchar* code = nullptr;
      g_autofree gchar* message = nullptr;
      if (!run_command_step(
              argv,
              "vpn_disconnect_failed",
              "Failed to stop OpenVPN tunnel.",
              &code,
              &message)) {
        respond_error(method_call, code, message, nullptr);
        return;
      }
      if (state->openvpn_pid_path) {
        g_remove(state->openvpn_pid_path);
      }
      state->last_connected = FALSE;
      set_active_protocol(state, nullptr);
      g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
          fl_method_success_response_new(nullptr));
      fl_method_call_respond(method_call, response, nullptr);
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

      gchar* delete_argv[10] = {nullptr};
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
      g_autofree gchar* delete_code = nullptr;
      g_autofree gchar* delete_message = nullptr;
      if (!run_command_step(
              delete_argv,
              "vpn_disconnect_failed",
              "Failed to clean up IKEv2 connection profile.",
              &delete_code,
              &delete_message)) {
        g_autofree gchar* lower = g_ascii_strdown(delete_message, -1);
        if (!lower || g_strrstr(lower, "unknown connection") == nullptr) {
          respond_error(method_call, delete_code, delete_message, nullptr);
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
