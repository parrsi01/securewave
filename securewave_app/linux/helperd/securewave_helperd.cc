#include <glib.h>
#include <glib/gstdio.h>

#include <grp.h>
#include <pwd.h>
#include <signal.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/un.h>
#include <unistd.h>

#include <algorithm>
#include <cerrno>
#include <cstdint>
#include <ctime>
#include <cstring>
#include <fstream>
#include <map>
#include <set>
#include <sstream>
#include <string>
#include <vector>

#if !GLIB_CHECK_VERSION(2, 70, 0)
static inline gboolean g_spawn_check_wait_status(gint wait_status,
                                                 GError** error) {
  return g_spawn_check_exit_status(wait_status, error);
}
#endif

namespace {

const char* kSocketPath = "/run/securewave/helper.sock";
const char* kRuntimeDir = "/run/securewave";
const char* kHelperPath = "/usr/local/libexec/securewave-wg-quick";
const char* kContractPath = "/usr/local/libexec/securewave-wg-quick.contract";
const char* kAllowedUsersPath = "/etc/securewave/helper-users";
const char* kGroupName = "securewave";
const char* kInterface = "sw-wg";
const char* kConfigName = "sw-wg.conf";
const guint kContractVersion = 13;
const gsize kMaxRequestBytes = 64 * 1024;
const gsize kMaxConfigBytes = 64 * 1024;

using Fields = std::map<std::string, std::string>;

struct CommandResult {
  bool spawned = false;
  bool ok = false;
  std::string out;
  std::string err;
  std::string message;
};

struct ParsedFields {
  Fields fields;
  bool valid = true;
  std::string error;
};

struct PeerCredentials {
  uid_t uid = 0;
  gid_t gid = 0;
  pid_t pid = 0;
  bool valid = false;
};

static std::string Trim(const std::string& value) {
  size_t begin = 0;
  while (begin < value.size() && g_ascii_isspace(value[begin])) {
    begin++;
  }
  size_t end = value.size();
  while (end > begin && g_ascii_isspace(value[end - 1])) {
    end--;
  }
  return value.substr(begin, end - begin);
}

static std::string Field(const Fields& fields, const std::string& key) {
  const auto it = fields.find(key);
  return it == fields.end() ? "" : it->second;
}

static bool StartsWith(const std::string& value, const std::string& prefix) {
  return value.compare(0, prefix.size(), prefix) == 0;
}

static std::string CleanMessage(const std::string& value) {
  std::string clean = Trim(value);
  for (char& character : clean) {
    if (character == '\n' || character == '\r' || character == '\t') {
      character = ' ';
    }
  }
  if (clean.size() > 800) {
    clean.resize(800);
    clean += "...";
  }
  return clean;
}

static std::string EscapeValue(const std::string& value) {
  std::string escaped;
  escaped.reserve(value.size());
  for (char character : value) {
    if (character == '\\') {
      escaped += "\\\\";
    } else if (character == '\n') {
      escaped += "\\n";
    } else if (character == '\r') {
      escaped += "\\r";
    } else {
      escaped += character;
    }
  }
  return escaped;
}

static std::string UnescapeValue(const std::string& value) {
  std::string unescaped;
  unescaped.reserve(value.size());
  for (size_t index = 0; index < value.size(); index++) {
    if (value[index] != '\\' || index + 1 >= value.size()) {
      unescaped += value[index];
      continue;
    }
    const char next = value[++index];
    unescaped += next == 'n' ? '\n' : (next == 'r' ? '\r' : next);
  }
  return unescaped;
}

static ParsedFields ParseFields(const std::string& body) {
  ParsedFields parsed;
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
    if (!line.empty()) {
      const size_t separator = line.find('=');
      if (separator == std::string::npos || separator == 0) {
        parsed.valid = false;
        parsed.error = "Malformed helper request field.";
        return parsed;
      }
      const std::string key = line.substr(0, separator);
      if (parsed.fields.find(key) != parsed.fields.end()) {
        parsed.valid = false;
        parsed.error = "Duplicate helper request field.";
        return parsed;
      }
      parsed.fields[key] = UnescapeValue(line.substr(separator + 1));
    }
    start = end + 1;
  }
  return parsed;
}

