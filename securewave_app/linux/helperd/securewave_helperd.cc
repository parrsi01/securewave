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
#include <cstdlib>
#include <cstdint>
#include <cstring>
#include <fstream>
#include <map>
#include <set>
#include <sstream>
#include <string>
#include <vector>

// g_spawn_check_exit_status was renamed to g_spawn_check_wait_status in
// glib 2.70. Provide the same compatibility shim as the Flutter runner.
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
const char* kOpenVpnPidName = "securewave-openvpn.pid";
const char* kOpenVpnLogName = "securewave-openvpn.log";
const char* kOpenVpnAuthName = "securewave-openvpn.auth";
const char* kIkev2ConfigName = "securewave-ikev2.conf";
const char* kIkev2CaName = "securewave-ikev2-ca.pem";
const char* kIkev2ConnectionName = "SecureWave-IKEv2";
const guint kContractVersion = 9;
const gsize kMaxRequestBytes = 1024 * 1024;

struct CommandResult {
  bool spawned = false;
  bool ok = false;
  int wait_status = 0;
  std::string out;
  std::string err;
  std::string message;
};

using Fields = std::map<std::string, std::string>;

struct PeerCredentials {
  uid_t uid = 0;
  gid_t gid = 0;
  pid_t pid = 0;
  bool valid = false;
};

