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
#include <map>
#include <sstream>
#include <string>
#include <utility>

#include "flutter/generated_plugin_registrant.h"

namespace {
const char* kChannelName = "securewave/vpn";
const char* kHelperSocketPath = "/run/securewave/helper.sock";
const char* kWireGuardConfigFileName = "sw-wg.conf";
const char* kOpenVpnPidFileName = "securewave-openvpn.pid";
const char* kOpenVpnLogFileName = "securewave-openvpn.log";
const char* kOpenVpnAuthFileName = "securewave-openvpn.auth";
const char* kIkev2ConfigFileName = "securewave-ikev2.conf";

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

using HelperFields = std::map<std::string, std::string>;

static std::string helper_escape(const std::string& value) {
  std::string escaped;
  for (const char c : value) {
    if (c == '\\') escaped += "\\\\";
    else if (c == '\n') escaped += "\\n";
    else if (c == '\r') escaped += "\\r";
    else escaped += c;
  }
  return escaped;
}

static std::string helper_unescape(const std::string& value) {
  std::string unescaped;
  for (size_t i = 0; i < value.size(); ++i) {
    if (value[i] == '\\' && i + 1 < value.size()) {
      const char next = value[++i];
      unescaped += next == 'n' ? '\n' : (next == 'r' ? '\r' : next);
    } else {
      unescaped += value[i];
    }
  }
  return unescaped;
}

static std::string helper_serialize(const HelperFields& fields) {
  std::string body;
  for (const auto& item : fields) {
    body += item.first + "=" + helper_escape(item.second) + "\n";
  }
  return body;
}

static HelperFields helper_parse(const std::string& body) {
  HelperFields fields;
  std::istringstream stream(body);
  std::string line;
  while (std::getline(stream, line)) {
    const auto separator = line.find('=');
    if (separator == std::string::npos) continue;
    fields[line.substr(0, separator)] = helper_unescape(line.substr(separator + 1));
  }
  return fields;
}

static gboolean helper_write_all(int fd, const std::string& body) {
  size_t offset = 0;
  while (offset < body.size()) {
    const ssize_t written = write(fd, body.data() + offset, body.size() - offset);
    if (written < 0 && errno == EINTR) continue;
    if (written <= 0) return FALSE;
    offset += static_cast<size_t>(written);
  }
  return TRUE;
}

static gboolean helper_request(const HelperFields& request,
                               HelperFields* response,
                               std::string* error_message) {
  const int fd = socket(AF_UNIX, SOCK_STREAM, 0);
  if (fd < 0) {
    *error_message = "Unable to open SecureWave VPN helper socket.";
    return FALSE;
  }
  struct sockaddr_un address {};
  address.sun_family = AF_UNIX;
  g_strlcpy(address.sun_path, kHelperSocketPath, sizeof(address.sun_path));
  if (connect(fd, reinterpret_cast<struct sockaddr*>(&address), sizeof(address)) != 0) {
    *error_message = "SecureWave VPN helper is not running. Start securewave-helper.service and retry.";
    close(fd);
    return FALSE;
  }
  const std::string body = helper_serialize(request);
  if (!helper_write_all(fd, body)) {
    *error_message = "Unable to send the VPN request to the SecureWave helper.";
    close(fd);
    return FALSE;
  }
  shutdown(fd, SHUT_WR);
  std::string raw;
  char buffer[4096];
  while (true) {
    const ssize_t count = read(fd, buffer, sizeof(buffer));
    if (count < 0 && errno == EINTR) continue;
    if (count <= 0) break;
    raw.append(buffer, static_cast<size_t>(count));
  }
  close(fd);
  if (raw.empty()) {
    *error_message = "SecureWave VPN helper returned no response.";
    return FALSE;
  }
  *response = helper_parse(raw);
  return TRUE;
}

static void respond_helper_result(FlMethodCall* method_call,
                                  const HelperFields& response,
                                  const std::string& transport_error) {
  if (!transport_error.empty()) {
    respond_error(method_call, "vpn_unavailable", transport_error.c_str(), nullptr);
    return;
  }
  const auto ok = response.find("ok");
  if (ok != response.end() && ok->second == "true") {
    g_autoptr(FlMethodResponse) success = FL_METHOD_RESPONSE(
        fl_method_success_response_new(nullptr));
    fl_method_call_respond(method_call, success, nullptr);
    return;
  }
  const auto code = response.find("code");
  const auto message = response.find("message");
  respond_error(method_call,
                code == response.end() ? "vpn_connect_failed" : code->second.c_str(),
                message == response.end() ? "VPN helper operation failed." : message->second.c_str(),
                nullptr);
}

struct HelperCallContext {
  FlMethodCall* method_call;
  HelperFields request;
  HelperFields response;
  std::string transport_error;
};

static gboolean finish_helper_request(gpointer user_data) {
  auto* context = static_cast<HelperCallContext*>(user_data);
  respond_helper_result(context->method_call, context->response,
                        context->transport_error);
  g_object_unref(context->method_call);
  delete context;
  return G_SOURCE_REMOVE;
}

static gpointer run_helper_request(gpointer user_data) {
  auto* context = static_cast<HelperCallContext*>(user_data);
  helper_request(context->request, &context->response,
                 &context->transport_error);
  g_main_context_invoke(nullptr, finish_helper_request, context);
  return nullptr;
}

static void start_helper_request(FlMethodCall* method_call,
                                 HelperFields request) {
  auto* context = new HelperCallContext{
      FL_METHOD_CALL(g_object_ref(method_call)), std::move(request), {}, {}};
  GThread* thread = g_thread_new("securewave-vpn-helper", run_helper_request,
                                 context);
  g_thread_unref(thread);
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
            access(kHelperSocketPath, F_OK) == 0)));
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
      start_helper_request(method_call,
                           {{"version", "1"}, {"op", "wireguard.up"},
                            {"config_path", state->config_path}});
      return;
    }

    if (g_strcmp0(protocol, "openvpn") == 0) {
      // The current backend does not issue an authenticated OpenVPN
      // credential or pass an auth-file path to this runner.  Refuse before
      // writing profile material or changing active protocol state.
      respond_error(
          method_call,
          "protocol_unavailable",
          "OpenVPN is unavailable until authenticated current-source runtime and credential evidence is recorded.",
          nullptr);
      return;
    }

    if (g_strcmp0(protocol, "ikev2") == 0) {
      g_clear_pointer(&state->config_path, g_free);
      state->config_path = build_state_path(kIkev2ConfigFileName);
      if (state->config_path == nullptr) {
        respond_error(method_call, "vpn_config_write_failed", "Unable to write IKEv2 state files.", nullptr);
        return;
      }
      g_autoptr(GError) error = nullptr;
      if (!g_file_set_contents(state->config_path, config, -1, &error)) {
        respond_error(method_call, "vpn_config_write_failed", error->message, nullptr);
        return;
      }
      g_chmod(state->config_path, 0600);
      g_clear_pointer(&state->active_protocol, g_free);
      state->active_protocol = g_strdup("ikev2");
      start_helper_request(method_call,
                           {{"version", "1"}, {"op", "ikev2.start"},
                            {"config_path", state->config_path}});
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
      if (!state->openvpn_log_path) {
        state->openvpn_log_path = build_state_path(kOpenVpnLogFileName);
      }
      g_autofree gchar* openvpn_auth_path = build_state_path(kOpenVpnAuthFileName);
      if (!openvpn_auth_path) {
        respond_error(method_call, "vpn_config_missing", "OpenVPN auth file path unavailable.", nullptr);
        return;
      }
      start_helper_request(method_call,
                           {{"version", "1"}, {"op", "openvpn.cleanup"},
                            {"pid_path", state->openvpn_pid_path},
                            {"log_path", state->openvpn_log_path},
                            {"auth_path", openvpn_auth_path}});
      return;
    }

    if (g_strcmp0(active_protocol, "ikev2") == 0) {
      start_helper_request(method_call,
                           {{"version", "1"}, {"op", "ikev2.cleanup"}});
      return;
    }

    if (!state->config_path || !g_file_test(state->config_path, G_FILE_TEST_EXISTS)) {
      state->config_path = build_state_path(kWireGuardConfigFileName);
    }
    if (!state->config_path || !g_file_test(state->config_path, G_FILE_TEST_EXISTS)) {
      start_helper_request(method_call,
                           {{"version", "1"}, {"op", "wireguard.cleanup"}});
      return;
    }
    start_helper_request(method_call,
                         {{"version", "1"}, {"op", "wireguard.down"},
                          {"config_path", state->config_path}});
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