static std::string SerializeFields(const Fields& fields) {
  std::string body;
  for (const auto& item : fields) {
    body += item.first;
    body += '=';
    body += EscapeValue(item.second);
    body += '\n';
  }
  return body;
}

static bool WriteAll(int fd, const std::string& data) {
  const char* cursor = data.data();
  size_t remaining = data.size();
  while (remaining > 0) {
    const ssize_t written = write(fd, cursor, remaining);
    if (written < 0 && errno == EINTR) {
      continue;
    }
    if (written <= 0) {
      return false;
    }
    cursor += written;
    remaining -= static_cast<size_t>(written);
  }
  return true;
}

static bool ReadAll(int fd, std::string* output, gsize limit) {
  output->clear();
  char buffer[4096];
  while (true) {
    const ssize_t count = read(fd, buffer, sizeof(buffer));
    if (count < 0 && errno == EINTR) {
      continue;
    }
    if (count < 0 || output->size() + static_cast<gsize>(count) > limit) {
      return false;
    }
    if (count == 0) {
      return true;
    }
    output->append(buffer, static_cast<size_t>(count));
  }
}

static Fields Ok(const Fields& extra = {}) {
  Fields fields = extra;
  fields["ok"] = "true";
  fields["contract"] = std::to_string(kContractVersion);
  return fields;
}

static Fields Error(const std::string& code,
                    const std::string& message,
                    const Fields& extra = {}) {
  Fields fields = extra;
  fields["ok"] = "false";
  fields["contract"] = std::to_string(kContractVersion);
  fields["code"] = code;
  fields["message"] = CleanMessage(message);
  return fields;
}

static std::string ResolveExecutable(const std::string& name) {
  static const char* kDirectories[] = {"/usr/bin", "/usr/sbin", "/bin", "/sbin"};
  for (const char* directory : kDirectories) {
    const std::string path = std::string(directory) + "/" + name;
    if (g_file_test(path.c_str(), G_FILE_TEST_IS_EXECUTABLE)) {
      return path;
    }
  }
  return "";
}

static CommandResult RunProgram(const std::string& executable,
                                const std::vector<std::string>& arguments) {
  CommandResult result;
  if (executable.empty() || !g_file_test(executable.c_str(), G_FILE_TEST_IS_EXECUTABLE)) {
    result.message = "Required Linux networking tool is unavailable.";
    return result;
  }

  std::vector<std::string> values;
  values.reserve(arguments.size() + 1);
  values.push_back(executable);
  values.insert(values.end(), arguments.begin(), arguments.end());
  std::vector<gchar*> argv;
  argv.reserve(values.size() + 1);
  for (std::string& value : values) {
    argv.push_back(const_cast<gchar*>(value.c_str()));
  }
  argv.push_back(nullptr);

  gchar* stdout_text = nullptr;
  gchar* stderr_text = nullptr;
  gint wait_status = 0;
  g_autoptr(GError) error = nullptr;
  gchar** environment = g_get_environ();
  environment = g_environ_setenv(
      environment,
      "PATH",
      "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
      TRUE);
  const gboolean spawned = g_spawn_sync(
      nullptr,
      argv.data(),
      environment,
      G_SPAWN_DEFAULT,
      nullptr,
      nullptr,
      &stdout_text,
      &stderr_text,
      &wait_status,
      &error);
  g_strfreev(environment);
  result.spawned = spawned;
  result.out = stdout_text == nullptr ? "" : stdout_text;
  result.err = stderr_text == nullptr ? "" : stderr_text;
  g_free(stdout_text);
  g_free(stderr_text);
  if (!spawned) {
    result.message = error ? error->message : "Unable to start Linux networking tool.";
    return result;
  }
  result.ok = g_spawn_check_wait_status(wait_status, nullptr);
  if (!result.ok) {
    result.message = !result.err.empty() ? result.err : "Linux networking operation failed.";
  }
  return result;
}

static CommandResult RunTool(const std::string& name,
                             const std::vector<std::string>& arguments) {
  return RunProgram(ResolveExecutable(name), arguments);
}

