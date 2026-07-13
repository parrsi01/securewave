#include <glib.h>
#include <glib/gstdio.h>

#include <arpa/inet.h>
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
const char* kOpenVpnInterface = "tun-securewave";
const char* kOpenVpnPidName = "securewave-openvpn.pid";
const char* kOpenVpnLogName = "securewave-openvpn.log";
const char* kOpenVpnAuthName = "securewave-openvpn.auth";
const char* kIkev2ConfigName = "securewave-ikev2.conf";
const char* kIkev2CaName = "securewave-ikev2-ca.pem";
const char* kIkev2ConnectionName = "SecureWave-IKEv2";
const char* kAdblockChainName = "SECUREWAVE_ADBLOCK";
const guint kContractVersion = 13;
const gsize kMaxRequestBytes = 64 * 1024;
const size_t kMaxDnsServers = 8;

struct CommandResult {
  bool spawned = false;
  bool ok = false;
  int wait_status = 0;
  std::string out;
  std::string err;
  std::string message;
};

using Fields = std::map<std::string, std::string>;

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

struct DnsServers {
  std::vector<std::string> ipv4;
  std::vector<std::string> ipv6;

  bool empty() const { return ipv4.empty() && ipv6.empty(); }
  size_t size() const { return ipv4.size() + ipv6.size(); }
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
    if (!ValidFieldName(key) || parsed.fields.find(key) != parsed.fields.end()) {
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

static std::string Lower(std::string value) {
  std::transform(value.begin(), value.end(), value.begin(), [](unsigned char c) {
    return static_cast<char>(g_ascii_tolower(c));
  });
  return value;
}

static bool AppendDnsLiteral(const std::string& raw, DnsServers* servers) {
  if (!servers) {
    return false;
  }
  const std::string value = Trim(raw);
  if (value.empty() || value.size() >= INET6_ADDRSTRLEN) {
    return false;
  }

  unsigned char address[sizeof(struct in6_addr)] = {};
  std::vector<std::string>* family = nullptr;
  int address_family = AF_UNSPEC;
  if (inet_pton(AF_INET, value.c_str(), address) == 1) {
    family = &servers->ipv4;
    address_family = AF_INET;
  } else if (inet_pton(AF_INET6, value.c_str(), address) == 1) {
    family = &servers->ipv6;
    address_family = AF_INET6;
  } else {
    return false;
  }
  char canonical[INET6_ADDRSTRLEN] = {};
  if (!inet_ntop(address_family, address, canonical, sizeof(canonical))) {
    return false;
  }
  const std::string normalized(canonical);
  if (std::find(family->begin(), family->end(), normalized) != family->end()) {
    return true;
  }
  if (servers->size() >= kMaxDnsServers) {
    return false;
  }
  family->push_back(normalized);
  return true;
}

static bool ParseCommaSeparatedDns(const std::string& raw,
                                   DnsServers* servers) {
  if (!servers || raw.empty()) {
    return false;
  }
  size_t start = 0;
  while (start <= raw.size()) {
    const size_t comma = raw.find(',', start);
    const std::string value = raw.substr(
        start,
        comma == std::string::npos ? raw.size() - start : comma - start);
    if (!AppendDnsLiteral(value, servers)) {
      return false;
    }
    if (comma == std::string::npos) {
      break;
    }
    start = comma + 1;
  }
  return !servers->empty();
}

static std::vector<std::string> TaggedDnsHelperArgs(
    const std::string& operation,
    const DnsServers& servers) {
  std::vector<std::string> args = {operation};
  for (const std::string& address : servers.ipv4) {
    args.push_back("4:" + address);
  }
  for (const std::string& address : servers.ipv6) {
    args.push_back("6:" + address);
  }
  return args;
}

static bool SafeWireGuardHook(const std::string& key, const std::string& value) {
  static const std::set<std::string> kAllowedPostUp = {
      "sh -c 'command -v iptables >/dev/null 2>&1 && iptables -I OUTPUT ! -o %i -m mark ! --mark $(wg show %i fwmark) -m addrtype ! --dst-type LOCAL -j REJECT'",
      "sh -c 'command -v ip6tables >/dev/null 2>&1 && ip6tables -I OUTPUT ! -o %i -m mark ! --mark $(wg show %i fwmark) -m addrtype ! --dst-type LOCAL -j REJECT'",
  };
  static const std::set<std::string> kAllowedPostDown = {
      "sh -c 'command -v iptables >/dev/null 2>&1 && iptables -D OUTPUT ! -o %i -m mark ! --mark $(wg show %i fwmark) -m addrtype ! --dst-type LOCAL -j REJECT || true'",
      "sh -c 'command -v ip6tables >/dev/null 2>&1 && ip6tables -D OUTPUT ! -o %i -m mark ! --mark $(wg show %i fwmark) -m addrtype ! --dst-type LOCAL -j REJECT || true'",
  };
  if (key == "postup") {
    return kAllowedPostUp.find(value) != kAllowedPostUp.end();
  }
  if (key == "postdown") {
    return kAllowedPostDown.find(value) != kAllowedPostDown.end();
  }
  return false;
}

static bool ValidateWireGuardConfigContents(const std::string& path) {
  std::ifstream input(path, std::ios::binary);
  std::string line;
  std::string section;
  bool saw_interface = false;
  bool saw_peer = false;
  const std::set<std::string> interface_keys = {
      "privatekey", "address", "dns", "mtu", "table", "saveconfig",
      "listenport", "fwmark", "postup", "postdown"};
  const std::set<std::string> peer_keys = {
      "publickey", "presharedkey", "allowedips", "endpoint",
      "persistentkeepalive"};

  while (std::getline(input, line)) {
    if (!line.empty() && line.back() == '\r') {
      line.pop_back();
    }
    if (line.find('\0') != std::string::npos) {
      return false;
    }
    line = Trim(line);
    if (line.empty() || line[0] == '#' || line[0] == ';') {
      continue;
    }
    if (line.front() == '[' && line.back() == ']') {
      section = Lower(Trim(line.substr(1, line.size() - 2)));
      if (section == "interface") {
        saw_interface = true;
      } else if (section == "peer") {
        saw_peer = true;
      } else {
        return false;
      }
      continue;
    }
    const size_t eq = line.find('=');
    if (eq == std::string::npos || section.empty()) {
      return false;
    }
    const std::string key = Lower(Trim(line.substr(0, eq)));
    const std::string value = Trim(line.substr(eq + 1));
    if (value.empty()) {
      return false;
    }
    if (section == "interface") {
      if (interface_keys.find(key) == interface_keys.end()) {
        return false;
      }
      if ((key == "postup" || key == "postdown") &&
          !SafeWireGuardHook(key, value)) {
        return false;
      }
    } else if (peer_keys.find(key) == peer_keys.end()) {
      return false;
    }
  }
  return input.eof() && saw_interface && saw_peer;
}

static bool ValidateOpenVpnConfigContents(const std::string& path,
                                          DnsServers* dns_servers = nullptr) {
  static const std::set<std::string> kForbiddenDirectives = {
      "up", "down", "route-up", "route-pre-down", "ipchange",
      "client-connect", "client-disconnect", "learn-address", "tls-verify",
      "auth-user-pass-verify", "plugin", "script-security", "management",
      "management-client-user", "management-client-group", "config", "include",
      "cd", "chroot", "daemon", "user", "group", "writepid", "log",
      "log-append", "status", "client-config-dir", "ifconfig-pool-persist",
      "replay-persist", "askpass", "tmp-dir"};
  std::ifstream input(path, std::ios::binary);
  std::string line;
  bool saw_client = false;
  std::string inline_block;
  DnsServers parsed_dns;
  const std::set<std::string> allowed_inline_blocks = {
      "ca", "cert", "key", "pkcs12", "tls-auth", "tls-crypt",
      "tls-crypt-v2", "connection"};
  while (std::getline(input, line)) {
    if (!line.empty() && line.back() == '\r') {
      line.pop_back();
    }
    if (line.find('\0') != std::string::npos) {
      return false;
    }
    line = Trim(line);
    if (line.empty() || line[0] == '#' || line[0] == ';') {
      continue;
    }
    if (line.front() == '<' && line.back() == '>') {
      const bool closing = line.size() > 2 && line[1] == '/';
      const size_t name_start = closing ? 2 : 1;
      const std::string name =
          Lower(Trim(line.substr(name_start, line.size() - name_start - 1)));
      if (allowed_inline_blocks.find(name) == allowed_inline_blocks.end()) {
        return false;
      }
      if (closing) {
        if (inline_block != name) {
          return false;
        }
        inline_block.clear();
      } else {
        if (!inline_block.empty()) {
          return false;
        }
        inline_block = name;
      }
      continue;
    }
    if (!inline_block.empty() && inline_block != "connection") {
      continue;
    }
    std::istringstream tokens(line);
    std::string directive;
    tokens >> directive;
    directive = Lower(directive);
    if (StartsWith(directive, "--")) {
      directive = directive.substr(2);
    }
    if (directive == "client") {
      saw_client = true;
    }
    if (directive == "dev") {
      std::string device_type;
      std::string extra;
      if (!(tokens >> device_type) || Lower(device_type) != "tun" ||
          (tokens >> extra)) {
        return false;
      }
    }
    if (kForbiddenDirectives.find(directive) != kForbiddenDirectives.end()) {
      return false;
    }
    if (directive == "auth-user-pass") {
      std::string path_arg;
      if (tokens >> path_arg) {
        return false;
      }
    }
    if (directive == "dhcp-option") {
      std::string option;
      if (!(tokens >> option) || Lower(option) != "dns") {
        continue;
      }
      std::string address;
      std::string extra;
      if (!(tokens >> address) || (tokens >> extra) ||
          !AppendDnsLiteral(address, &parsed_dns)) {
        return false;
      }
    }
  }
  const bool valid = input.eof() && inline_block.empty() && saw_client &&
                     !parsed_dns.empty();
  if (valid && dns_servers) {
    *dns_servers = parsed_dns;
  }
  return valid;
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

static bool ProcessLooksLikeOpenVpn(pid_t pid, const std::string& config_path) {
  if (pid <= 0 || config_path.empty()) {
    return false;
  }
  const std::string proc_dir = std::string("/proc/") +
                               std::to_string(static_cast<long>(pid));
  struct stat proc_stat {};
  if (stat(proc_dir.c_str(), &proc_stat) != 0 || proc_stat.st_uid != 0) {
    return false;
  }
  std::ifstream comm(std::string("/proc/") + std::to_string(static_cast<long>(pid)) + "/comm");
  std::string name;
  std::getline(comm, name);
  name = Trim(name);
  if (name != "openvpn") {
    return false;
  }

  std::ifstream cmdline(
      std::string("/proc/") + std::to_string(static_cast<long>(pid)) + "/cmdline",
      std::ios::binary);
  std::string raw((std::istreambuf_iterator<char>(cmdline)), std::istreambuf_iterator<char>());
  std::vector<std::string> args;
  size_t start = 0;
  while (start < raw.size()) {
    const size_t end = raw.find('\0', start);
    args.push_back(raw.substr(
        start,
        end == std::string::npos ? raw.size() - start : end - start));
    if (end == std::string::npos) {
      break;
    }
    start = end + 1;
  }
  bool expected_config = false;
  bool expected_interface = false;
  for (size_t i = 0; i + 1 < args.size(); i++) {
    if (args[i] == "--config" && args[i + 1] == config_path) {
      expected_config = true;
    }
    if (args[i] == "--dev" && args[i + 1] == kOpenVpnInterface) {
      expected_interface = true;
    }
  }
  return expected_config && expected_interface;
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

static bool WgQuickNftTablePresent(const std::string& output) {
  std::istringstream lines(output);
  std::string line;
  while (std::getline(lines, line)) {
    std::istringstream fields(Trim(line));
    std::string table_keyword;
    std::string family;
    std::string name;
    std::string extra;
    if ((fields >> table_keyword >> family >> name) &&
        !(fields >> extra) &&
        table_keyword == "table" &&
        (family == "ip" || family == "ip6" || family == "inet") &&
        name == "wg-quick-sw-wg") {
      return true;
    }
  }
  return false;
}

static bool WgQuickIptablesRulePresent(const std::string& output) {
  const std::string marker =
      "-m comment --comment \"wg-quick(8) rule for sw-wg\"";
  std::istringstream lines(output);
  std::string line;
  while (std::getline(lines, line)) {
    line = Trim(line);
    if (StartsWith(line, "-A ") && line.find(marker) != std::string::npos) {
      return true;
    }
  }
  return false;
}

struct WireGuardFirewallEvidence {
  bool inspection_ok = false;
  bool nft_table_present = false;
  bool iptables_rule_present = false;
  bool ip6tables_rule_present = false;
};

static WireGuardFirewallEvidence ReadWireGuardFirewallEvidence() {
  const CommandResult nft = RunCommand({"nft", "list", "tables"});
  const CommandResult iptables = RunCommand({"iptables-save"});
  const CommandResult ip6tables = RunCommand({"ip6tables-save"});
  WireGuardFirewallEvidence evidence;
  evidence.inspection_ok = nft.ok && iptables.ok && ip6tables.ok;
  evidence.nft_table_present = WgQuickNftTablePresent(nft.out);
  evidence.iptables_rule_present =
      WgQuickIptablesRulePresent(iptables.out);
  evidence.ip6tables_rule_present =
      WgQuickIptablesRulePresent(ip6tables.out);
  return evidence;
}

static bool WireGuardFirewallResidueExists(
    const WireGuardFirewallEvidence& evidence) {
  return !evidence.inspection_ok ||
         evidence.nft_table_present ||
         evidence.iptables_rule_present ||
         evidence.ip6tables_rule_present;
}

static bool WireGuardResidueExists() {
  const WireGuardFirewallEvidence firewall =
      ReadWireGuardFirewallEvidence();
  return WireGuardInterfaceExists() ||
         WireGuardRouteExists() ||
         WireGuardPolicyRulesExist() ||
         WireGuardPolicyRoutesExist() ||
         WireGuardFirewallResidueExists(firewall);
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
  const WireGuardFirewallEvidence firewall =
      ReadWireGuardFirewallEvidence();
  if (!firewall.inspection_ok) {
    parts.emplace_back("WireGuard firewall inspection failed");
  } else {
    if (firewall.nft_table_present) {
      parts.emplace_back("wg-quick-sw-wg nftables table present");
    }
    if (firewall.iptables_rule_present) {
      parts.emplace_back("wg-quick sw-wg IPv4 rule present");
    }
    if (firewall.ip6tables_rule_present) {
      parts.emplace_back("wg-quick sw-wg IPv6 rule present");
    }
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
  return g_file_test(
      (std::string("/sys/class/net/") + kOpenVpnInterface).c_str(),
      G_FILE_TEST_IS_DIR);
}

static std::string OpenVpnInterfaceName() {
  return OpenVpnTunExists() ? kOpenVpnInterface : "";
}

static bool OpenVpnRouteExists() {
  CommandResult result = RunCommand({"ip", "route", "get", "1.1.1.1"});
  return result.ok &&
         result.out.find(std::string(" dev ") + kOpenVpnInterface) !=
             std::string::npos;
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

static bool ExtractIkev2DnsServers(const std::string& contents,
                                   DnsServers* servers) {
  if (!servers) {
    return false;
  }
  const std::string prefix = "# dns =";
  bool found = false;
  std::istringstream stream(contents);
  std::string line;
  while (std::getline(stream, line)) {
    if (!line.empty() && line.back() == '\r') {
      line.pop_back();
    }
    line = Trim(line);
    if (!StartsWith(line, prefix)) {
      continue;
    }
    if (found) {
      return false;
    }
    found = true;
    if (!ParseCommaSeparatedDns(Trim(line.substr(prefix.size())), servers)) {
      return false;
    }
  }
  return found && !servers->empty();
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

static bool OutputContainsDelimitedValue(const std::string& output,
                                         const std::string& value) {
  size_t pos = output.find(value);
  while (pos != std::string::npos) {
    const auto dns_char = [](unsigned char c) {
      return g_ascii_isxdigit(c) || c == ':' || c == '.';
    };
    const bool left_ok = pos == 0 || !dns_char(output[pos - 1]);
    const size_t end = pos + value.size();
    const bool right_ok = end == output.size() || !dns_char(output[end]);
    if (left_ok && right_ok) {
      return true;
    }
    pos = output.find(value, pos + 1);
  }
  return false;
}

static bool OutputContainsWhitespaceDelimitedToken(
    const std::string& output,
    const std::string& token) {
  size_t pos = output.find(token);
  while (pos != std::string::npos) {
    const bool left_ok =
        pos == 0 || g_ascii_isspace(static_cast<unsigned char>(output[pos - 1]));
    const size_t end = pos + token.size();
    const bool right_ok =
        end == output.size() ||
        g_ascii_isspace(static_cast<unsigned char>(output[end]));
    if (left_ok && right_ok) {
      return true;
    }
    pos = output.find(token, pos + 1);
  }
  return false;
}

static bool OpenVpnResolvedDnsEvidence(const DnsServers& dns_servers) {
  if (dns_servers.empty()) {
    return false;
  }
  CommandResult dns = RunCommand({"resolvectl", "dns", kOpenVpnInterface});
  CommandResult domains =
      RunCommand({"resolvectl", "domain", kOpenVpnInterface});
  if (!dns.ok || !domains.ok ||
      !OutputContainsWhitespaceDelimitedToken(domains.out, "~.")) {
    return false;
  }
  for (const std::string& address : dns_servers.ipv4) {
    if (!OutputContainsDelimitedValue(dns.out, address)) {
      return false;
    }
  }
  for (const std::string& address : dns_servers.ipv6) {
    if (!OutputContainsDelimitedValue(dns.out, address)) {
      return false;
    }
  }
  return true;
}

static bool OpenVpnTunnelEvidence(const std::string& config_path,
                                  const std::string& pid_path,
                                  const std::string& log_path) {
  pid_t pid = 0;
  return ReadPid(pid_path, &pid) &&
         ProcessRunning(pid) &&
         ProcessLooksLikeOpenVpn(pid, config_path) &&
         FileContains(log_path, "Initialization Sequence Completed") &&
         OpenVpnTunExists() &&
         OpenVpnRouteExists();
}

static bool OpenVpnRuntimeEvidence(const std::string& config_path,
                                   const std::string& pid_path,
                                   const std::string& log_path) {
  DnsServers dns_servers;
  return ValidateOpenVpnConfigContents(config_path, &dns_servers) &&
         OpenVpnTunnelEvidence(config_path, pid_path, log_path) &&
         OpenVpnResolvedDnsEvidence(dns_servers);
}

static bool WaitOpenVpnStarted(const std::string& config_path,
                               const std::string& pid_path,
                               const std::string& log_path) {
  for (guint i = 0; i < 40; i++) {
    if (OpenVpnTunnelEvidence(config_path, pid_path, log_path)) {
      return true;
    }
    g_usleep(500000);
  }
  return false;
}

static bool WaitOpenVpnStopped(const std::string& config_path,
                               const std::string& pid_path) {
  for (guint i = 0; i < 20; i++) {
    pid_t pid = 0;
    const bool openvpn_running =
        ReadPid(pid_path, &pid) && ProcessRunning(pid) &&
        ProcessLooksLikeOpenVpn(pid, config_path);
    if (!openvpn_running && !OpenVpnTunExists() && !OpenVpnRouteExists()) {
      return true;
    }
    g_usleep(500000);
  }
  pid_t pid = 0;
  const bool openvpn_running =
      ReadPid(pid_path, &pid) && ProcessRunning(pid) &&
      ProcessLooksLikeOpenVpn(pid, config_path);
  return !openvpn_running && !OpenVpnTunExists() && !OpenVpnRouteExists();
}

static std::string OpenVpnLogTail(const std::string& path) {
  std::ifstream input(path);
  std::vector<std::string> lines;
  std::string line;
  while (std::getline(input, line)) {
    line = Trim(line);
    if (!line.empty()) {
      lines.push_back(line);
    }
  }
  const size_t start = lines.size() > 8 ? lines.size() - 8 : 0;
  std::string tail;
  for (size_t i = start; i < lines.size(); i++) {
    if (!tail.empty()) {
      tail += " | ";
    }
    tail += lines[i];
  }
  return CleanMessage(tail);
}

static bool NmcliListHasExactIkev2(const std::string& output) {
  std::istringstream stream(output);
  std::string line;
  const std::string expected = std::string(kIkev2ConnectionName) + ":vpn";
  while (std::getline(stream, line)) {
    if (Trim(line) == expected) {
      return true;
    }
  }
  return false;
}

struct Ikev2ConnectionEvidence {
  bool inspection_ok = false;
  bool connection_present = false;
  bool active = false;
};

static Ikev2ConnectionEvidence ReadIkev2ConnectionEvidence() {
  const CommandResult saved = RunCommand(
      {"nmcli", "-t", "-f", "NAME,TYPE", "connection", "show"});
  const CommandResult active = RunCommand({
      "nmcli", "-t", "-f", "NAME,TYPE", "connection", "show", "--active"});
  Ikev2ConnectionEvidence evidence;
  evidence.inspection_ok = saved.ok && active.ok;
  evidence.connection_present = NmcliListHasExactIkev2(saved.out);
  evidence.active = NmcliListHasExactIkev2(active.out);
  return evidence;
}

struct Ikev2NetworkEvidence {
  bool inspected = false;
  bool dns_present = false;
  bool route_present = false;
};

static Ikev2NetworkEvidence ParseIkev2NetworkEvidence(
    const std::string& output) {
  Ikev2NetworkEvidence evidence;
  evidence.inspected = true;
  std::istringstream stream(output);
  std::string line;
  while (std::getline(stream, line)) {
    line = Trim(line);
    const std::string::size_type colon = line.find(':');
    if (colon == std::string::npos) {
      continue;
    }
    std::string value = Trim(line.substr(colon + 1));
    if (value.empty() || value == "--") {
      continue;
    }
    const std::string field = line.substr(0, colon);
    if (StartsWith(field, "IP4.DNS") || StartsWith(field, "IP6.DNS")) {
      evidence.dns_present = true;
    } else if (StartsWith(field, "IP4.ROUTE") ||
               StartsWith(field, "IP6.ROUTE")) {
      evidence.route_present = true;
    }
  }
  return evidence;
}

static Ikev2NetworkEvidence ReadIkev2NetworkEvidence() {
  CommandResult result = RunCommand({
      "nmcli", "-t", "-f", "IP4.DNS,IP4.ROUTE,IP6.DNS,IP6.ROUTE",
      "connection", "show", kIkev2ConnectionName});
  if (!result.ok) {
    return Ikev2NetworkEvidence();
  }
  return ParseIkev2NetworkEvidence(result.out);
}

static bool XfrmHasEsp(const std::string& output) {
  return output.find("proto esp") != std::string::npos;
}

static bool XfrmOutputPresent(const std::string& output) {
  return !Trim(output).empty();
}

static CommandResult ReadXfrmState() {
  return RunCommand({"ip", "-s", "xfrm", "state"});
}

static CommandResult ReadXfrmPolicy() {
  return RunCommand({"ip", "xfrm", "policy"});
}

static CommandResult ReadIpRules(const char* family) {
  return RunCommand({"ip", family, "rule", "show"});
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

struct Ikev2RuntimeSnapshot {
  CommandResult xfrm_state;
  CommandResult xfrm_policy;
  CommandResult rules4;
  CommandResult rules6;
  Ikev2ConnectionEvidence connection;
  Ikev2NetworkEvidence network;
  bool routing_loop_rule_present = false;
  bool connected = false;
};

static Ikev2RuntimeSnapshot ReadIkev2RuntimeSnapshot() {
  Ikev2RuntimeSnapshot snapshot;
  snapshot.xfrm_state = ReadXfrmState();
  snapshot.xfrm_policy = ReadXfrmPolicy();
  snapshot.rules4 = ReadIpRules("-4");
  snapshot.rules6 = ReadIpRules("-6");
  snapshot.connection = ReadIkev2ConnectionEvidence();
  snapshot.network = ReadIkev2NetworkEvidence();
  snapshot.routing_loop_rule_present =
      (snapshot.rules4.ok &&
       Ikev2HasUnqualifiedPref220Rule(snapshot.rules4.out)) ||
      (snapshot.rules6.ok &&
       Ikev2HasUnqualifiedPref220Rule(snapshot.rules6.out));
  snapshot.connected =
      snapshot.connection.inspection_ok &&
      snapshot.connection.connection_present &&
      snapshot.connection.active &&
      snapshot.network.inspected &&
      snapshot.network.dns_present &&
      snapshot.network.route_present &&
      snapshot.xfrm_state.ok &&
      XfrmHasEsp(snapshot.xfrm_state.out) &&
      snapshot.xfrm_policy.ok &&
      XfrmOutputPresent(snapshot.xfrm_policy.out) &&
      snapshot.rules4.ok &&
      snapshot.rules6.ok &&
      !snapshot.routing_loop_rule_present;
  return snapshot;
}

static bool Ikev2RuntimeEvidence() {
  return ReadIkev2RuntimeSnapshot().connected;
}

static bool Ikev2DisconnectedStateClean(bool connection_inspection_ok,
                                        bool connection_present,
                                        bool nm_active,
                                        bool state_inspection_ok,
                                        bool state_present,
                                        bool policy_inspection_ok,
                                        bool policy_present) {
  return connection_inspection_ok &&
         !connection_present &&
         !nm_active &&
         state_inspection_ok &&
         !state_present &&
         policy_inspection_ok &&
         !policy_present;
}

static bool WaitIkev2Stopped() {
  for (guint i = 0; i < 20; i++) {
    const Ikev2ConnectionEvidence connection =
        ReadIkev2ConnectionEvidence();
    const CommandResult state = ReadXfrmState();
    const CommandResult policy = ReadXfrmPolicy();
    if (Ikev2DisconnectedStateClean(
            connection.inspection_ok,
            connection.connection_present,
            connection.active,
            state.ok,
            XfrmOutputPresent(state.out),
            policy.ok,
            XfrmOutputPresent(policy.out))) {
      return true;
    }
    g_usleep(500000);
  }
  const Ikev2ConnectionEvidence connection = ReadIkev2ConnectionEvidence();
  const CommandResult state = ReadXfrmState();
  const CommandResult policy = ReadXfrmPolicy();
  return Ikev2DisconnectedStateClean(
      connection.inspection_ok,
      connection.connection_present,
      connection.active,
      state.ok,
      XfrmOutputPresent(state.out),
      policy.ok,
      XfrmOutputPresent(policy.out));
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

static bool IptablesReportsMissingChain(const CommandResult& result) {
  const std::string diagnostic = result.out + "\n" + result.err;
  return diagnostic.find("No chain/target/match by that name") !=
             std::string::npos ||
         diagnostic.find("Chain 'SECUREWAVE_ADBLOCK' does not exist") !=
             std::string::npos;
}

static Fields AdblockStatus() {
  Fields contract_error;
  if (!ContractOk(&contract_error)) {
    return contract_error;
  }
  CommandResult inspection =
      RunCommand({"iptables", "-S", kAdblockChainName});
  Fields fields;
  if (inspection.ok) {
    fields["present"] = "true";
    return Ok(fields);
  }
  if (inspection.spawned && IptablesReportsMissingChain(inspection)) {
    fields["present"] = "false";
    return Ok(fields);
  }
  return Error(
      "inspection_failed",
      "Unable to inspect legacy SecureWave adblock firewall state.");
}

static Fields WireGuardStatus() {
  const bool interface_present = WireGuardInterfaceExists();
  const bool route_via_sw_wg = WireGuardRouteExists();
  const bool policy_rules_present = WireGuardPolicyRulesExist();
  const bool policy_routes_present = WireGuardPolicyRoutesExist();
  const WireGuardFirewallEvidence firewall =
      ReadWireGuardFirewallEvidence();
  const bool connected = interface_present && route_via_sw_wg;
  guint64 rx = 0;
  guint64 tx = 0;
  const bool counters = InterfaceCounters(kWireGuardInterface, &rx, &tx);
  Fields fields;
  fields["status"] = connected ? "connected" : "disconnected";
  fields["interface"] = kWireGuardInterface;
  fields["interface_present"] = interface_present ? "true" : "false";
  fields["route_via_sw_wg"] = route_via_sw_wg ? "true" : "false";
  fields["policy_rules_present"] = policy_rules_present ? "true" : "false";
  fields["policy_routes_present"] = policy_routes_present ? "true" : "false";
  fields["firewall_inspection_ok"] =
      firewall.inspection_ok ? "true" : "false";
  fields["nft_table_present"] =
      firewall.nft_table_present ? "true" : "false";
  fields["iptables_rule_present"] =
      firewall.iptables_rule_present ? "true" : "false";
  fields["ip6tables_rule_present"] =
      firewall.ip6tables_rule_present ? "true" : "false";
  const bool firewall_residue = WireGuardFirewallResidueExists(firewall);
  fields["firewall_residue_present"] =
      firewall_residue ? "true" : "false";
  fields["residue_present"] =
      (interface_present || route_via_sw_wg || policy_rules_present ||
       policy_routes_present || firewall_residue)
          ? "true"
          : "false";
  fields["rx_bytes"] = std::to_string(rx);
  fields["tx_bytes"] = std::to_string(tx);
  fields["counters_available"] = counters ? "true" : "false";
  if (!firewall.inspection_ok) {
    return Error(
        "inspection_failed",
        "Unable to inspect privileged WireGuard firewall state.",
        fields);
  }
  if (!connected && firewall_residue) {
    return Error(
        "vpn_residue_present",
        "WireGuard is disconnected but owned firewall residue remains.",
        fields);
  }
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
    if (!ValidateWireGuardConfigContents(config_path)) {
      return Error(
          "invalid_config",
          "WireGuard config contains unsupported privileged directives.");
    }
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
  const std::string config_path = Field(request, "config_path");
  const std::string pid_path = Field(request, "pid_path");
  const std::string log_path = Field(request, "log_path");
  if (!ValidateConfigPath(config_path, "securewave.ovpn", peer_uid) ||
      !ValidateRuntimeFilePath(pid_path, kOpenVpnPidName, peer_uid) ||
      !ValidateRuntimeFilePath(log_path, kOpenVpnLogName, peer_uid)) {
    return Error("invalid_path", "OpenVPN runtime path is not approved.");
  }
  const std::string iface = OpenVpnInterfaceName();
  pid_t pid = 0;
  const bool process_present =
      ReadPid(pid_path, &pid) && ProcessRunning(pid) &&
      ProcessLooksLikeOpenVpn(pid, config_path);
  const bool initialization_complete =
      FileContains(log_path, "Initialization Sequence Completed");
  const bool interface_present = !iface.empty();
  const bool route_present = OpenVpnRouteExists();
  DnsServers dns_servers;
  const bool dns_profile_valid =
      ValidateOpenVpnConfigContents(config_path, &dns_servers);
  const bool dns_configured =
      dns_profile_valid && OpenVpnResolvedDnsEvidence(dns_servers);
  guint64 rx = 0;
  guint64 tx = 0;
  const bool counters = InterfaceCounters(iface, &rx, &tx);
  Fields fields;
  fields["status"] = OpenVpnRuntimeEvidence(config_path, pid_path, log_path)
                         ? "connected"
                         : "disconnected";
  fields["interface"] = iface;
  fields["process_present"] = process_present ? "true" : "false";
  fields["initialization_complete"] = initialization_complete ? "true" : "false";
  fields["interface_present"] = interface_present ? "true" : "false";
  fields["route_present"] = route_present ? "true" : "false";
  fields["dns_configured"] = dns_configured ? "true" : "false";
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
  if (op == "openvpn.status") {
    return OpenVpnStatus(request, peer_uid);
  }

  const std::string config_path = Field(request, "config_path");
  const std::string pid_path = Field(request, "pid_path");
  const std::string log_path = Field(request, "log_path");
  const std::string auth_path = Field(request, "auth_path");
  if ((op == "openvpn.start" || op == "openvpn.stop" ||
       op == "openvpn.cleanup") &&
      !ValidateConfigPath(config_path, "securewave.ovpn", peer_uid)) {
    return Error("invalid_path", "OpenVPN config path is not approved.");
  }
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

  if (op == "openvpn.start") {
    if (!ValidateConfigPath(config_path, "securewave.ovpn", peer_uid) ||
        !ValidateRuntimeFilePath(log_path, kOpenVpnLogName, peer_uid)) {
      return Error("invalid_path", "OpenVPN config or log path is not approved.");
    }
    DnsServers dns_servers;
    if (!ValidateOpenVpnConfigContents(config_path, &dns_servers)) {
      return Error(
          "invalid_config",
          "OpenVPN config contains unsupported directives or missing/invalid DNS IPs.");
    }
    if (OpenVpnTunExists()) {
      return Error(
          "vpn_connect_failed",
          "The dedicated SecureWave OpenVPN interface already exists.");
    }
    CommandResult preflight_dns_revert =
        RunHelper({"openvpn-dns-revert"});
    if (!preflight_dns_revert.ok) {
      return Error(
          "vpn_connect_failed",
          "Unable to clear stale SecureWave OpenVPN DNS state.");
    }
    std::vector<std::string> args = {"openvpn-start", config_path, pid_path, log_path};
    if (!auth_path.empty()) {
      args.push_back(auth_path);
    }
    CommandResult result = RunHelper(args);
    if (!result.ok) {
      RunHelper({"openvpn-dns-revert"});
      return Error("vpn_connect_failed", result.message.empty() ? "OpenVPN start failed." : result.message);
    }
    if (!WaitOpenVpnStarted(config_path, pid_path, log_path)) {
      pid_t pid = 0;
      if (ReadPid(pid_path, &pid) && ProcessLooksLikeOpenVpn(pid, config_path)) {
        RunHelper({"openvpn-stop", std::to_string(static_cast<long>(pid))});
      }
      RunHelper({"openvpn-dns-revert"});
      const std::string tail = OpenVpnLogTail(log_path);
      WaitOpenVpnStopped(config_path, pid_path);
      unlink(pid_path.c_str());
      unlink(log_path.c_str());
      return Error(
          "vpn_connect_failed",
          tail.empty()
              ? "OpenVPN started but tunnel route evidence was not detected."
              : "OpenVPN started but tunnel route evidence was not detected. Last log lines: " + tail);
    }
    CommandResult dns_apply =
        RunHelper(TaggedDnsHelperArgs("openvpn-dns-apply", dns_servers));
    if (!dns_apply.ok) {
      RunHelper({"openvpn-dns-revert"});
      pid_t pid = 0;
      if (ReadPid(pid_path, &pid) && ProcessLooksLikeOpenVpn(pid, config_path)) {
        RunHelper({"openvpn-stop", std::to_string(static_cast<long>(pid))});
      }
      WaitOpenVpnStopped(config_path, pid_path);
      unlink(pid_path.c_str());
      unlink(log_path.c_str());
      return Error(
          "vpn_connect_failed",
          "OpenVPN connected but SecureWave DNS enforcement failed.");
    }
    if (!OpenVpnResolvedDnsEvidence(dns_servers)) {
      RunHelper({"openvpn-dns-revert"});
      pid_t pid = 0;
      if (ReadPid(pid_path, &pid) && ProcessLooksLikeOpenVpn(pid, config_path)) {
        RunHelper({"openvpn-stop", std::to_string(static_cast<long>(pid))});
      }
      WaitOpenVpnStopped(config_path, pid_path);
      unlink(pid_path.c_str());
      unlink(log_path.c_str());
      return Error(
          "vpn_connect_failed",
          "OpenVPN DNS settings could not be verified on the dedicated tunnel link.");
    }
    return OpenVpnStatus(request, peer_uid);
  }

  if (op == "openvpn.stop" || op == "openvpn.cleanup") {
    CommandResult dns_revert = RunHelper({"openvpn-dns-revert"});
    pid_t pid = 0;
    if (!ReadPid(pid_path, &pid)) {
      if (OpenVpnTunExists() || OpenVpnRouteExists()) {
        return Error(
            "vpn_disconnect_failed",
            "OpenVPN PID file is missing but dedicated tunnel residue remains.");
      }
      unlink(pid_path.c_str());
      if (op == "openvpn.cleanup") {
        unlink(log_path.c_str());
        if (!auth_path.empty()) {
          unlink(auth_path.c_str());
        }
      }
      if (!dns_revert.ok) {
        return Error(
            "vpn_disconnect_failed",
            "OpenVPN stopped but SecureWave DNS state could not be reverted.");
      }
      return OpenVpnStatus(request, peer_uid);
    }
    if (!ProcessLooksLikeOpenVpn(pid, config_path)) {
      if (op == "openvpn.cleanup" && !OpenVpnTunExists() &&
          !OpenVpnRouteExists()) {
        unlink(pid_path.c_str());
        unlink(log_path.c_str());
        if (!auth_path.empty()) {
          unlink(auth_path.c_str());
        }
        if (!dns_revert.ok) {
          return Error(
              "vpn_disconnect_failed",
              "OpenVPN process was absent but SecureWave DNS state could not be reverted.");
        }
        return OpenVpnStatus(request, peer_uid);
      }
      return Error("vpn_disconnect_failed", "OpenVPN PID file does not point to an OpenVPN process.");
    }
    CommandResult result = RunHelper({"openvpn-stop", std::to_string(static_cast<long>(pid))});
    if (!result.ok) {
      return Error("vpn_disconnect_failed", result.message.empty() ? "OpenVPN stop failed." : result.message);
    }
    if (!WaitOpenVpnStopped(config_path, pid_path)) {
      return Error("vpn_disconnect_failed", "OpenVPN stop completed but process or route evidence remains.");
    }
    unlink(pid_path.c_str());
    if (op == "openvpn.cleanup") {
      unlink(log_path.c_str());
      if (!auth_path.empty()) {
        unlink(auth_path.c_str());
      }
    }
    if (!dns_revert.ok) {
      return Error(
          "vpn_disconnect_failed",
          "OpenVPN stopped but SecureWave DNS state could not be reverted.");
    }
    return OpenVpnStatus(request, peer_uid);
  }

  return Error("invalid_operation", "Unsupported OpenVPN operation.");
}

static Fields Ikev2Status() {
  const Ikev2RuntimeSnapshot snapshot = ReadIkev2RuntimeSnapshot();
  const bool xfrm_state_present =
      XfrmOutputPresent(snapshot.xfrm_state.out);
  const bool xfrm_policy_present =
      XfrmOutputPresent(snapshot.xfrm_policy.out);
  const bool xfrm_esp_present = XfrmHasEsp(snapshot.xfrm_state.out);
  guint64 rx = 0;
  guint64 tx = 0;
  const bool counters =
      snapshot.xfrm_state.ok &&
      ParseXfrmCounters(snapshot.xfrm_state.out, &rx, &tx);
  Fields fields;
  fields["status"] = snapshot.connected ? "connected" : "disconnected";
  fields["interface"] = "xfrm";
  fields["rx_bytes"] = std::to_string(rx);
  fields["tx_bytes"] = std::to_string(tx);
  fields["counters_available"] = counters ? "true" : "false";
  fields["routing_loop_rule_present"] =
      snapshot.routing_loop_rule_present ? "true" : "false";
  fields["connection_inspection_ok"] =
      snapshot.connection.inspection_ok ? "true" : "false";
  fields["connection_present"] =
      snapshot.connection.connection_present ? "true" : "false";
  fields["nm_active"] = snapshot.connection.active ? "true" : "false";
  fields["dns_present"] = snapshot.network.dns_present ? "true" : "false";
  fields["route_present"] =
      snapshot.network.route_present ? "true" : "false";
  fields["route_or_dns_present"] =
      (snapshot.network.dns_present || snapshot.network.route_present)
          ? "true"
          : "false";
  fields["xfrm_state_inspection_ok"] =
      snapshot.xfrm_state.ok ? "true" : "false";
  fields["xfrm_policy_inspection_ok"] =
      snapshot.xfrm_policy.ok ? "true" : "false";
  fields["xfrm_state_present"] = xfrm_state_present ? "true" : "false";
  fields["xfrm_esp_present"] = xfrm_esp_present ? "true" : "false";
  fields["xfrm_policy_present"] = xfrm_policy_present ? "true" : "false";

  if (!snapshot.connection.inspection_ok ||
      !snapshot.xfrm_state.ok ||
      !snapshot.xfrm_policy.ok) {
    return Error(
        "inspection_failed",
        "Unable to inspect IKEv2 NetworkManager or privileged XFRM state.",
        fields);
  }
  if (!snapshot.connected &&
      !Ikev2DisconnectedStateClean(
          snapshot.connection.inspection_ok,
          snapshot.connection.connection_present,
          snapshot.connection.active,
          snapshot.xfrm_state.ok,
          xfrm_state_present,
          snapshot.xfrm_policy.ok,
          xfrm_policy_present)) {
    return Error(
        "vpn_residue_present",
        "IKEv2 is not connected but privileged runtime residue remains.",
        fields);
  }
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
    WaitIkev2Stopped();
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
  DnsServers dns_servers;
  if (server.empty() || username.empty() || password.empty()) {
    return Error("invalid_config", "IKEv2 config is missing server, EAP ID, or EAP secret.");
  }
  if (!ExtractIkev2DnsServers(contents, &dns_servers)) {
    return Error(
        "invalid_config",
        "IKEv2 config is missing a valid SecureWave DNS IP marker.");
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
  CommandResult dns =
      RunHelper(TaggedDnsHelperArgs("ikev2-set-dns", dns_servers));
  if (!dns.ok) {
    RunHelper({"ikev2-delete"});
    return Error(
        "vpn_connect_failed",
        dns.message.empty()
            ? "IKEv2 NetworkManager DNS enforcement failed."
            : dns.message);
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

static bool RequestFieldsAllowed(const Fields& request,
                                 const std::set<std::string>& allowed) {
  for (const auto& item : request) {
    if (allowed.find(item.first) == allowed.end()) {
      return false;
    }
  }
  return true;
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
    if (!RequestFieldsAllowed(request, {"version", "op", "protocol"})) {
      return Error("invalid_request", "Unexpected helper request field.");
    }
    return HandleProbe(request);
  }
  if (op == "firewall.adblock_status") {
    if (!RequestFieldsAllowed(request, {"version", "op"})) {
      return Error("invalid_request", "Unexpected helper request field.");
    }
    return AdblockStatus();
  }
  if (StartsWith(op, "wireguard.")) {
    if (!RequestFieldsAllowed(request, {"version", "op", "config_path"})) {
      return Error("invalid_request", "Unexpected helper request field.");
    }
    return HandleWireGuard(op, request, peer_uid);
  }
  if (StartsWith(op, "openvpn.")) {
    if (!RequestFieldsAllowed(
            request,
            {"version", "op", "config_path", "pid_path", "log_path", "auth_path"})) {
      return Error("invalid_request", "Unexpected helper request field.");
    }
    return HandleOpenVpn(op, request, peer_uid);
  }
  if (StartsWith(op, "ikev2.")) {
    if (!RequestFieldsAllowed(request, {"version", "op", "config_path"})) {
      return Error("invalid_request", "Unexpected helper request field.");
    }
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
  const ParsedFields parsed = ParseFields(body);
  if (!parsed.valid) {
    response = Error("invalid_request", parsed.error);
  } else {
    response = HandleRequest(parsed.fields, peer.uid);
  }
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
    const struct timeval timeout = {5, 0};
    setsockopt(client_fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    setsockopt(client_fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
    HandleClient(client_fd);
    close(client_fd);
  }
}
