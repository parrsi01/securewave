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
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <map>
#include <sstream>
#include <string>
#include <vector>

// g_spawn_check_exit_status was renamed to g_spawn_check_wait_status in
// glib 2.70. Keep the runner build working on older distro toolchains.
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
const char* kWireGuardInterface = "sw-wg";
const guint kContractVersion = 13;
const gsize kMaxRequestBytes = 64 * 1024;

using Fields = std::map<std::string, std::string>;

struct CommandResult {
  bool spawned = false;
  bool ok = false;
  int wait_status = 0;
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
  const auto begin = std::find_if_not(
      value.begin(), value.end(), [](unsigned char c) {
        return g_ascii_isspace(c);
      });
  const auto end = std::find_if_not(
      value.rbegin(), value.rend(), [](unsigned char c) {
        return g_ascii_isspace(c);
      }).base();
  if (begin >= end) {
    return "";
  }
  return std::string(begin, end);
}

static bool StartsWith(const std::string& value, const std::string& prefix) {
  return value.compare(0, prefix.size(), prefix) == 0;
}

static std::string Field(const Fields& fields, const std::string& key) {
  const auto it = fields.find(key);
  return it == fields.end() ? "" : it->second;
}

static std::string CleanMessage(const std::string& value) {
  std::string clean = Trim(value);
  for (char& c : clean) {
    if (c == '\n' || c == '\r' || c == '\t') {
      c = ' ';
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

static std::string UnescapeValue(const std::string& value) {
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

static bool ValidFieldName(const std::string& key) {
  if (key.empty() || key.size() > 64) {
    return false;
  }
  return std::all_of(key.begin(), key.end(), [](unsigned char c) {
    return g_ascii_islower(c) || g_ascii_isdigit(c) || c == '_';
  });
}

static ParsedFields ParseFields(const std::string& body) {
  ParsedFields parsed;
  std::istringstream stream(body);
  std::string line;
  while (std::getline(stream, line)) {
    if (!line.empty() && line.back() == '\r') {
      line.pop_back();
    }
    if (line.empty()) {
      continue;
    }
    const std::string::size_type eq = line.find('=');
    if (eq == std::string::npos || eq == 0) {
      parsed.valid = false;
      parsed.error = "Malformed helper request field.";
      return parsed;
    }
    const std::string key = line.substr(0, eq);
    if (!ValidFieldName(key) ||
        parsed.fields.find(key) != parsed.fields.end()) {
      parsed.valid = false;
      parsed.error = "Invalid or duplicate helper request field.";
      return parsed;
    }
    parsed.fields[key] = UnescapeValue(line.substr(eq + 1));
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

static Fields Ok(Fields fields = Fields()) {
  fields["ok"] = "true";
  fields["code"] = "ok";
  fields["message"] =
      Field(fields, "message").empty() ? "OK" : Field(fields, "message");
  fields["service_version"] = "1";
  fields["contract"] = std::to_string(kContractVersion);
  return fields;
}

static Fields Error(const std::string& code,
                    const std::string& message,
                    Fields fields = Fields()) {
  fields["ok"] = "false";
  fields["code"] = code;
  fields["message"] = CleanMessage(message);
  fields["service_version"] = "1";
  fields["contract"] = std::to_string(kContractVersion);
  return fields;
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

static bool ReadAll(int fd, std::string* out) {
  out->clear();
  char buffer[4096];
  while (true) {
    const ssize_t count = read(fd, buffer, sizeof(buffer));
    if (count < 0 && errno == EINTR) {
      continue;
    }
    if (count < 0) {
      return false;
    }
    if (count == 0) {
      return true;
    }
    if (out->size() + static_cast<size_t>(count) > kMaxRequestBytes) {
      return false;
    }
    out->append(buffer, static_cast<size_t>(count));
  }
}

static bool ParseUint32Strict(const std::string& raw, guint32* value) {
  const std::string input = Trim(raw);
  if (!value || input.empty() || input[0] == '+' || input[0] == '-') {
    return false;
  }
  char* end = nullptr;
  errno = 0;
  const unsigned long long parsed = strtoull(input.c_str(), &end, 10);
  if (errno != 0 || end == input.c_str() || *end != '\0' ||
      parsed == 0 || parsed > UINT32_MAX) {
    return false;
  }
  *value = static_cast<guint32>(parsed);
  return true;
}

static guint InstalledContractVersion() {
  std::ifstream input(kContractPath);
  std::string contents;
  std::getline(input, contents);
  guint32 installed = 0;
  if (!ParseUint32Strict(contents, &installed)) {
    return 0;
  }
  return installed;
}

static Fields RequireContract() {
  struct stat st {};
  if (stat(kHelperPath, &st) != 0 ||
      !S_ISREG(st.st_mode) ||
      access(kHelperPath, X_OK) != 0) {
    return Error("helper_missing", "SecureWave WireGuard helper is missing.");
  }
  const guint installed = InstalledContractVersion();
  if (installed < kContractVersion) {
    Fields fields;
    fields["installed_contract"] = std::to_string(installed);
    fields["required_contract"] = std::to_string(kContractVersion);
    return Error("helper_incompatible",
                 "SecureWave WireGuard helper is out of date.",
                 fields);
  }
  return Ok();
}

static bool ContractOk(Fields* error) {
  Fields result = RequireContract();
  if (Field(result, "ok") == "true") {
    return true;
  }
  if (error) {
    *error = result;
  }
  return false;
}

static const char* AllowlistedExecutablePath(const std::string& executable) {
  if (executable == kHelperPath ||
      executable == "securewave-wg-quick") {
    return kHelperPath;
  }
  return nullptr;
}

static CommandResult RunCommand(const std::vector<std::string>& args) {
  CommandResult result;
  if (args.empty()) {
    result.message = "Empty command refused.";
    return result;
  }

  const char* executable = AllowlistedExecutablePath(args.front());
  if (executable == nullptr) {
    result.message = "Command executable is not allowlisted.";
    return result;
  }

  std::vector<std::string> canonical_args = args;
  canonical_args.front() = executable;
  for (const std::string& arg : canonical_args) {
    if (arg.find('\0') != std::string::npos ||
        arg.find('\n') != std::string::npos ||
        arg.find('\r') != std::string::npos) {
      result.message = "Command argument contains a forbidden control character.";
      return result;
    }
  }

  GPtrArray* argv_array = g_ptr_array_new_with_free_func(g_free);
  for (const std::string& arg : canonical_args) {
    g_ptr_array_add(argv_array, g_strdup(arg.c_str()));
  }
  g_ptr_array_add(argv_array, nullptr);

  gint wait_status = 0;
  GError* error = nullptr;
  gchar* stdout_text = nullptr;
  gchar* stderr_text = nullptr;
  const gboolean spawned = g_spawn_sync(
      nullptr,
      reinterpret_cast<gchar**>(argv_array->pdata),
      nullptr,
      G_SPAWN_DEFAULT,
      nullptr,
      nullptr,
      &stdout_text,
      &stderr_text,
      &wait_status,
      &error);
  g_ptr_array_free(argv_array, TRUE);

  result.spawned = spawned;
  result.wait_status = wait_status;
  result.out = stdout_text ? stdout_text : "";
  result.err = stderr_text ? stderr_text : "";
  if (!spawned) {
    result.message = error ? error->message : "Command failed to start.";
  } else {
    result.ok = g_spawn_check_wait_status(wait_status, nullptr);
    if (!result.ok) {
      result.message = !Trim(result.err).empty()
                           ? Trim(result.err)
                           : (!Trim(result.out).empty()
                                  ? Trim(result.out)
                                  : "Command exited with an error.");
    }
  }
  g_clear_error(&error);
  g_free(stdout_text);
  g_free(stderr_text);
  return result;
}

static CommandResult RunHelper(const std::vector<std::string>& helper_args) {
  std::vector<std::string> argv;
  argv.emplace_back(kHelperPath);
  argv.insert(argv.end(), helper_args.begin(), helper_args.end());
  return RunCommand(argv);
}

static bool HasUnsafePathComponent(const std::string& path) {
  if (path.empty() || path[0] != '/' || path.size() > 4096) {
    return true;
  }
  if (path.find('\n') != std::string::npos ||
      path.find('\r') != std::string::npos ||
      path.find('\0') != std::string::npos) {
    return true;
  }
  std::istringstream stream(path);
  std::string part;
  while (std::getline(stream, part, '/')) {
    if (part == "..") {
      return true;
    }
  }
  return false;
}

static std::string Basename(const std::string& path) {
  const std::string::size_type slash = path.find_last_of('/');
  return slash == std::string::npos ? path : path.substr(slash + 1);
}

static std::string PeerHome(uid_t peer_uid) {
  const struct passwd* pwd = getpwuid(peer_uid);
  if (!pwd || !pwd->pw_dir || pwd->pw_dir[0] != '/') {
    return "";
  }
  return pwd->pw_dir;
}

static bool IsApprovedConfigPath(const std::string& path, uid_t peer_uid) {
  if (HasUnsafePathComponent(path) || Basename(path) != "sw-wg.conf") {
    return false;
  }
  if (StartsWith(path, "/run/securewave/")) {
    return true;
  }
  const std::string home = peer_uid == 0 ? "/root" : PeerHome(peer_uid);
  return !home.empty() &&
         !HasUnsafePathComponent(home) &&
         StartsWith(path, home + "/.config/securewave/");
}

static bool ExistingConfigFileSafe(const std::string& path, uid_t peer_uid) {
  struct stat st {};
  if (lstat(path.c_str(), &st) != 0 ||
      S_ISLNK(st.st_mode) ||
      !S_ISREG(st.st_mode)) {
    return false;
  }
  if (st.st_uid != peer_uid && st.st_uid != 0) {
    return false;
  }
  return (st.st_mode & (S_IWGRP | S_IWOTH)) == 0;
}

static bool ParseUid(const std::string& raw, uid_t* uid) {
  const std::string trimmed = Trim(raw);
  if (trimmed.empty() || trimmed[0] == '#') {
    return false;
  }
  char* end = nullptr;
  errno = 0;
  const unsigned long parsed = strtoul(trimmed.c_str(), &end, 10);
  if (errno != 0 || end == trimmed.c_str()) {
    return false;
  }
  while (*end != '\0' && g_ascii_isspace(*end)) {
    end++;
  }
  if (*end != '\0' && *end != '#') {
    return false;
  }
  *uid = static_cast<uid_t>(parsed);
  return true;
}

static bool UidAllowedByFile(uid_t uid) {
  std::ifstream input(kAllowedUsersPath);
  std::string line;
  while (std::getline(input, line)) {
    uid_t allowed = 0;
    if (ParseUid(line, &allowed) && allowed == uid) {
      return true;
    }
  }
  return false;
}

static bool PeerAllowed(const PeerCredentials& peer) {
  return peer.valid && (peer.uid == 0 || UidAllowedByFile(peer.uid));
}

static PeerCredentials GetPeerCredentials(int fd) {
  PeerCredentials peer;
#ifdef SO_PEERCRED
  struct ucred cred {};
  socklen_t length = sizeof(cred);
  if (getsockopt(fd, SOL_SOCKET, SO_PEERCRED, &cred, &length) == 0) {
    peer.uid = cred.uid;
    peer.gid = cred.gid;
    peer.pid = cred.pid;
    peer.valid = true;
  }
#endif
  return peer;
}

static guint64 ReadSysUint64(const std::string& path, bool* ok) {
  std::ifstream input(path);
  std::string contents;
  std::getline(input, contents);
  const std::string trimmed = Trim(contents);
  if (trimmed.empty() || trimmed[0] == '+' || trimmed[0] == '-') {
    *ok = false;
    return 0;
  }
  char* end = nullptr;
  errno = 0;
  const unsigned long long parsed = strtoull(trimmed.c_str(), &end, 10);
  if (errno != 0 || end == trimmed.c_str() || *end != '\0') {
    *ok = false;
    return 0;
  }
  *ok = true;
  return static_cast<guint64>(parsed);
}

static Fields HandleRequest(const Fields& request,
                            const PeerCredentials& peer) {
  if (Field(request, "version") != "1") {
    return Error("invalid_version", "Unsupported SecureWave helper request.");
  }

  const std::string op = Field(request, "op");
  if (op.empty()) {
    return Error("missing_operation", "SecureWave helper operation is missing.");
  }

  if (!PeerAllowed(peer)) {
    return Error("unauthorized",
                 "Current user is not authorized for the SecureWave helper.");
  }

  if (op == "probe") {
    if (Field(request, "protocol") != "wireguard") {
      return Error("protocol_unavailable",
                   "SecureWave is WireGuard-only in this build.");
    }
    Fields contract_error;
    if (!ContractOk(&contract_error)) {
      return contract_error;
    }
    const CommandResult probe = RunHelper({"probe", "wireguard"});
    if (!probe.ok) {
      return Error("wireguard_unavailable",
                   probe.message.empty()
                       ? "WireGuard tools are not installed."
                       : probe.message);
    }
    Fields fields;
    fields["installed_contract"] = std::to_string(InstalledContractVersion());
    fields["required_contract"] = std::to_string(kContractVersion);
    fields["wireguard_ready"] = "true";
    return Ok(fields);
  }

  Fields contract_error;
  if (!ContractOk(&contract_error)) {
    return contract_error;
  }

  if (op == "wireguard.status") {
    const std::string interface_dir =
        std::string("/sys/class/net/") + kWireGuardInterface;
    const bool connected =
        g_file_test(interface_dir.c_str(), G_FILE_TEST_IS_DIR);
    bool rx_ok = false;
    bool tx_ok = false;
    const guint64 rx = ReadSysUint64(
        interface_dir + "/statistics/rx_bytes", &rx_ok);
    const guint64 tx = ReadSysUint64(
        interface_dir + "/statistics/tx_bytes", &tx_ok);
    Fields fields;
    fields["status"] = connected ? "connected" : "disconnected";
    fields["interface"] = kWireGuardInterface;
    fields["rx_bytes"] = std::to_string(rx_ok ? rx : 0);
    fields["tx_bytes"] = std::to_string(tx_ok ? tx : 0);
    fields["counters_available"] =
        connected && rx_ok && tx_ok ? "true" : "false";
    return Ok(fields);
  }

  if (op == "wireguard.counters") {
    const CommandResult counters = RunHelper({"wireguard-transfer"});
    if (!counters.ok) {
      return Error("counters_unavailable",
                   counters.message.empty()
                       ? "WireGuard transfer counters are unavailable."
                       : counters.message);
    }
    Fields fields;
    fields["stdout"] = counters.out;
    return Ok(fields);
  }

  if (op == "wireguard.up" || op == "wireguard.down") {
    const std::string config_path = Field(request, "config_path");
    if (!IsApprovedConfigPath(config_path, peer.uid)) {
      return Error("invalid_path",
                   "WireGuard config path is not approved.");
    }
    if (op == "wireguard.up" &&
        !ExistingConfigFileSafe(config_path, peer.uid)) {
      return Error("invalid_path",
                   "WireGuard config file is missing or unsafe.");
    }
    const CommandResult result =
        RunHelper({op == "wireguard.up" ? "up" : "down", config_path});
    if (!result.ok) {
      return Error(op == "wireguard.up"
                       ? "vpn_connect_failed"
                       : "vpn_disconnect_failed",
                   result.message.empty()
                       ? "WireGuard helper operation failed."
                       : result.message);
    }
    return Ok();
  }

  return Error("invalid_operation",
               "Unsupported SecureWave WireGuard helper operation.");
}

static Fields HandleRequestBody(const std::string& body,
                                const PeerCredentials& peer) {
  const ParsedFields parsed = ParseFields(body);
  if (!parsed.valid) {
    return Error("invalid_request", parsed.error);
  }
  return HandleRequest(parsed.fields, peer);
}

static gid_t RuntimeGroupGid() {
  const struct group* group = getgrnam(kGroupName);
  return group ? group->gr_gid : getegid();
}

static int BindServerSocket() {
  if (g_mkdir_with_parents(kRuntimeDir, 0750) != 0) {
    return -1;
  }
  const gid_t runtime_gid = RuntimeGroupGid();
  chown(kRuntimeDir, 0, runtime_gid);
  chmod(kRuntimeDir, 0750);
  unlink(kSocketPath);

  const int fd = socket(AF_UNIX, SOCK_STREAM, 0);
  if (fd < 0) {
    return -1;
  }

  sockaddr_un address {};
  address.sun_family = AF_UNIX;
  g_strlcpy(address.sun_path, kSocketPath, sizeof(address.sun_path));
  if (bind(fd, reinterpret_cast<sockaddr*>(&address), sizeof(address)) != 0) {
    close(fd);
    return -1;
  }
  chown(kSocketPath, 0, runtime_gid);
  chmod(kSocketPath, 0660);

  if (listen(fd, 16) != 0) {
    close(fd);
    unlink(kSocketPath);
    return -1;
  }
  return fd;
}

static void ServeClient(int client_fd) {
  const PeerCredentials peer = GetPeerCredentials(client_fd);
  std::string request_body;
  Fields response;
  if (!ReadAll(client_fd, &request_body)) {
    response = Error("request_unreadable",
                     "SecureWave helper request was unreadable.");
  } else {
    response = HandleRequestBody(request_body, peer);
  }
  const std::string response_body = SerializeFields(response);
  WriteAll(client_fd, response_body);
  close(client_fd);
}

}  // namespace

int main(int argc, char** argv) {
  signal(SIGPIPE, SIG_IGN);

  if (argc == 2 && std::string(argv[1]) == "--request") {
    std::string body;
    if (!ReadAll(STDIN_FILENO, &body)) {
      g_printerr("securewave-helperd request input was unreadable.\n");
      return 1;
    }
    PeerCredentials root_peer;
    root_peer.uid = geteuid();
    root_peer.gid = getegid();
    root_peer.pid = getpid();
    root_peer.valid = true;
    const std::string response =
        SerializeFields(HandleRequestBody(body, root_peer));
    if (!WriteAll(STDOUT_FILENO, response)) {
      g_printerr("securewave-helperd response output failed.\n");
      return 1;
    }
    const ParsedFields parsed = ParseFields(response);
    return parsed.valid && Field(parsed.fields, "ok") == "true" ? 0 : 1;
  }

  if (argc != 1) {
    g_printerr("Usage: securewave-helperd [--request]\n");
    return 64;
  }

  if (geteuid() != 0) {
    g_printerr("securewave-helperd must run as root.\n");
    return 1;
  }

  const int server_fd = BindServerSocket();
  if (server_fd < 0) {
    g_printerr("securewave-helperd failed to bind %s: %s\n",
               kSocketPath,
               g_strerror(errno));
    return 1;
  }

  while (true) {
    const int client_fd = accept(server_fd, nullptr, nullptr);
    if (client_fd < 0) {
      if (errno == EINTR) {
        continue;
      }
      g_printerr("securewave-helperd accept failed: %s\n", g_strerror(errno));
      close(server_fd);
      unlink(kSocketPath);
      return 1;
    }
    ServeClient(client_fd);
  }
}