static CommandResult RunHelper(const std::vector<std::string>& arguments) {
  const std::string bash = ResolveExecutable("bash");
  if (bash.empty() || !g_file_test(kHelperPath, G_FILE_TEST_IS_EXECUTABLE)) {
    CommandResult result;
    result.message = "SecureWave WireGuard helper script is not installed.";
    return result;
  }
  std::vector<std::string> command = {kHelperPath};
  command.insert(command.end(), arguments.begin(), arguments.end());
  return RunProgram(bash, command);
}

static guint InstalledContractVersion() {
  g_autofree gchar* contents = nullptr;
  if (!g_file_get_contents(kContractPath, &contents, nullptr, nullptr) ||
      contents == nullptr) {
    return 0;
  }
  g_strstrip(contents);
  if (*contents == '\0' || *contents == '-' || *contents == '+') {
    return 0;
  }
  gchar* end = nullptr;
  errno = 0;
  const guint64 value = g_ascii_strtoull(contents, &end, 10);
  if (errno != 0 || end == contents || *end != '\0' || value > G_MAXUINT) {
    return 0;
  }
  return static_cast<guint>(value);
}

static bool RequestFieldsAllowed(const Fields& request,
                                 const std::set<std::string>& allowed) {
  for (const auto& item : request) {
    if (allowed.find(item.first) == allowed.end()) {
      return false;
    }
  }
  return true;
}

static bool ContractInstalled(Fields* error) {
  const guint installed = InstalledContractVersion();
  if (installed < kContractVersion) {
    *error = Error(
        "contract_unavailable",
        "SecureWave WireGuard helper contract is missing or out of date.");
    return false;
  }
  return true;
}

static bool PeerGroupsContain(pid_t pid, gid_t group_id) {
  std::ifstream input(
      std::string("/proc/") + std::to_string(static_cast<long>(pid)) + "/status");
  std::string line;
  while (std::getline(input, line)) {
    if (!StartsWith(line, "Groups:")) {
      continue;
    }
    std::istringstream groups(line.substr(strlen("Groups:")));
    unsigned long value = 0;
    while (groups >> value) {
      if (static_cast<gid_t>(value) == group_id) {
        return true;
      }
    }
  }
  return false;
}

static bool UidAllowedByFile(uid_t uid) {
  std::ifstream input(kAllowedUsersPath);
  std::string line;
  while (std::getline(input, line)) {
    line = Trim(line);
    if (line.empty() || line[0] == '#') {
      continue;
    }
    char* end = nullptr;
    errno = 0;
    const unsigned long parsed = strtoul(line.c_str(), &end, 10);
    if (errno == 0 && end != line.c_str() && *Trim(end).c_str() == '\0' &&
        static_cast<uid_t>(parsed) == uid) {
      return true;
    }
  }
  return false;
}

static bool AuthorizedPeer(const PeerCredentials& peer) {
  if (!peer.valid) {
    return false;
  }
  if (peer.uid == 0 || UidAllowedByFile(peer.uid)) {
    return true;
  }
  const struct group* group = getgrnam(kGroupName);
  return group != nullptr &&
         (peer.gid == group->gr_gid || PeerGroupsContain(peer.pid, group->gr_gid));
}

static bool PeerCredentialsForFd(int fd, PeerCredentials* peer) {
  struct ucred credentials {};
  socklen_t length = sizeof(credentials);
  if (getsockopt(fd, SOL_SOCKET, SO_PEERCRED, &credentials, &length) != 0) {
    return false;
  }
  peer->uid = credentials.uid;
  peer->gid = credentials.gid;
  peer->pid = credentials.pid;
  peer->valid = true;
  return true;
}

static std::string PeerConfigPath(uid_t uid) {
  const struct passwd* user = getpwuid(uid);
  if (user == nullptr || user->pw_dir == nullptr || user->pw_dir[0] != '/') {
    return "";
  }
  return std::string(user->pw_dir) + "/.config/securewave/" + kConfigName;
}

static bool ValidateConfigPath(const std::string& path,
                               uid_t peer_uid,
                               bool allow_missing) {
  const std::string expected = PeerConfigPath(peer_uid);
  if (expected.empty() || path != expected) {
    return false;
  }
  struct stat info {};
  if (lstat(path.c_str(), &info) != 0) {
    return allow_missing && errno == ENOENT;
  }
  return S_ISREG(info.st_mode) && info.st_uid == peer_uid &&
         (info.st_mode & 0077) == 0;
}

