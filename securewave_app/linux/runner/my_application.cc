#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif
#include <gio/gio.h>
#include <glib/gstdio.h>

#include <fstream>
#include <optional>
#include <sstream>
#include <string>

#include "flutter/generated_plugin_registrant.h"

namespace {
const char* kVpnChannelName = "securewave/vpn";
const char* kTrafficChannelName = "securewave/traffic_stats";
const char* kTunnelStatusChannelName = "securewave/tunnel_status";
const char* kConfigFileName = "securewave.conf";

typedef struct {
  FlMethodChannel* vpn_channel;
  FlMethodChannel* traffic_channel;
  FlMethodChannel* tunnel_status_channel;
  gchar* config_path;
} NativeChannelState;

struct InterfaceStats {
  std::string name;
  gint64 rx_bytes = 0;
  gint64 tx_bytes = 0;
};

static void native_channel_state_free(NativeChannelState* state) {
  if (!state) {
    return;
  }
  g_clear_object(&state->vpn_channel);
  g_clear_object(&state->traffic_channel);
  g_clear_object(&state->tunnel_status_channel);
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
  g_autofree gchar* config_dir =
      g_build_filename(g_get_user_config_dir(), "securewave", nullptr);
  if (g_mkdir_with_parents(config_dir, 0700) != 0) {
    return nullptr;
  }
  return g_build_filename(config_dir, kConfigFileName, nullptr);
}

static void respond_error(FlMethodCall* method_call,
                          const gchar* code,
                          const gchar* message,
                          FlValue* details) {
  g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
      fl_method_error_response_new(code, message, details));
  fl_method_call_respond(method_call, response, nullptr);
}

static gboolean run_command(const gchar* const* argv,
                            gchar** stdout_text,
                            GError** error) {
  gint exit_status = 0;
  return g_spawn_sync(nullptr, const_cast<gchar**>(argv), nullptr,
                      G_SPAWN_SEARCH_PATH, nullptr, nullptr, stdout_text,
                      nullptr, &exit_status, error) &&
         g_spawn_check_exit_status(exit_status, error);
}

static std::optional<InterfaceStats> detect_tunnel_interface() {
  std::ifstream input("/proc/net/dev");
  if (!input.is_open()) {
    return std::nullopt;
  }

  std::string line;
  for (int index = 0; index < 2 && std::getline(input, line); ++index) {
  }

  std::optional<InterfaceStats> candidate;
  while (std::getline(input, line)) {
    const auto separator = line.find(':');
    if (separator == std::string::npos) {
      continue;
    }
    std::string name = line.substr(0, separator);
    name.erase(0, name.find_first_not_of(" \t"));
    name.erase(name.find_last_not_of(" \t") + 1);
    if (!(name.rfind("wg", 0) == 0 || name.rfind("tun", 0) == 0 ||
          name.rfind("utun", 0) == 0)) {
      continue;
    }
    std::istringstream stats_stream(line.substr(separator + 1));
    InterfaceStats stats;
    stats.name = name;
    stats_stream >> stats.rx_bytes;
    for (int skip = 0; skip < 7; ++skip) {
      gint64 ignored = 0;
      stats_stream >> ignored;
    }
    stats_stream >> stats.tx_bytes;
    candidate = stats;
  }
  return candidate;
}

static std::optional<std::string> default_route_interface() {
  const gchar* argv[] = {"sh", "-c", "ip route get 1.1.1.1", nullptr};
  g_autofree gchar* stdout_text = nullptr;
  g_autoptr(GError) error = nullptr;
  if (!run_command(argv, &stdout_text, &error) || stdout_text == nullptr) {
    return std::nullopt;
  }

  std::string output(stdout_text);
  const std::string token = " dev ";
  const auto token_index = output.find(token);
  if (token_index == std::string::npos) {
    return std::nullopt;
  }
  const auto start = token_index + token.size();
  const auto end = output.find(' ', start);
  return output.substr(start, end - start);
}

static FlValue* build_traffic_payload() {
  g_autoptr(FlValue) map = fl_value_new_map();
  const auto stats = detect_tunnel_interface();
  fl_value_set_string_take(map, "rxBytes",
                           fl_value_new_int(stats.has_value() ? stats->rx_bytes : 0));
  fl_value_set_string_take(map, "txBytes",
                           fl_value_new_int(stats.has_value() ? stats->tx_bytes : 0));
  fl_value_set_string_take(
      map, "interfaceName",
      stats.has_value() ? fl_value_new_string(stats->name.c_str())
                        : fl_value_new_string(""));
  return fl_value_ref(map);
}