static std::string Trim(const std::string& value) {
  const auto begin = std::find_if_not(value.begin(), value.end(), [](unsigned char c) {
    return g_ascii_isspace(c);
  });
  const auto end = std::find_if_not(value.rbegin(), value.rend(), [](unsigned char c) {
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

static std::vector<uid_t> ReadAllowedUids() {
  std::vector<uid_t> uids;
  std::ifstream input(kAllowedUsersPath);
  std::string line;
  while (std::getline(input, line)) {
    uid_t uid = 0;
    if (ParseUid(line, &uid)) {
      uids.push_back(uid);
    }
  }
  return uids;
}

static bool UidAllowedByFile(uid_t uid) {
  for (const uid_t allowed : ReadAllowedUids()) {
    if (allowed == uid) {
      return true;
    }
  }
  return false;
}

static std::string Basename(const std::string& path) {
  const std::string::size_type slash = path.find_last_of('/');
  return slash == std::string::npos ? path : path.substr(slash + 1);
}

static std::string Dirname(const std::string& path) {
  const std::string::size_type slash = path.find_last_of('/');
  if (slash == std::string::npos || slash == 0) {
    return slash == 0 ? "/" : ".";
  }
  return path.substr(0, slash);
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

static Fields ParseFields(const std::string& body) {
  Fields fields;
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
    if (eq == std::string::npos) {
      continue;
    }
    fields[line.substr(0, eq)] = UnescapeValue(line.substr(eq + 1));
  }
  return fields;
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
  fields["message"] = Field(fields, "message").empty() ? "OK" : Field(fields, "message");
  fields["service_version"] = "1";
  fields["contract"] = std::to_string(kContractVersion);
  return fields;
}

static Fields Error(const std::string& code, const std::string& message, Fields fields = Fields()) {
  fields["ok"] = "false";
  fields["code"] = code;
  fields["message"] = CleanMessage(message);
  fields["service_version"] = "1";
  fields["contract"] = std::to_string(kContractVersion);
  return fields;
}

static CommandResult RunCommand(const std::vector<std::string>& args) {
  CommandResult result;
  if (args.empty()) {
    result.message = "Empty command refused.";
    return result;
  }

  GPtrArray* argv_array = g_ptr_array_new_with_free_func(g_free);
  for (const std::string& arg : args) {
    g_ptr_array_add(argv_array, g_strdup(arg.c_str()));
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

  result.spawned = spawned;
  result.wait_status = wait_status;
  result.out = stdout_text ? stdout_text : "";
  result.err = stderr_text ? stderr_text : "";
  if (!spawned) {
    result.message = error ? error->message : "Command failed to start.";
    return result;
  }
  result.ok = g_spawn_check_wait_status(wait_status, nullptr);
  if (!result.ok) {
    result.message = !Trim(result.err).empty()
                         ? Trim(result.err)
                         : (!Trim(result.out).empty() ? Trim(result.out) : "Command exited with an error.");
  }
  return result;
}

static guint InstalledContractVersion() {
  std::ifstream input(kContractPath);
  std::string contents;
  std::getline(input, contents);
  if (contents.empty()) {
    return 0;
  }
  return static_cast<guint>(g_ascii_strtoull(Trim(contents).c_str(), nullptr, 10));
}

static Fields RequireContract() {
  struct stat st {};
  if (stat(kHelperPath, &st) != 0 || !S_ISREG(st.st_mode) || access(kHelperPath, X_OK) != 0) {
    return Error("helper_missing", "SecureWave VPN helper executable is missing.");
  }
  const guint installed = InstalledContractVersion();
  if (installed < kContractVersion) {
    Fields fields;
    fields["installed_contract"] = std::to_string(installed);
    fields["required_contract"] = std::to_string(kContractVersion);
    return Error("helper_incompatible", "SecureWave VPN helper is out of date.", fields);
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

static CommandResult RunHelper(const std::vector<std::string>& helper_args) {
  std::vector<std::string> argv;
  argv.emplace_back(kHelperPath);
  argv.insert(argv.end(), helper_args.begin(), helper_args.end());
  return RunCommand(argv);
}

static void ApplyAllowedUserAcls() {
  for (const uid_t uid : ReadAllowedUids()) {
    const std::string entry_prefix = std::string("u:") + std::to_string(static_cast<unsigned long>(uid));
    RunCommand({"setfacl", "-m", entry_prefix + ":rx", kRuntimeDir});
    RunCommand({"setfacl", "-m", entry_prefix + ":rw", kSocketPath});
  }
}

static bool HasUnsafePathComponent(const std::string& path) {
  if (path.empty() || path[0] != '/' || path.size() > 4096) {
    return true;
  }
  if (path.find('\n') != std::string::npos || path.find('\r') != std::string::npos ||
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

static std::string PeerHome(uid_t peer_uid) {
  const struct passwd* pwd = getpwuid(peer_uid);
  if (!pwd || !pwd->pw_dir || pwd->pw_dir[0] != '/') {
    return "";
  }
  return pwd->pw_dir;
}

static bool IsApprovedRuntimePath(const std::string& path, uid_t peer_uid) {
  if (HasUnsafePathComponent(path)) {
    return false;
  }
  if (StartsWith(path, "/run/securewave/")) {
    return true;
  }
  const std::string home = peer_uid == 0 ? "/root" : PeerHome(peer_uid);
  if (home.empty() || HasUnsafePathComponent(home)) {
    return false;
  }
  return StartsWith(path, home + "/.config/securewave/");
}

static bool PathOwnerAllowed(const std::string& path, const struct stat& st, uid_t peer_uid) {
  if (peer_uid == 0) {
    return true;
  }
  if (StartsWith(path, "/run/securewave/")) {
    return st.st_uid == 0;
  }
  return st.st_uid == peer_uid;
}

static bool IsExistingRegularFile(const std::string& path, uid_t peer_uid) {
  struct stat st {};
  if (lstat(path.c_str(), &st) != 0) {
    return false;
  }
  return S_ISREG(st.st_mode) &&
         !S_ISLNK(st.st_mode) &&
         PathOwnerAllowed(path, st, peer_uid) &&
         (st.st_mode & (S_IWGRP | S_IWOTH)) == 0;
}

static bool ValidateConfigPath(const std::string& path, const std::string& expected_name, uid_t peer_uid) {
  return IsApprovedRuntimePath(path, peer_uid) &&
         Basename(path) == expected_name &&
         IsExistingRegularFile(path, peer_uid);
}

static bool ValidateRuntimeFilePath(const std::string& path, const std::string& expected_name, uid_t peer_uid) {
  if (!IsApprovedRuntimePath(path, peer_uid) || Basename(path) != expected_name) {
    return false;
  }
  struct stat parent {};
  if (stat(Dirname(path).c_str(), &parent) != 0 || !S_ISDIR(parent.st_mode)) {
    return false;
  }
  if (!PathOwnerAllowed(Dirname(path), parent, peer_uid)) {
    return false;
  }
  struct stat st {};
  if (lstat(path.c_str(), &st) == 0 && S_ISLNK(st.st_mode)) {
    return false;
  }
  if (lstat(path.c_str(), &st) == 0 &&
      (!S_ISREG(st.st_mode) ||
       !PathOwnerAllowed(path, st, peer_uid) ||
       (st.st_mode & (S_IWGRP | S_IWOTH)) != 0)) {
    return false;
  }
  return true;
}

static bool ValidateProtocol(const std::string& protocol) {
  return protocol == "wireguard" || protocol == "openvpn" || protocol == "ikev2";
}

static bool ProcessRunning(pid_t pid) {
  if (pid <= 0) {
    return false;
  }
  if (kill(pid, 0) == 0) {
    return true;
  }
  return errno == EPERM;
}

static bool ProcessLooksLikeOpenVpn(pid_t pid) {
  if (pid <= 0) {
    return false;
  }
  std::ifstream comm(std::string("/proc/") + std::to_string(static_cast<long>(pid)) + "/comm");
  std::string name;
  std::getline(comm, name);
  name = Trim(name);
  if (name == "openvpn") {
    return true;
  }

  std::ifstream cmdline(
      std::string("/proc/") + std::to_string(static_cast<long>(pid)) + "/cmdline",
      std::ios::binary);
  std::string raw((std::istreambuf_iterator<char>(cmdline)), std::istreambuf_iterator<char>());
  for (char& c : raw) {
    if (c == '\0') {
      c = ' ';
    }
  }
  return raw.find("openvpn") != std::string::npos;
}

static bool ReadPid(const std::string& path, pid_t* pid) {
  std::ifstream input(path);
  std::string contents;
  std::getline(input, contents);
  contents = Trim(contents);
  if (contents.empty()) {
    return false;
  }
  char* end = nullptr;
  const long parsed = strtol(contents.c_str(), &end, 10);
  if (end == contents.c_str() || *end != '\0' || parsed <= 0) {
    return false;
  }
  *pid = static_cast<pid_t>(parsed);
  return true;
}

static bool CommandOk(const std::vector<std::string>& args) {
  return RunCommand(args).ok;
}

static bool WireGuardInterfaceExists() {
  return CommandOk({"ip", "link", "show", kWireGuardInterface});
}

static bool WireGuardRouteExists() {
  CommandResult result = RunCommand({"ip", "route", "get", "1.1.1.1"});
  return result.ok && result.out.find(" dev sw-wg") != std::string::npos;
}

static bool WireGuardPolicyRulesExist() {
  CommandResult result = RunCommand({"ip", "rule", "show"});
  if (!result.ok) {
    return true;
  }
  return result.out.find("lookup 51820") != std::string::npos ||
         result.out.find("table 51820") != std::string::npos ||
         result.out.find("suppress_prefixlength 0") != std::string::npos;
}

static bool WireGuardPolicyRoutesExistForFamily(const std::string& family) {
  CommandResult result = RunCommand({"ip", family, "route", "show", "table", "51820"});
  if (!result.ok) {
    return result.err.find("FIB table does not exist") == std::string::npos &&
           result.out.find("FIB table does not exist") == std::string::npos;
  }
  return !Trim(result.out).empty();
}

static bool WireGuardPolicyRoutesExist() {
  return WireGuardPolicyRoutesExistForFamily("-4") ||
         WireGuardPolicyRoutesExistForFamily("-6");
}

static bool WireGuardResidueExists() {
  return WireGuardInterfaceExists() ||
         WireGuardRouteExists() ||
         WireGuardPolicyRulesExist() ||
         WireGuardPolicyRoutesExist();
}

static std::string WireGuardResidueSummary() {
  std::vector<std::string> parts;
  if (WireGuardInterfaceExists()) {
    parts.emplace_back("sw-wg interface present");
  }
  if (WireGuardRouteExists()) {
    parts.emplace_back("route to 1.1.1.1 uses sw-wg");
  }
  if (WireGuardPolicyRulesExist()) {
    parts.emplace_back("WireGuard policy rules present");
  }
  if (WireGuardPolicyRoutesExist()) {
    parts.emplace_back("WireGuard table 51820 routes present");
  }
  if (parts.empty()) {
    return "no WireGuard residue";
  }
  std::ostringstream summary;
  for (size_t i = 0; i < parts.size(); i++) {
    if (i > 0) {
      summary << "; ";
    }
    summary << parts[i];
  }
  return summary.str();
}

static bool WaitWireGuardClean() {
  for (guint i = 0; i < 20; i++) {
    if (!WireGuardResidueExists()) {
      return true;
    }
    g_usleep(250000);
  }
  return !WireGuardResidueExists();
}

static bool OpenVpnTunExists() {
  if (g_file_test("/sys/class/net/tun0", G_FILE_TEST_IS_DIR)) {
    return true;
  }
  g_autoptr(GDir) dir = g_dir_open("/sys/class/net", 0, nullptr);
  if (!dir) {
    return false;
  }
  const gchar* name = nullptr;
  while ((name = g_dir_read_name(dir)) != nullptr) {
    if (g_str_has_prefix(name, "tun")) {
      return true;
    }
  }
  return false;
}

static std::string OpenVpnInterfaceName() {
  if (g_file_test("/sys/class/net/tun0", G_FILE_TEST_IS_DIR)) {
    return "tun0";
  }
  g_autoptr(GDir) dir = g_dir_open("/sys/class/net", 0, nullptr);
  if (!dir) {
    return "tun0";
  }
  const gchar* name = nullptr;
  while ((name = g_dir_read_name(dir)) != nullptr) {
    if (g_str_has_prefix(name, "tun")) {
      return name;
    }
  }
  return "tun0";
}

static bool OpenVpnRouteExists() {
  CommandResult result = RunCommand({"ip", "route", "get", "1.1.1.1"});
  return result.ok && result.out.find(" dev tun") != std::string::npos;
}

static bool FileContains(const std::string& path, const std::string& needle) {
  std::ifstream input(path);
  std::ostringstream buffer;
  buffer << input.rdbuf();
  return buffer.str().find(needle) != std::string::npos;
}

static std::string UnquoteSwanctlValue(std::string value) {
  value = Trim(value);
  if (value.size() >= 2 && value.front() == '"' && value.back() == '"') {
    value = value.substr(1, value.size() - 2);
  }
  std::string out;
  out.reserve(value.size());
  bool escaped = false;
  for (char c : value) {
    if (escaped) {
      out += c;
      escaped = false;
      continue;
    }
    if (c == '\\') {
      escaped = true;
      continue;
    }
    out += c;
  }
  if (escaped) {
    out += '\\';
  }
  return out;
}

static std::string SwanctlValueForKey(const std::string& contents, const std::string& key) {
  std::istringstream stream(contents);
  std::string line;
  const std::string prefix = key + " =";
  while (std::getline(stream, line)) {
    line = Trim(line);
    if (!StartsWith(line, prefix)) {
      continue;
    }
    return UnquoteSwanctlValue(line.substr(prefix.size()));
  }
  return "";
}

static std::string ExtractCaPem(const std::string& contents) {
  const std::string begin = "# ca_cert_pem_begin";
  const std::string end = "# ca_cert_pem_end";
  const std::string::size_type begin_pos = contents.find(begin);
  if (begin_pos == std::string::npos) {
    return "";
  }
  const std::string::size_type data_start = contents.find('\n', begin_pos);
  if (data_start == std::string::npos) {
    return "";
  }
  const std::string::size_type end_pos = contents.find(end, data_start + 1);
  if (end_pos == std::string::npos) {
    return "";
  }
  return Trim(contents.substr(data_start + 1, end_pos - data_start - 1));
}

static bool WritePeerOwnedFile(const std::string& path,
                               const std::string& contents,
                               uid_t peer_uid,
                               std::string* message) {
  GError* error = nullptr;
  if (!g_file_set_contents(path.c_str(), contents.c_str(), contents.size(), &error)) {
    if (message) {
      *message = error ? error->message : "unable to write file";
    }
    if (error) {
      g_error_free(error);
    }
    return false;
  }
  if (error) {
    g_error_free(error);
  }
  chmod(path.c_str(), 0600);
  struct stat parent {};
  if (peer_uid != 0 && stat(Dirname(path).c_str(), &parent) == 0) {
    chown(path.c_str(), peer_uid, parent.st_gid);
  }
  return true;
}

static bool OpenVpnRuntimeEvidence(const std::string& pid_path, const std::string& log_path) {
  pid_t pid = 0;
  return ReadPid(pid_path, &pid) &&
         ProcessRunning(pid) &&
         ProcessLooksLikeOpenVpn(pid) &&
         FileContains(log_path, "Initialization Sequence Completed") &&
         OpenVpnTunExists() &&
         OpenVpnRouteExists();
}

static bool WaitOpenVpnStopped(const std::string& pid_path) {
  for (guint i = 0; i < 20; i++) {
    pid_t pid = 0;
    const bool openvpn_running =
        ReadPid(pid_path, &pid) && ProcessRunning(pid) && ProcessLooksLikeOpenVpn(pid);
    if (!openvpn_running && !OpenVpnRouteExists()) {
      return true;
    }
    g_usleep(500000);
  }
  pid_t pid = 0;
  const bool openvpn_running =
      ReadPid(pid_path, &pid) && ProcessRunning(pid) && ProcessLooksLikeOpenVpn(pid);
  return !openvpn_running && !OpenVpnRouteExists();
}

static bool NmcliActiveIkev2() {
  CommandResult result = RunCommand({"nmcli", "-t", "-f", "NAME,TYPE", "connection", "show", "--active"});
  if (!result.ok) {
    return false;
  }
  std::istringstream stream(result.out);
  std::string line;
  const std::string expected = std::string(kIkev2ConnectionName) + ":vpn";
  while (std::getline(stream, line)) {
    if (Trim(line) == expected) {
      return true;
    }
  }
  return false;
}

static bool Ikev2RouteOrDnsEvidence() {
  CommandResult result = RunCommand({
      "nmcli", "-t", "-f", "IP4.DNS,IP4.ROUTE,IP6.DNS,IP6.ROUTE",
      "connection", "show", kIkev2ConnectionName});
  if (!result.ok) {
    return false;
  }
  std::istringstream stream(result.out);
  std::string line;
  while (std::getline(stream, line)) {
    line = Trim(line);
    const std::string::size_type colon = line.find(':');
    if (colon == std::string::npos) {
      continue;
    }
    std::string value = Trim(line.substr(colon + 1));
    if (!value.empty() && value != "--") {
      return true;
    }
  }
  return false;
}

static bool XfrmHasEsp(const std::string& output) {
  return output.find("proto esp") != std::string::npos;
}

static CommandResult ReadXfrmState() {
  return RunCommand({"ip", "-s", "xfrm", "state"});
}

static CommandResult ReadIpRules() {
  return RunCommand({"ip", "rule", "show"});
}

static bool Ikev2HasUnqualifiedPref220Rule(const std::string& output) {
  std::istringstream stream(output);
  std::string line;
  while (std::getline(stream, line)) {
    line = Trim(line);
    if (line.rfind("220:", 0) != 0) {
      continue;
    }
    if (line.find("from all") != std::string::npos &&
        line.find("lookup 220") != std::string::npos &&
        line.find("fwmark") == std::string::npos) {
      return true;
    }
  }
  return false;
}

static bool Ikev2RuntimeEvidence(std::string* xfrm_output = nullptr,
                                 bool* routing_loop_rule_present = nullptr) {
  CommandResult xfrm = ReadXfrmState();
  if (xfrm_output) {
    *xfrm_output = xfrm.out;
  }
  CommandResult rules = ReadIpRules();
  const bool routing_loop_rule =
      rules.ok && Ikev2HasUnqualifiedPref220Rule(rules.out);
  if (routing_loop_rule_present) {
    *routing_loop_rule_present = routing_loop_rule;
  }
  return NmcliActiveIkev2() &&
         Ikev2RouteOrDnsEvidence() &&
         xfrm.ok &&
         XfrmHasEsp(xfrm.out) &&
         rules.ok &&
         !routing_loop_rule;
}

static bool WaitIkev2Stopped() {
  for (guint i = 0; i < 20; i++) {
    if (!NmcliActiveIkev2()) {
      return true;
    }
    g_usleep(500000);
  }
  return !NmcliActiveIkev2();
}

static std::set<std::string> LocalAddresses() {
  std::set<std::string> addresses;
  CommandResult result = RunCommand({"ip", "-o", "addr", "show"});
  if (!result.ok) {
    return addresses;
  }
  std::istringstream lines(result.out);
  std::string line;
  while (std::getline(lines, line)) {
    std::istringstream parts(line);
    std::string token;
    while (parts >> token) {
      if (token != "inet" && token != "inet6") {
        continue;
      }
      std::string address;
      if (parts >> address) {
        const std::string::size_type slash = address.find('/');
        if (slash != std::string::npos) {
          address.resize(slash);
        }
        addresses.insert(address);
      }
      break;
    }
  }
  return addresses;
}

static std::string TokenAfter(const std::string& line, const std::string& key) {
  std::istringstream parts(line);
  std::string token;
  while (parts >> token) {
    if (token != key) {
      continue;
    }
    std::string value;
    if (parts >> value) {
      return value;
    }
  }
  return "";
}

static bool ParseLifetimeBytes(const std::string& line, guint64* bytes) {
  const std::string marker = "(bytes)";
  const std::string::size_type marker_pos = line.find(marker);
  if (marker_pos == std::string::npos || marker_pos == 0) {
    return false;
  }
  size_t start = marker_pos;
  while (start > 0 && g_ascii_isdigit(line[start - 1])) {
    start--;
  }
  if (start == marker_pos) {
    return false;
  }
  *bytes = g_ascii_strtoull(line.substr(start, marker_pos - start).c_str(), nullptr, 10);
  return true;
}

static bool ParseXfrmCounters(const std::string& output, guint64* rx, guint64* tx) {
  *rx = 0;
  *tx = 0;
  const std::set<std::string> local = LocalAddresses();
  std::istringstream lines(output);
  std::string line;
  std::string src;
  std::string dst;
  bool awaiting_lifetime = false;
  guint classified = 0;
  while (std::getline(lines, line)) {
    line = Trim(line);
    if (StartsWith(line, "src ")) {
      src = TokenAfter(line, "src");
      dst = TokenAfter(line, "dst");
      awaiting_lifetime = false;
      continue;
    }
    if (line.find("lifetime current:") != std::string::npos) {
      awaiting_lifetime = true;
    }
    if (!awaiting_lifetime) {
      continue;
    }
    guint64 bytes = 0;
    if (!ParseLifetimeBytes(line, &bytes)) {
      continue;
    }
    if (local.find(dst) != local.end()) {
      *rx += bytes;
      classified++;
    } else if (local.find(src) != local.end()) {
      *tx += bytes;
      classified++;
    }
    awaiting_lifetime = false;
  }
  return classified > 0;
}

static guint64 ReadInterfaceCounter(const std::string& iface, const std::string& counter) {
  std::ifstream input(std::string("/sys/class/net/") + iface + "/statistics/" + counter);
  std::string contents;
  std::getline(input, contents);
  return g_ascii_strtoull(Trim(contents).c_str(), nullptr, 10);
}

static bool InterfaceCounters(const std::string& iface, guint64* rx, guint64* tx) {
  if (!g_file_test((std::string("/sys/class/net/") + iface + "/statistics/rx_bytes").c_str(), G_FILE_TEST_IS_REGULAR) ||
      !g_file_test((std::string("/sys/class/net/") + iface + "/statistics/tx_bytes").c_str(), G_FILE_TEST_IS_REGULAR)) {
    return false;
  }
  *rx = ReadInterfaceCounter(iface, "rx_bytes");
  *tx = ReadInterfaceCounter(iface, "tx_bytes");
  return true;
}

static Fields HandleProbe(const Fields& request) {
  Fields contract_error;
  if (!ContractOk(&contract_error)) {
    return contract_error;
  }
  const std::string protocol = Field(request, "protocol");
  if (!ValidateProtocol(protocol)) {
    return Error("invalid_protocol", "Unsupported VPN protocol.");
  }
  CommandResult probe = RunHelper({"probe", protocol});
  if (!probe.ok) {
    return Error("tool_missing", protocol + " runtime tooling is unavailable.");
  }
  Fields fields;
  fields["protocol"] = protocol;
  fields["installed_contract"] = std::to_string(InstalledContractVersion());
  fields["required_contract"] = std::to_string(kContractVersion);
  return Ok(fields);
}

static Fields WireGuardStatus() {
  const bool interface_present = WireGuardInterfaceExists();
  const bool route_via_sw_wg = WireGuardRouteExists();
  const bool policy_rules_present = WireGuardPolicyRulesExist();
  const bool policy_routes_present = WireGuardPolicyRoutesExist();
  const bool connected = interface_present && route_via_sw_wg;
  guint64 rx = 0;
  guint64 tx = 0;
  InterfaceCounters(kWireGuardInterface, &rx, &tx);
  Fields fields;
  fields["status"] = connected ? "connected" : "disconnected";
  fields["interface"] = kWireGuardInterface;
  fields["interface_present"] = interface_present ? "true" : "false";
  fields["route_via_sw_wg"] = route_via_sw_wg ? "true" : "false";
  fields["policy_rules_present"] = policy_rules_present ? "true" : "false";
  fields["policy_routes_present"] = policy_routes_present ? "true" : "false";
  fields["residue_present"] = WireGuardResidueExists() ? "true" : "false";
  fields["rx_bytes"] = std::to_string(rx);
  fields["tx_bytes"] = std::to_string(tx);
  fields["counters_available"] = (rx > 0 || tx > 0) ? "true" : "false";
  return Ok(fields);
}

static Fields HandleWireGuard(const std::string& op, const Fields& request, uid_t peer_uid) {
  Fields contract_error;
  if (!ContractOk(&contract_error)) {
    return contract_error;
  }
  if (op == "wireguard.status") {
    return WireGuardStatus();
  }
  if (op == "wireguard.counters") {
    CommandResult counters = RunHelper({"wireguard-transfer"});
    if (!counters.ok) {
      return Error("counter_unavailable", counters.message.empty() ? "WireGuard counters unavailable." : counters.message);
    }
    Fields fields;
    fields["stdout"] = counters.out;
    return Ok(fields);
  }

  const std::string config_path = Field(request, "config_path");
  if ((op == "wireguard.up" || op == "wireguard.down") &&
      !ValidateConfigPath(config_path, "sw-wg.conf", peer_uid)) {
    return Error("invalid_path", "WireGuard config path is not approved.");
  }

  if (op == "wireguard.up") {
    CommandResult result = RunHelper({"up", config_path});
    if (!result.ok) {
      RunHelper({"policy-clear-link", kWireGuardInterface});
      if (!WaitWireGuardClean()) {
        return Error(
            "vpn_connect_failed",
            (result.message.empty() ? "WireGuard start failed." : result.message) +
                std::string(" Cleanup residue remains: ") +
                WireGuardResidueSummary());
      }
      return Error("vpn_connect_failed", result.message.empty() ? "WireGuard start failed." : result.message);
    }
    if (!WireGuardInterfaceExists()) {
      RunHelper({"policy-clear-link", kWireGuardInterface});
      if (!WaitWireGuardClean()) {
        return Error(
            "vpn_connect_failed",
            std::string("WireGuard command completed but sw-wg was not present. Cleanup residue remains: ") +
                WireGuardResidueSummary());
      }
      return Error("vpn_connect_failed", "WireGuard command completed but sw-wg was not present.");
    }
    if (!WireGuardRouteExists()) {
      RunHelper({"down", config_path});
      RunHelper({"policy-clear-link", kWireGuardInterface});
      if (!WaitWireGuardClean()) {
        return Error(
            "vpn_connect_failed",
            std::string("WireGuard command completed but route evidence did not use sw-wg. Cleanup residue remains: ") +
                WireGuardResidueSummary());
      }
      return Error("vpn_connect_failed", "WireGuard command completed but route evidence did not use sw-wg.");
    }
    return WireGuardStatus();
  }

  if (op == "wireguard.down") {
    CommandResult result = RunHelper({"down", config_path});
    RunHelper({"policy-clear-link", kWireGuardInterface});
    if (!result.ok) {
      if (!WaitWireGuardClean()) {
        return Error(
            "vpn_disconnect_failed",
            (result.message.empty() ? "WireGuard stop failed." : result.message) +
                std::string(" Cleanup residue remains: ") +
                WireGuardResidueSummary());
      }
      return Error("vpn_disconnect_failed", result.message.empty() ? "WireGuard stop failed." : result.message);
    }
    if (!WaitWireGuardClean()) {
      return Error(
          "vpn_disconnect_failed",
          std::string("WireGuard stop completed but cleanup residue remains: ") +
              WireGuardResidueSummary());
    }
    return WireGuardStatus();
  }

  if (op == "wireguard.cleanup") {
    if (!config_path.empty() && ValidateConfigPath(config_path, "sw-wg.conf", peer_uid)) {
      RunHelper({"down", config_path});
    }
    RunHelper({"policy-clear-link", kWireGuardInterface});
    if (!WaitWireGuardClean()) {
      return Error(
          "vpn_cleanup_failed",
          std::string("WireGuard cleanup residue remains: ") +
              WireGuardResidueSummary());
    }
    return WireGuardStatus();
  }

  return Error("invalid_operation", "Unsupported WireGuard operation.");
}

static Fields OpenVpnStatus(const Fields& request, uid_t peer_uid) {
  const std::string pid_path = Field(request, "pid_path");
  const std::string log_path = Field(request, "log_path");
  if (!ValidateRuntimeFilePath(pid_path, kOpenVpnPidName, peer_uid) ||
      !ValidateRuntimeFilePath(log_path, kOpenVpnLogName, peer_uid)) {
    return Error("invalid_path", "OpenVPN runtime path is not approved.");
  }
  const std::string iface = OpenVpnInterfaceName();
  guint64 rx = 0;
  guint64 tx = 0;
  const bool counters = InterfaceCounters(iface, &rx, &tx);
  Fields fields;
  fields["status"] = OpenVpnRuntimeEvidence(pid_path, log_path) ? "connected" : "disconnected";
  fields["interface"] = iface;
  fields["rx_bytes"] = std::to_string(rx);
  fields["tx_bytes"] = std::to_string(tx);
  fields["counters_available"] = counters ? "true" : "false";
  return Ok(fields);
}

static Fields HandleOpenVpn(const std::string& op, const Fields& request, uid_t peer_uid) {
  Fields contract_error;
  if (!ContractOk(&contract_error)) {
    return contract_error;
  }
  if (op == "openvpn.start") {
    // The current source has no authenticated backend evidence or credential
    // issuance contract.  Keep status/stop/cleanup available for residue
    // handling, but never allow direct IPC to bypass the API/client gate.
    return Error(
        "protocol_unavailable",
        "OpenVPN is unavailable until authenticated current-source runtime and credential evidence is recorded.");
  }
  if (op == "openvpn.status") {
    return OpenVpnStatus(request, peer_uid);
  }

  const std::string pid_path = Field(request, "pid_path");
  const std::string log_path = Field(request, "log_path");
  const std::string auth_path = Field(request, "auth_path");
  if (!ValidateRuntimeFilePath(pid_path, kOpenVpnPidName, peer_uid)) {
    return Error("invalid_path", "OpenVPN PID path is not approved.");
  }
  if ((op == "openvpn.stop" || op == "openvpn.cleanup") &&
      !ValidateRuntimeFilePath(log_path, kOpenVpnLogName, peer_uid)) {
    return Error("invalid_path", "OpenVPN log path is not approved.");
  }
  if (!auth_path.empty() &&
      !ValidateRuntimeFilePath(auth_path, kOpenVpnAuthName, peer_uid)) {
    return Error("invalid_path", "OpenVPN auth path is not approved.");
  }
  if (op == "openvpn.cleanup" && auth_path.empty()) {
    return Error("invalid_path", "OpenVPN cleanup requires the auth path.");
  }

  if (op == "openvpn.stop" || op == "openvpn.cleanup") {
    pid_t pid = 0;
    if (!ReadPid(pid_path, &pid)) {
      if (OpenVpnRouteExists()) {
        return Error("vpn_disconnect_failed", "OpenVPN PID file is missing but tunnel route evidence remains.");
      }
      unlink(pid_path.c_str());
      if (op == "openvpn.cleanup") {
        unlink(log_path.c_str());
        if (!auth_path.empty()) {
          unlink(auth_path.c_str());
        }
      }
      return OpenVpnStatus(request, peer_uid);
    }
    if (!ProcessLooksLikeOpenVpn(pid)) {
      if (op == "openvpn.cleanup" && !OpenVpnRouteExists()) {
        unlink(pid_path.c_str());
        unlink(log_path.c_str());
        if (!auth_path.empty()) {
          unlink(auth_path.c_str());
        }
        return OpenVpnStatus(request, peer_uid);
      }
      return Error("vpn_disconnect_failed", "OpenVPN PID file does not point to an OpenVPN process.");
    }
    CommandResult result = RunHelper({"openvpn-stop", std::to_string(static_cast<long>(pid))});
    if (!result.ok) {
      return Error("vpn_disconnect_failed", result.message.empty() ? "OpenVPN stop failed." : result.message);
    }
    if (!WaitOpenVpnStopped(pid_path)) {
      return Error("vpn_disconnect_failed", "OpenVPN stop completed but process or route evidence remains.");
    }
    unlink(pid_path.c_str());
    if (op == "openvpn.cleanup") {
      unlink(log_path.c_str());
      if (!auth_path.empty()) {
        unlink(auth_path.c_str());
      }
    }
    return OpenVpnStatus(request, peer_uid);
  }

  return Error("invalid_operation", "Unsupported OpenVPN operation.");
}

static Fields Ikev2Status() {
  std::string xfrm_output;
  bool routing_loop_rule = false;
  const bool connected = Ikev2RuntimeEvidence(&xfrm_output, &routing_loop_rule);
  guint64 rx = 0;
  guint64 tx = 0;
  const bool counters = ParseXfrmCounters(xfrm_output, &rx, &tx);
  Fields fields;
  fields["status"] = connected ? "connected" : "disconnected";
  fields["interface"] = "xfrm";
  fields["rx_bytes"] = std::to_string(rx);
  fields["tx_bytes"] = std::to_string(tx);
  fields["counters_available"] = counters ? "true" : "false";
  fields["routing_loop_rule_present"] = routing_loop_rule ? "true" : "false";
  return Ok(fields);
}

static Fields HandleIkev2(const std::string& op, const Fields& request, uid_t peer_uid) {
  Fields contract_error;
  if (!ContractOk(&contract_error)) {
    return contract_error;
  }
  if (op == "ikev2.status") {
    return Ikev2Status();
  }

  if (op == "ikev2.stop" || op == "ikev2.cleanup") {
    RunHelper({"ikev2-down"});
    RunHelper({"ikev2-delete"});
    if (!WaitIkev2Stopped()) {
      return Error("vpn_disconnect_failed", "IKEv2 stop completed but active NetworkManager VPN evidence remains.");
    }
    return Ikev2Status();
  }

  if (op != "ikev2.start") {
    return Error("invalid_operation", "Unsupported IKEv2 operation.");
  }

  const std::string config_path = Field(request, "config_path");
  if (!ValidateConfigPath(config_path, kIkev2ConfigName, peer_uid)) {
    return Error("invalid_path", "IKEv2 config path is not approved.");
  }

  std::ifstream input(config_path);
  std::ostringstream buffer;
  buffer << input.rdbuf();
  const std::string contents = buffer.str();
  const std::string server = SwanctlValueForKey(contents, "remote_addrs");
  const std::string username = SwanctlValueForKey(contents, "eap_id");
  const std::string password = SwanctlValueForKey(contents, "secret");
  const std::string remote_id = SwanctlValueForKey(contents, "id");
  const std::string ca_pem = ExtractCaPem(contents);
  if (server.empty() || username.empty() || password.empty()) {
    return Error("invalid_config", "IKEv2 config is missing server, EAP ID, or EAP secret.");
  }

  std::string ca_path;
  if (!ca_pem.empty()) {
    ca_path = Dirname(config_path) + "/" + kIkev2CaName;
    std::string write_error;
    if (!WritePeerOwnedFile(ca_path, ca_pem + "\n", peer_uid, &write_error)) {
      return Error("vpn_connect_failed", "Unable to write IKEv2 CA certificate: " + write_error);
    }
  }

  RunHelper({"ikev2-down"});
  RunHelper({"ikev2-delete"});
  std::vector<std::string> add_args = {"ikev2-add-eap", server, username, password};
  add_args.push_back(remote_id.empty() ? server : remote_id);
  if (!ca_path.empty()) {
    add_args.push_back(ca_path);
  }
  CommandResult add = RunHelper(add_args);
  if (!add.ok) {
    RunHelper({"ikev2-delete"});
    return Error("vpn_connect_failed", add.message.empty() ? "IKEv2 NetworkManager profile creation failed." : add.message);
  }
  CommandResult up = RunHelper({"ikev2-up"});
  if (!up.ok) {
    RunHelper({"ikev2-down"});
    RunHelper({"ikev2-delete"});
    return Error("vpn_connect_failed", up.message.empty() ? "IKEv2 start failed." : up.message);
  }
  for (guint i = 0; i < 40; i++) {
    if (Ikev2RuntimeEvidence()) {
      return Ikev2Status();
    }
    g_usleep(500000);
  }
  RunHelper({"ikev2-down"});
  RunHelper({"ikev2-delete"});
  return Error("vpn_connect_failed", "IKEv2 started but route, DNS, XFRM ESP, and routing-loop safety evidence was not detected.");
}

static Fields HandleRequest(const Fields& request, uid_t peer_uid) {
  if (Field(request, "version") != "1") {
    return Error("invalid_request", "Unsupported helper protocol version.");
  }
  const std::string op = Field(request, "op");
  if (op.empty()) {
    return Error("invalid_request", "Missing helper operation.");
  }
  if (op == "probe") {
    return HandleProbe(request);
  }
  if (StartsWith(op, "wireguard.")) {
    return HandleWireGuard(op, request, peer_uid);
  }
  if (StartsWith(op, "openvpn.")) {
    return HandleOpenVpn(op, request, peer_uid);
  }
  if (StartsWith(op, "ikev2.")) {
    return HandleIkev2(op, request, peer_uid);
  }
  return Error("invalid_operation", "Unsupported helper operation.");
}

static bool PeerGroupsContain(pid_t pid, gid_t group_id) {
  std::ifstream input(std::string("/proc/") + std::to_string(static_cast<long>(pid)) + "/status");
  std::string line;
  while (std::getline(input, line)) {
    if (!StartsWith(line, "Groups:")) {
      continue;
    }
    std::istringstream groups(line.substr(strlen("Groups:")));
    std::string value;
    while (groups >> value) {
      if (static_cast<gid_t>(g_ascii_strtoull(value.c_str(), nullptr, 10)) == group_id) {
        return true;
      }
    }
  }
  return false;
}

static bool PeerCredentialsForFd(int fd, PeerCredentials* peer) {
  struct ucred cred {};
  socklen_t len = sizeof(cred);
  if (getsockopt(fd, SOL_SOCKET, SO_PEERCRED, &cred, &len) != 0) {
    return false;
  }
  peer->uid = cred.uid;
  peer->gid = cred.gid;
  peer->pid = cred.pid;
  peer->valid = true;
  return true;
}

static bool AuthorizedPeer(const PeerCredentials& peer) {
  if (!peer.valid) {
    return false;
  }
  if (peer.uid == 0) {
    return true;
  }
  if (UidAllowedByFile(peer.uid)) {
    return true;
  }
  const struct group* group = getgrnam(kGroupName);
  if (!group) {
    return false;
  }
  return peer.gid == group->gr_gid || PeerGroupsContain(peer.pid, group->gr_gid);
}

static int CreateSocket() {
  if (g_mkdir_with_parents(kRuntimeDir, 0750) != 0) {
    return -1;
  }
  const struct group* group = getgrnam(kGroupName);
  if (group) {
    chown(kRuntimeDir, 0, group->gr_gid);
    chmod(kRuntimeDir, 0750);
  }

  int fd = socket(AF_UNIX, SOCK_STREAM, 0);
  if (fd < 0) {
    return -1;
  }
  unlink(kSocketPath);
  sockaddr_un address {};
  address.sun_family = AF_UNIX;
  g_strlcpy(address.sun_path, kSocketPath, sizeof(address.sun_path));
  if (bind(fd, reinterpret_cast<sockaddr*>(&address), sizeof(address)) != 0) {
    close(fd);
    return -1;
  }
  if (group) {
    chown(kSocketPath, 0, group->gr_gid);
    chmod(kSocketPath, 0660);
  } else {
    chmod(kSocketPath, 0600);
  }
  ApplyAllowedUserAcls();
  if (listen(fd, 16) != 0) {
    close(fd);
    unlink(kSocketPath);
    return -1;
  }
  return fd;
}

static void HandleClient(int client_fd) {
  Fields response;
  PeerCredentials peer;
  if (!PeerCredentialsForFd(client_fd, &peer) || !AuthorizedPeer(peer)) {
    response = Error("unauthorized", "Current user is not authorized for the SecureWave helper service.");
    WriteAll(client_fd, SerializeFields(response));
    return;
  }
  std::string body;
  if (!ReadAll(client_fd, &body)) {
    response = Error("invalid_request", "Helper request was too large or unreadable.");
    WriteAll(client_fd, SerializeFields(response));
    return;
  }
  response = HandleRequest(ParseFields(body), peer.uid);
  WriteAll(client_fd, SerializeFields(response));
}

}  // namespace

int main(int argc, char** argv) {
  (void)argc;
  (void)argv;
  if (geteuid() != 0) {
    g_printerr("securewave-helperd must run as root.\n");
    return 1;
  }
  signal(SIGPIPE, SIG_IGN);
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
    HandleClient(client_fd);
    close(client_fd);
  }
}