static bool ReadConfig(const std::string& path, std::string* contents) {
  std::ifstream input(path, std::ios::binary);
  if (!input) {
    return false;
  }
  std::ostringstream buffer;
  buffer << input.rdbuf();
  *contents = buffer.str();
  return contents->size() <= kMaxConfigBytes;
}

static bool ValidConfigContents(const std::string& contents) {
  bool interface_seen = false;
  bool peer_seen = false;
  bool private_key_seen = false;
  bool address_seen = false;
  bool public_key_seen = false;
  bool endpoint_seen = false;
  bool allowed_ips_seen = false;
  std::string section;
  std::istringstream input(contents);
  std::string line;
  while (std::getline(input, line)) {
    line = Trim(line);
    if (line.empty() || line[0] == '#') {
      continue;
    }
    if (line.front() == '[' && line.back() == ']') {
      section = Trim(line.substr(1, line.size() - 2));
      if (section != "Interface" && section != "Peer") {
        return false;
      }
      interface_seen = interface_seen || section == "Interface";
      peer_seen = peer_seen || section == "Peer";
      continue;
    }
    const size_t separator = line.find('=');
    if (separator == std::string::npos || section.empty()) {
      return false;
    }
    const std::string key = Trim(line.substr(0, separator));
    const std::string value = Trim(line.substr(separator + 1));
    if (value.empty() || value.find('\n') != std::string::npos ||
        value.find('\r') != std::string::npos) {
      return false;
    }
    if (key == "PreUp" || key == "PostUp" || key == "PreDown" ||
        key == "PostDown" || key == "Table" || key == "SaveConfig") {
      return false;
    }
    if (section == "Interface") {
      if (key == "PrivateKey") private_key_seen = true;
      if (key == "Address") address_seen = true;
      if (key != "PrivateKey" && key != "Address" && key != "DNS") {
        return false;
      }
    } else {
      if (key == "PublicKey") public_key_seen = true;
      if (key == "Endpoint") endpoint_seen = true;
      if (key == "AllowedIPs") allowed_ips_seen = true;
      if (key != "PublicKey" && key != "Endpoint" && key != "AllowedIPs" &&
          key != "PersistentKeepalive" && key != "PresharedKey") {
        return false;
      }
    }
  }
  return interface_seen && peer_seen && private_key_seen && address_seen &&
         public_key_seen && endpoint_seen && allowed_ips_seen;
}

static bool InterfacePresent() {
  return RunTool("ip", {"link", "show", "dev", kInterface}).ok;
}

static bool RoutesUseInterface(const std::string& family) {
  const CommandResult table = RunTool("ip", {family, "route", "show", "table", "51820"});
  if (table.ok && table.out.find(kInterface) != std::string::npos) {
    return true;
  }
  const CommandResult main = RunTool("ip", {family, "route", "show", "dev", kInterface});
  return main.ok && main.out.find(kInterface) != std::string::npos;
}

static bool HandshakePresent() {
  const CommandResult result = RunTool("wg", {"show", kInterface, "latest-handshakes"});
  if (!result.ok) {
    return false;
  }
  const std::time_t now = std::time(nullptr);
  std::istringstream input(result.out);
  std::string key;
  unsigned long long timestamp = 0;
  while (input >> key >> timestamp) {
    if (timestamp > 0 && now >= static_cast<std::time_t>(timestamp) &&
        now - static_cast<std::time_t>(timestamp) <= 180) {
      return true;
    }
  }
  return false;
}

static Fields WireGuardStatus() {
  const bool interface_present = InterfacePresent();
  const bool ipv4_route = interface_present && RoutesUseInterface("-4");
  const bool ipv6_route = interface_present && RoutesUseInterface("-6");
  const bool handshake = interface_present && HandshakePresent();
  Fields fields;
  fields["status"] = interface_present && (ipv4_route || ipv6_route) && handshake
                          ? "connected"
                          : "disconnected";
  fields["interface"] = kInterface;
  fields["interface_present"] = interface_present ? "true" : "false";
  fields["ipv4_route_via_sw_wg"] = ipv4_route ? "true" : "false";
  fields["ipv6_route_via_sw_wg"] = ipv6_route ? "true" : "false";
  fields["handshake_present"] = handshake ? "true" : "false";
  fields["counters_available"] =
      RunTool("wg", {"show", kInterface, "transfer"}).ok ? "true" : "false";
  return Ok(fields);
}

