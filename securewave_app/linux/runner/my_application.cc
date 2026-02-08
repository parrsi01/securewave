#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif
#include <gio/gio.h>
#include <glib/gstdio.h>

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
const char* kConfigFileName = "securewave.conf";

typedef struct {
  FlMethodChannel* channel;
  gchar* config_path;
} VpnChannelState;

static void vpn_channel_state_free(VpnChannelState* state) {
  if (!state) {
    return;
  }
  g_clear_object(&state->channel);
  g_clear_pointer(&state->config_path, g_free);
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

static gchar* build_config_path() {
  g_autofree gchar* config_dir = g_build_filename(g_get_user_config_dir(), "securewave", nullptr);
  if (g_mkdir_with_parents(config_dir, 0700) != 0) {
    return nullptr;
  }
  return g_build_filename(config_dir, kConfigFileName, nullptr);
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

static void handle_vpn_call(FlMethodChannel* channel,
                            FlMethodCall* method_call,
                            gpointer user_data) {
  (void)channel;  // Unused; the channel is already held in VpnChannelState.
  VpnChannelState* state = static_cast<VpnChannelState*>(user_data);
  const gchar* method = fl_method_call_get_name(method_call);
  if (g_strcmp0(method, "isAvailable") == 0) {
    g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
        fl_method_success_response_new(fl_value_new_bool(wg_quick_available())));
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }
  if (g_strcmp0(method, "connect") == 0) {
    if (!wg_quick_available()) {
      respond_error(
          method_call,
          "vpn_unavailable",
          "wg-quick not found. Install wireguard-tools (e.g. sudo apt-get install wireguard-tools) and retry.",
          fl_value_new_map());
      return;
    }
    FlValue* args = fl_method_call_get_args(method_call);
    const gchar* config = get_string_arg(args, "config");
    if (!config || *config == '\0') {
      respond_error(method_call, "invalid_config", "Missing WireGuard configuration.", nullptr);
      return;
    }
    if (state->config_path == nullptr) {
      state->config_path = build_config_path();
    }
    if (state->config_path == nullptr) {
      respond_error(method_call, "vpn_config_write_failed", "Unable to write config file.", nullptr);
      return;
    }
    g_autoptr(GError) error = nullptr;
    if (!g_file_set_contents(state->config_path, config, -1, &error)) {
      respond_error(method_call, "vpn_config_write_failed", error->message, nullptr);
      return;
    }
    gchar* argv[] = {
        const_cast<gchar*>("wg-quick"),
        const_cast<gchar*>("up"),
        state->config_path,
        nullptr
    };
    gint exit_status = 0;
    if (!g_spawn_sync(nullptr, argv, nullptr, G_SPAWN_SEARCH_PATH, nullptr, nullptr,
                      nullptr, nullptr, &exit_status, &error)) {
      respond_error(method_call, "vpn_connect_failed", error->message, nullptr);
      return;
    }
    if (!g_spawn_check_wait_status(exit_status, &error)) {
      respond_error(method_call, "vpn_connect_failed", error->message, nullptr);
      return;
    }
    g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
        fl_method_success_response_new(nullptr));
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }
  if (g_strcmp0(method, "disconnect") == 0) {
    if (!wg_quick_available()) {
      respond_error(
          method_call,
          "vpn_unavailable",
          "wg-quick not found. Install wireguard-tools (e.g. sudo apt-get install wireguard-tools) and retry.",
          fl_value_new_map());
      return;
    }
    if (!state->config_path || !g_file_test(state->config_path, G_FILE_TEST_EXISTS)) {
      respond_error(method_call, "vpn_config_missing", "WireGuard config file not found.", nullptr);
      return;
    }
    g_autoptr(GError) error = nullptr;
    gchar* argv[] = {
        const_cast<gchar*>("wg-quick"),
        const_cast<gchar*>("down"),
        state->config_path,
        nullptr
    };
    gint exit_status = 0;
    if (!g_spawn_sync(nullptr, argv, nullptr, G_SPAWN_SEARCH_PATH, nullptr, nullptr,
                      nullptr, nullptr, &exit_status, &error)) {
      respond_error(method_call, "vpn_disconnect_failed", error->message, nullptr);
      return;
    }
    if (!g_spawn_check_wait_status(exit_status, &error)) {
      respond_error(method_call, "vpn_disconnect_failed", error->message, nullptr);
      return;
    }
    g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
        fl_method_success_response_new(nullptr));
    fl_method_call_respond(method_call, response, nullptr);
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
