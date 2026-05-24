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
const char* kWireGuardConfigFileName = "securewave.conf";
const char* kOpenVpnConfigFileName = "securewave.ovpn";
const char* kOpenVpnPidFileName = "securewave-openvpn.pid";
const char* kOpenVpnLogFileName = "securewave-openvpn.log";
const guint kWgQuickTimeoutMs = 30000;
const guint kOpenVpnTimeoutMs = 10000;

typedef struct {
  FlMethodChannel* channel;
  gchar* config_path;
  gchar* openvpn_pid_path;
  gchar* openvpn_log_path;
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

static gboolean openvpn_available() {
  g_autofree gchar* openvpn = g_find_program_in_path("openvpn");
  return openvpn != nullptr;
}

static gboolean ikev2_available() {
  g_autofree gchar* swanctl = g_find_program_in_path("swanctl");
  g_autofree gchar* ipsec = g_find_program_in_path("ipsec");
  return swanctl != nullptr && ipsec != nullptr;
}

static gboolean elevated_runner_available() {
  if (geteuid() == 0) {
    return TRUE;
  }
  g_autofree gchar* pkexec = g_find_program_in_path("pkexec");
  return pkexec != nullptr;
}

static gchar* build_state_path(const gchar* filename) {
  g_autofree gchar* config_dir = g_build_filename(g_get_user_config_dir(), "securewave", nullptr);
  if (g_mkdir_with_parents(config_dir, 0700) != 0) {
    return nullptr;
  }
  return g_build_filename(config_dir, filename, nullptr);
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

typedef struct {
  gint ref_count;
  FlMethodCall* method_call;
  gchar* error_code;
  GPid pid;
  guint timeout_id;
  guint timeout_ms;
  gboolean responded;
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

static void wg_quick_child_watch_cb(GPid pid, gint wait_status, gpointer user_data) {
  WgQuickSpawnContext* ctx = static_cast<WgQuickSpawnContext*>(user_data);
  if (ctx->timeout_id != 0) {
    g_source_remove(ctx->timeout_id);
    ctx->timeout_id = 0;
  }
  g_autoptr(GError) error = nullptr;
  if (!g_spawn_check_wait_status(wait_status, &error)) {
    wg_quick_respond_error_once(ctx, error ? error->message : "wg-quick failed.");
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
    const gchar* config_path) {
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
  }
  g_ptr_array_add(argv_array, wg_quick);
  g_ptr_array_add(argv_array, const_cast<gchar*>(action));
  g_ptr_array_add(argv_array, const_cast<gchar*>(config_path));
  g_ptr_array_add(argv_array, nullptr);
  gchar** argv = reinterpret_cast<gchar**>(argv_array->pdata);

  GPid pid = 0;
  if (!g_spawn_async(nullptr, argv, nullptr,
                     static_cast<GSpawnFlags>(G_SPAWN_SEARCH_PATH | G_SPAWN_DO_NOT_REAP_CHILD),
                     nullptr, nullptr, &pid, &error)) {
    g_ptr_array_free(argv_array, TRUE);
    respond_error(method_call, error_code, error ? error->message : "Failed to spawn wg-quick.", nullptr);
    return;
  }
  g_ptr_array_free(argv_array, TRUE);

  WgQuickSpawnContext* ctx = g_new0(WgQuickSpawnContext, 1);
  ctx->ref_count = 1;
  ctx->method_call = FL_METHOD_CALL(g_object_ref(method_call));
  ctx->error_code = g_strdup(error_code);
  ctx->pid = pid;
  ctx->timeout_ms = kWgQuickTimeoutMs;
  ctx->responded = FALSE;
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

static void spawn_shell_async(
    FlMethodCall* method_call,
    const gchar* error_code,
    const gchar* script,
    guint timeout_ms) {
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
          "Starting VPN tunnels requires administrator privileges. Install PolicyKit/pkexec or run SecureWave with the required permissions.",
          nullptr);
      return;
    }
    g_ptr_array_add(argv_array, pkexec);
  }
  g_ptr_array_add(argv_array, const_cast<gchar*>("/bin/sh"));
  g_ptr_array_add(argv_array, const_cast<gchar*>("-c"));
  g_ptr_array_add(argv_array, const_cast<gchar*>(script));
  g_ptr_array_add(argv_array, nullptr);
  gchar** argv = reinterpret_cast<gchar**>(argv_array->pdata);

  GPid pid = 0;
  if (!g_spawn_async(nullptr, argv, nullptr,
                     static_cast<GSpawnFlags>(G_SPAWN_SEARCH_PATH | G_SPAWN_DO_NOT_REAP_CHILD),
                     nullptr, nullptr, &pid, &error)) {
    g_ptr_array_free(argv_array, TRUE);
    respond_error(method_call, error_code, error ? error->message : "Failed to spawn VPN command.", nullptr);
    return;
  }
  g_ptr_array_free(argv_array, TRUE);

  WgQuickSpawnContext* ctx = g_new0(WgQuickSpawnContext, 1);
  ctx->ref_count = 1;
  ctx->method_call = FL_METHOD_CALL(g_object_ref(method_call));
  ctx->error_code = g_strdup(error_code);
  ctx->pid = pid;
  ctx->timeout_ms = timeout_ms;
  ctx->responded = FALSE;
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
  g_autofree gchar* q_openvpn = g_shell_quote(openvpn);
  g_autofree gchar* q_config = g_shell_quote(config_path);
  g_autofree gchar* q_pid = g_shell_quote(pid_path);
  g_autofree gchar* q_log = g_shell_quote(log_path);
  g_autofree gchar* script = g_strdup_printf(
      "%s --config %s --daemon securewave-openvpn --writepid %s --log %s; "
      "sleep 2; test -s %s && kill -0 $(cat %s)",
      q_openvpn, q_config, q_pid, q_log, q_pid, q_pid);
  spawn_shell_async(method_call, "vpn_connect_failed", script, kOpenVpnTimeoutMs);
}

static void spawn_openvpn_down_async(
    FlMethodCall* method_call,
    const gchar* pid_path) {
  g_autofree gchar* q_pid = g_shell_quote(pid_path);
  g_autofree gchar* script = g_strdup_printf(
      "if test -s %s; then kill $(cat %s); rm -f %s; fi",
      q_pid, q_pid, q_pid);
  spawn_shell_async(method_call, "vpn_disconnect_failed", script, kOpenVpnTimeoutMs);
}

static void handle_vpn_call(FlMethodChannel* channel,
                            FlMethodCall* method_call,
                            gpointer user_data) {
  (void)channel;  // Unused; the channel is already held in VpnChannelState.
  VpnChannelState* state = static_cast<VpnChannelState*>(user_data);
  const gchar* method = fl_method_call_get_name(method_call);
  if (g_strcmp0(method, "isAvailable") == 0) {
    g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
        fl_method_success_response_new(fl_value_new_bool(
            elevated_runner_available() &&
            (wg_quick_available() || openvpn_available() || ikev2_available()))));
    fl_method_call_respond(method_call, response, nullptr);
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
      g_clear_pointer(&state->active_protocol, g_free);
      state->active_protocol = g_strdup("wireguard");
      spawn_wg_quick_async(method_call, "vpn_connect_failed", "up", state->config_path);
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
      g_clear_pointer(&state->active_protocol, g_free);
      state->active_protocol = g_strdup("openvpn");
      spawn_openvpn_up_async(method_call, state->config_path, state->openvpn_pid_path, state->openvpn_log_path);
      return;
    }

    if (g_strcmp0(protocol, "ikev2") == 0) {
      if (!ikev2_available()) {
        respond_error(
            method_call,
            "vpn_unavailable",
            "IKEv2 requires strongSwan swanctl and ipsec tooling. Install strongSwan NetworkManager support and retry.",
            fl_value_new_map());
        return;
      }
      respond_error(
          method_call,
          "protocol_unavailable",
          "IKEv2 profile import/start is not wired in this Linux runner yet.",
          nullptr);
      return;
    }

    respond_error(method_call, "protocol_unavailable", "Unsupported VPN protocol.", nullptr);
    return;
  }
  if (g_strcmp0(method, "disconnect") == 0) {
    const gchar* active_protocol = state->active_protocol ? state->active_protocol : "wireguard";
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
      respond_error(
          method_call,
          "protocol_unavailable",
          "IKEv2 profile cleanup is not wired in this Linux runner yet.",
          nullptr);
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
    spawn_wg_quick_async(method_call, "vpn_disconnect_failed", "down", state->config_path);
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
                                     "application-id", APPLICATION_ID, nullptr));
}