static bool CleanRuntime() {
  return !InterfacePresent();
}

static Fields HandleWireGuard(const std::string& op,
                              const Fields& request,
                              uid_t peer_uid) {
  Fields contract_error;
  if (!ContractInstalled(&contract_error)) {
    return contract_error;
  }
  if (op == "wireguard.status") {
    return WireGuardStatus();
  }
  if (op == "wireguard.counters") {
    const CommandResult result = RunTool("wg", {"show", kInterface, "transfer"});
    if (!result.ok) {
      return Error(
          "counter_unavailable",
          result.message.empty() ? "WireGuard traffic counters are unavailable." : result.message);
    }
    return Ok({{"stdout", result.out}});
  }

  const std::string config_path = Field(request, "config_path");
  const bool allow_missing = op == "wireguard.down" || op == "wireguard.cleanup";
  if (!ValidateConfigPath(config_path, peer_uid, allow_missing)) {
    return Error("invalid_path", "WireGuard configuration path is not approved.");
  }

  if (op == "wireguard.up") {
    std::string contents;
    if (!ReadConfig(config_path, &contents) || !ValidConfigContents(contents)) {
      return Error("invalid_config", "WireGuard configuration is invalid or unsafe.");
    }
    const CommandResult result = RunHelper({"up", config_path});
    if (!result.ok) {
      RunHelper({"down", config_path});
      return Error(
          "vpn_connect_failed",
          result.message.empty() ? "WireGuard start failed." : result.message);
    }
    if (!InterfacePresent()) {
      RunHelper({"down", config_path});
      return Error("vpn_connect_failed", "WireGuard interface was not created.");
    }
    for (guint attempt = 0; attempt < 40; attempt++) {
      const Fields status = WireGuardStatus();
      if (Field(status, "status") == "connected") {
        return status;
      }
      g_usleep(250000);
    }
    RunHelper({"down", config_path});
    return Error(
        "vpn_connect_failed",
        "WireGuard started but no recent authenticated handshake was observed.");
  }

  if (op == "wireguard.down" || op == "wireguard.cleanup") {
    const CommandResult result = config_path.empty()
        ? CommandResult{}
        : RunHelper({"down", config_path});
    if (!result.ok && InterfacePresent()) {
      return Error(
          "vpn_disconnect_failed",
          result.message.empty() ? "WireGuard stop failed." : result.message);
    }
    if (!CleanRuntime()) {
      return Error("vpn_disconnect_failed", "WireGuard interface cleanup could not be verified.");
    }
    return WireGuardStatus();
  }
  return Error("invalid_operation", "Unsupported WireGuard operation.");
}

static Fields HandleProbe() {
  Fields contract_error;
  if (!ContractInstalled(&contract_error)) {
    return contract_error;
  }
  const CommandResult script = RunHelper({"probe", "wireguard"});
  if (!script.ok) {
    return Error(
        "tool_missing",
        script.message.empty() ? "Required WireGuard tools are unavailable." : script.message);
  }
  Fields fields;
  fields["service_version"] = "1.0.0";
  fields["wireguard"] = "true";
  return Ok(fields);
}

static Fields HandleRequest(const Fields& request, uid_t peer_uid) {
  if (Field(request, "version") != "1") {
    return Error("invalid_request", "Unsupported helper request version.");
  }
  const std::string op = Field(request, "op");
  if (op.empty()) {
    return Error("invalid_request", "Missing helper operation.");
  }
  if (op == "probe") {
    if (!RequestFieldsAllowed(request, {"version", "op"})) {
      return Error("invalid_request", "Unexpected helper request field.");
    }
    return HandleProbe();
  }
  if (StartsWith(op, "wireguard.")) {
    if (!RequestFieldsAllowed(request, {"version", "op", "config_path"})) {
      return Error("invalid_request", "Unexpected helper request field.");
    }
    return HandleWireGuard(op, request, peer_uid);
  }
  return Error("invalid_operation", "Unsupported helper operation.");
}