static FlValue* build_tunnel_status_payload() {
  const auto stats = detect_tunnel_interface();
  const auto route_interface = default_route_interface();
  const gboolean interface_ok = stats.has_value();
  const gboolean routing_ok =
      interface_ok && route_interface.has_value() &&
      route_interface.value() == stats->name;

  g_autoptr(FlValue) map = fl_value_new_map();
  fl_value_set_string_take(
      map, "status",
      fl_value_new_string(interface_ok ? "CONNECTED" : "DISCONNECTED"));
  fl_value_set_string_take(
      map, "interfaceName",
      interface_ok ? fl_value_new_string(stats->name.c_str())
                   : fl_value_new_string(""));
  fl_value_set_string_take(map, "interfaceOk", fl_value_new_bool(interface_ok));
  fl_value_set_string_take(map, "routingOk", fl_value_new_bool(routing_ok));
  fl_value_set_string_take(
      map, "details",
      fl_value_new_string(interface_ok ? "Detected active Linux tunnel interface."
                                       : "No wg/tun interface detected."));
  return fl_value_ref(map);
}

static void handle_vpn_call(FlMethodCall* method_call, gpointer user_data) {
  NativeChannelState* state = static_cast<NativeChannelState*>(user_data);
  const gchar* method = fl_method_call_get_name(method_call);
  if (g_strcmp0(method, "isAvailable") == 0) {
    g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
        fl_method_success_response_new(fl_value_new_bool(wg_quick_available())));
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }

  if (g_strcmp0(method, "connect") == 0) {
    if (!wg_quick_available()) {
      respond_error(method_call, "vpn_unavailable",
                    "wg-quick not found. Install WireGuard tools and retry.",
                    fl_value_new_map());
      return;
    }
    FlValue* args = fl_method_call_get_args(method_call);
    const gchar* config = get_string_arg(args, "config");
    if (!config || *config == '\0') {
      respond_error(method_call, "invalid_config",
                    "Missing WireGuard configuration.", nullptr);
      return;
    }
    if (state->config_path == nullptr) {
      state->config_path = build_config_path();
    }
    if (state->config_path == nullptr) {
      respond_error(method_call, "vpn_config_write_failed",
                    "Unable to write config file.", nullptr);
      return;
    }
    g_autoptr(GError) error = nullptr;
    if (!g_file_set_contents(state->config_path, config, -1, &error)) {
      respond_error(method_call, "vpn_config_write_failed", error->message,
                    nullptr);
      return;
    }
    const gchar* argv[] = {"wg-quick", "up", state->config_path, nullptr};
    if (!run_command(argv, nullptr, &error)) {
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
      respond_error(method_call, "vpn_unavailable",
                    "wg-quick not found. Install WireGuard tools and retry.",
                    fl_value_new_map());
      return;
    }
    if (!state->config_path || !g_file_test(state->config_path, G_FILE_TEST_EXISTS)) {
      respond_error(method_call, "vpn_config_missing",
                    "WireGuard config file not found.", nullptr);
      return;
    }
    g_autoptr(GError) error = nullptr;
    const gchar* argv[] = {"wg-quick", "down", state->config_path, nullptr};
    if (!run_command(argv, nullptr, &error)) {
      respond_error(method_call, "vpn_disconnect_failed", error->message,
                    nullptr);
      return;
    }
    g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
        fl_method_success_response_new(nullptr));
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }

  g_autoptr(FlMethodResponse) response =
      FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  fl_method_call_respond(method_call, response, nullptr);
}

static void handle_traffic_call(FlMethodCall* method_call, gpointer user_data) {
  const gchar* method = fl_method_call_get_name(method_call);
  if (g_strcmp0(method, "getTrafficStats") == 0) {
    g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
        fl_method_success_response_new(build_traffic_payload()));
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }

  g_autoptr(FlMethodResponse) response =
      FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  fl_method_call_respond(method_call, response, nullptr);
}

static void handle_tunnel_status_call(FlMethodCall* method_call,
                                      gpointer user_data) {
  const gchar* method = fl_method_call_get_name(method_call);
  if (g_strcmp0(method, "getTunnelStatus") == 0) {
    g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
        fl_method_success_response_new(build_tunnel_status_payload()));
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }

  g_autoptr(FlMethodResponse) response =
      FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  fl_method_call_respond(method_call, response, nullptr);
}

}  // namespace

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "securewave_app");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "securewave_app");
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
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  FlEngine* engine = fl_view_get_engine(view);
  NativeChannelState* native_state = g_new0(NativeChannelState, 1);
  native_state->vpn_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(engine), kVpnChannelName,
      FL_METHOD_CODEC(fl_standard_method_codec_new()));
  native_state->traffic_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(engine), kTrafficChannelName,
      FL_METHOD_CODEC(fl_standard_method_codec_new()));
  native_state->tunnel_status_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(engine), kTunnelStatusChannelName,
      FL_METHOD_CODEC(fl_standard_method_codec_new()));

  fl_method_channel_set_method_call_handler(
      native_state->vpn_channel, handle_vpn_call, native_state, nullptr);
  fl_method_channel_set_method_call_handler(
      native_state->traffic_channel, handle_traffic_call, native_state, nullptr);
  fl_method_channel_set_method_call_handler(native_state->tunnel_status_channel,
                                            handle_tunnel_status_call,
                                            native_state,
                                            reinterpret_cast<GDestroyNotify>(
                                                native_channel_state_free));

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
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
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(), "application-id",
                                     APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