static int CreateSocket() {
  if (g_mkdir_with_parents(kRuntimeDir, 0750) != 0) {
    return -1;
  }
  const struct group* group = getgrnam(kGroupName);
  if (group != nullptr) {
    chown(kRuntimeDir, 0, group->gr_gid);
    chmod(kRuntimeDir, 0750);
  }
  const int fd = socket(AF_UNIX, SOCK_STREAM, 0);
  if (fd < 0) {
    return -1;
  }
  unlink(kSocketPath);
  sockaddr_un address {};
  address.sun_family = AF_UNIX;
  g_strlcpy(address.sun_path, kSocketPath, sizeof(address.sun_path));
  if (bind(fd, reinterpret_cast<sockaddr*>(&address), sizeof(address)) != 0 ||
      listen(fd, 16) != 0) {
    close(fd);
    unlink(kSocketPath);
    return -1;
  }
  if (group != nullptr) {
    chown(kSocketPath, 0, group->gr_gid);
    chmod(kSocketPath, 0660);
  } else {
    chmod(kSocketPath, 0600);
  }
  return fd;
}

static void HandleClient(int client_fd) {
  Fields response;
  PeerCredentials peer;
  if (!PeerCredentialsForFd(client_fd, &peer) || !AuthorizedPeer(peer)) {
    response = Error("unauthorized", "Current user is not authorized for SecureWave WireGuard.");
  } else {
    std::string body;
    if (!ReadAll(client_fd, &body, kMaxRequestBytes)) {
      response = Error("invalid_request", "Helper request was too large or unreadable.");
    } else {
      const ParsedFields parsed = ParseFields(body);
      response = parsed.valid
          ? HandleRequest(parsed.fields, peer.uid)
          : Error("invalid_request", parsed.error);
    }
  }
  WriteAll(client_fd, SerializeFields(response));
}

static int SendRequestToRunningHelper() {
  std::string request;
  if (!ReadAll(STDIN_FILENO, &request, kMaxRequestBytes)) {
    g_printerr("securewave-helperd request input was unreadable.\n");
    return 2;
  }
  const int fd = socket(AF_UNIX, SOCK_STREAM, 0);
  if (fd < 0) {
    g_printerr("securewave-helperd request socket failed: %s\n", g_strerror(errno));
    return 2;
  }
  sockaddr_un address {};
  address.sun_family = AF_UNIX;
  g_strlcpy(address.sun_path, kSocketPath, sizeof(address.sun_path));
  if (connect(fd, reinterpret_cast<sockaddr*>(&address), sizeof(address)) != 0 ||
      !WriteAll(fd, request) || shutdown(fd, SHUT_WR) != 0) {
    g_printerr("securewave-helperd request connection failed: %s\n", g_strerror(errno));
    close(fd);
    return 2;
  }
  std::string response;
  const bool read_ok = ReadAll(fd, &response, kMaxRequestBytes);
  close(fd);
  if (!read_ok || !WriteAll(STDOUT_FILENO, response)) {
    g_printerr("securewave-helperd response was unreadable.\n");
    return 2;
  }
  const ParsedFields parsed = ParseFields(response);
  return parsed.valid && Field(parsed.fields, "ok") == "true" ? 0 : 1;
}

}  // namespace

int main(int argc, char** argv) {
  if (geteuid() != 0) {
    g_printerr("securewave-helperd must run as root.\n");
    return 1;
  }
  signal(SIGPIPE, SIG_IGN);
  if (argc == 2 && strcmp(argv[1], "--request") == 0) {
    return SendRequestToRunningHelper();
  }
  if (argc != 1) {
    g_printerr("Usage: securewave-helperd [--request]\n");
    return 2;
  }
  const int server_fd = CreateSocket();
  if (server_fd < 0) {
    g_printerr("securewave-helperd failed to bind %s: %s\n", kSocketPath, g_strerror(errno));
    return 1;
  }
  while (true) {
    const int client_fd = accept(server_fd, nullptr, nullptr);
    if (client_fd < 0 && errno == EINTR) {
      continue;
    }
    if (client_fd < 0) {
      g_usleep(100000);
      continue;
    }
    const struct timeval timeout = {5, 0};
    setsockopt(client_fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    setsockopt(client_fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
    HandleClient(client_fd);
    close(client_fd);
  }
}
