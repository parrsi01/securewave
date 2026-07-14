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
#include <ctime>
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
const char* kIkev2InterfaceName = "nm-xfrm-sw";
const char* kIkev2IfIdPath = "/run/securewave/ikev2-xfrm-if-id";
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

static bool ParseUint32Strict(const std::string& raw,
                              int base,
                              guint32* value) {
  const std::string input = Trim(raw);
  if (!value || input.empty() || input[0] == '+' || input[0] == '-') {
    return false;
  }
  char* end = nullptr;
  errno = 0;
  const unsigned long long parsed = strtoull(input.c_str(), &end, base);
  if (errno != 0 || end == input.c_str() || *end != '\0' ||
      parsed == 0 || parsed > UINT32_MAX) {
    return false;
  }
  *value = static_cast<guint32>(parsed);
  return true;
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

static const char* AllowlistedExecutablePath(const std::string& executable) {
  static const std::map<std::string, const char*> kExecutables = {
      {"/usr/local/libexec/securewave-wg-quick", "/usr/local/libexec/securewave-wg-quick"},
      {"ip", "/usr/sbin/ip"},
      {"ip6tables", "/usr/sbin/ip6tables"},
      {"ip6tables-restore", "/usr/sbin/ip6tables-restore"},
      {"ip6tables-save", "/usr/sbin/ip6tables-save"},
      {"iptables", "/usr/sbin/iptables"},
      {"iptables-restore", "/usr/sbin/iptables-restore"},
      {"iptables-save", "/usr/sbin/iptables-save"},
      {"nft", "/usr/sbin/nft"},
      {"nmcli", "/usr/bin/nmcli"},
      {"resolvectl", "/usr/bin/resolvectl"},
      {"setfacl", "/usr/bin/setfacl"},
      {"wg", "/usr/bin/wg"},
  };
  const auto it = kExecutables.find(executable);
  return it == kExecutables.end() ? nullptr : it->second;
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
  g_autoptr(GError) error = nullptr;
  g_autofree gchar* stdout_text = nullptr;
  g_autofree gchar* stderr_text = nullptr;
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
  guint32 installed = 0;
  if (!ParseUint32Strict(contents, 10, &installed)) {
    return 0;
  }
  return installed;
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
      "sh -c 'command -v iptables >/dev/null 2>&1 && iptables -I OUTPUT ! -o %i -m mark ! --mark $(wg show %i fwmark) -m addrtype ! --dst-type LOCAL -m comment --comment securewave-wireguard-ipv4-kill-switch-v1 -j REJECT'",
      "sh -c 'command -v ip6tables >/dev/null 2>&1 && ip6tables -I OUTPUT -d 2000::/3 -m mark ! --mark $(wg show %i fwmark) -m comment --comment securewave-wireguard-ipv6-block-v1 -j REJECT --reject-with icmp6-adm-prohibited'",
  };
  static const std::set<std::string> kAllowedPostDown = {
      "sh -c 'command -v iptables >/dev/null 2>&1 && iptables -D OUTPUT ! -o %i -m mark ! --mark $(wg show %i fwmark) -m addrtype ! --dst-type LOCAL -m comment --comment securewave-wireguard-ipv4-kill-switch-v1 -j REJECT || true'",
      "sh -c 'command -v ip6tables >/dev/null 2>&1 && ip6tables -D OUTPUT -d 2000::/3 -m mark ! --mark $(wg show %i fwmark) -m comment --comment securewave-wireguard-ipv6-block-v1 -j REJECT --reject-with icmp6-adm-prohibited || true'",
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
  bool saw_block_ipv6 = false;
  bool saw_ifconfig_ipv6 = false;
  bool saw_redirect_gateway = false;
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
    if (directive == "block-ipv6") {
      std::string extra;
      if (saw_block_ipv6 || (tokens >> extra)) {
        return false;
      }
      saw_block_ipv6 = true;
    }
    if (directive == "ifconfig-ipv6") {
      std::string local;
      std::string remote;
      std::string extra;
      if (saw_ifconfig_ipv6 || !(tokens >> local) || !(tokens >> remote) ||
          (tokens >> extra) ||
          local != "fd53:6563:7572:6577::2/64" ||
          remote != "fd53:6563:7572:6577::1") {
        return false;
      }
      saw_ifconfig_ipv6 = true;
    }
    if (directive == "redirect-gateway") {
      std::string first;
      std::string second;
      std::string extra;
      if (saw_redirect_gateway || !(tokens >> first) || !(tokens >> second) ||
          (tokens >> extra) || Lower(first) != "def1" ||
          Lower(second) != "ipv6") {
        return false;
      }
      saw_redirect_gateway = true;
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
                     saw_block_ipv6 && saw_ifconfig_ipv6 &&
                     saw_redirect_gateway && !parsed_dns.empty();
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

struct FullTunnelRouteEvidence {
  CommandResult ipv4;
  CommandResult ipv6;
  bool ipv4_via_interface = false;
  bool ipv6_via_interface = false;
};

static bool RouteOutputUsesInterface(const std::string& output,
                                     const std::string& interface) {
  std::istringstream lines(output);
  std::string line;
  while (std::getline(lines, line)) {
    std::istringstream tokens(line);
    std::string token;
    while (tokens >> token) {
      if (token != "dev") {
        continue;
      }
      std::string device;
      if ((tokens >> device) && device == interface) {
        return true;
      }
    }
  }
  return false;
}

static FullTunnelRouteEvidence ReadFullTunnelRouteEvidence(
    const std::string& interface) {
  FullTunnelRouteEvidence evidence;
  evidence.ipv4 =
      RunCommand({"ip", "-4", "route", "get", "1.1.1.1"});
  evidence.ipv6 = RunCommand(
      {"ip", "-6", "route", "get", "2606:4700:4700::1111"});
  evidence.ipv4_via_interface =
      evidence.ipv4.ok && RouteOutputUsesInterface(evidence.ipv4.out, interface);
  evidence.ipv6_via_interface =
      evidence.ipv6.ok && RouteOutputUsesInterface(evidence.ipv6.out, interface);
  return evidence;
}

static bool FullTunnelRoutesPresent(const FullTunnelRouteEvidence& evidence) {
  return evidence.ipv4_via_interface && evidence.ipv6_via_interface;
}

static bool OwnedTunnelRoutePresent(const FullTunnelRouteEvidence& evidence) {
  return evidence.ipv4_via_interface || evidence.ipv6_via_interface;
}

static bool WireGuardRouteExists() {
  return OwnedTunnelRoutePresent(
      ReadFullTunnelRouteEvidence(kWireGuardInterface));
}

static bool WireGuardFullTunnelRoutesPresent() {
  return FullTunnelRoutesPresent(
      ReadFullTunnelRouteEvidence(kWireGuardInterface));
}

static bool WireGuardPolicyRuleOutputPresent(const std::string& output) {
  return output.find("lookup 51820") != std::string::npos ||
         output.find("table 51820") != std::string::npos ||
         output.find("suppress_prefixlength 0") != std::string::npos;
}

struct WireGuardPolicyRuleEvidence {
  CommandResult ipv4;
  CommandResult ipv6;
  bool ipv4_present = false;
  bool ipv6_present = false;
};

static WireGuardPolicyRuleEvidence ReadWireGuardPolicyRuleEvidence() {
  WireGuardPolicyRuleEvidence evidence;
  evidence.ipv4 = RunCommand({"ip", "-4", "rule", "show"});
  evidence.ipv6 = RunCommand({"ip", "-6", "rule", "show"});
  evidence.ipv4_present =
      evidence.ipv4.ok && WireGuardPolicyRuleOutputPresent(evidence.ipv4.out);
  evidence.ipv6_present =
      evidence.ipv6.ok && WireGuardPolicyRuleOutputPresent(evidence.ipv6.out);
  return evidence;
}

static bool WireGuardPolicyRulesExist() {
  const WireGuardPolicyRuleEvidence evidence =
      ReadWireGuardPolicyRuleEvidence();
  return !evidence.ipv4.ok || !evidence.ipv6.ok ||
         evidence.ipv4_present || evidence.ipv6_present;
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

static bool WireGuardPolicyRoutesPresentForBothFamilies() {
  return WireGuardPolicyRoutesExistForFamily("-4") &&
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

static std::vector<std::string> IptablesSaveTokens(std::string line) {
  std::istringstream stream(Trim(line));
  std::vector<std::string> tokens;
  std::string token;
  while (stream >> token) {
    if (token.size() >= 2 && token.front() == '"' && token.back() == '"') {
      token = token.substr(1, token.size() - 2);
    }
    tokens.push_back(token);
  }
  return tokens;
}

static bool WireGuardMarkToken(const std::string& token) {
  return token == "0xca6c" || token == "0xca6c/0xffffffff" ||
         token == "51820" || token == "51820/0xffffffff";
}

static bool WireGuardIpv4KillSwitchPresent(const std::string& output) {
  std::istringstream lines(output);
  std::string line;
  while (std::getline(lines, line)) {
    const std::vector<std::string> values = IptablesSaveTokens(line);
    if (values.size() == 21 && values[0] == "-A" &&
        values[1] == "OUTPUT" && values[2] == "!" && values[3] == "-o" &&
        values[4] == kWireGuardInterface && values[5] == "-m" &&
        values[6] == "mark" && values[7] == "!" &&
        values[8] == "--mark" && WireGuardMarkToken(values[9]) &&
        values[10] == "-m" && values[11] == "addrtype" &&
        values[12] == "!" && values[13] == "--dst-type" &&
        values[14] == "LOCAL" && values[15] == "-m" &&
        values[16] == "comment" && values[17] == "--comment" &&
        values[18] == "securewave-wireguard-ipv4-kill-switch-v1" &&
        values[19] == "-j" && values[20] == "REJECT") {
      return true;
    }
  }
  return false;
}

static bool WireGuardIpv6BlockPresent(const std::string& output) {
  std::istringstream lines(output);
  std::string line;
  while (std::getline(lines, line)) {
    const std::vector<std::string> values = IptablesSaveTokens(line);
    if (values.size() == 17 && values[0] == "-A" &&
        values[1] == "OUTPUT" && values[2] == "-d" &&
        values[3] == "2000::/3" && values[4] == "-m" &&
        values[5] == "mark" && values[6] == "!" &&
        values[7] == "--mark" && WireGuardMarkToken(values[8]) &&
        values[9] == "-m" && values[10] == "comment" &&
        values[11] == "--comment" &&
        values[12] == "securewave-wireguard-ipv6-block-v1" &&
        values[13] == "-j" && values[14] == "REJECT" &&
        values[15] == "--reject-with" &&
        values[16] == "icmp6-adm-prohibited") {
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
  bool ipv4_kill_switch_present = false;
  bool ipv6_block_present = false;
};

static WireGuardFirewallEvidence ReadWireGuardFirewallEvidence() {
  const CommandResult nft = RunCommand({"nft", "list", "tables"});
  const CommandResult iptables = RunCommand({"iptables-save"});
  const CommandResult ip6tables = RunCommand({"ip6tables-save"});
  WireGuardFirewallEvidence evidence;
  evidence.inspection_ok = nft.ok && iptables.ok && ip6tables.ok;
  evidence.nft_table_present = WgQuickNftTablePresent(nft.out);
  evidence.ipv4_kill_switch_present =
      WireGuardIpv4KillSwitchPresent(iptables.out);
  evidence.ipv6_block_present = WireGuardIpv6BlockPresent(ip6tables.out);
  evidence.iptables_rule_present = WgQuickIptablesRulePresent(iptables.out) ||
                                    evidence.ipv4_kill_switch_present;
  evidence.ip6tables_rule_present = WgQuickIptablesRulePresent(ip6tables.out) ||
                                     evidence.ipv6_block_present;
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
  return OwnedTunnelRoutePresent(ReadFullTunnelRouteEvidence(kOpenVpnInterface));
}

static bool OpenVpnFullTunnelRoutesPresent() {
  return FullTunnelRoutesPresent(ReadFullTunnelRouteEvidence(kOpenVpnInterface));
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

static bool Ikev2Ipv6BlockModeConfigured(const std::string& contents) {
  const std::string expected = "# ipv6_mode = block";
  bool found = false;
  std::istringstream stream(contents);
  std::string line;
  while (std::getline(stream, line)) {
    if (!line.empty() && line.back() == '\r') {
      line.pop_back();
    }
    if (Trim(line) != expected) {
      continue;
    }
    if (found) {
      return false;
    }
    found = true;
  }
  return found;
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
         OpenVpnFullTunnelRoutesPresent();
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
  bool interface_name_configured = false;
};

static Ikev2ConnectionEvidence ReadIkev2ConnectionEvidence() {
  const CommandResult saved = RunCommand(
      {"nmcli", "-t", "-f", "NAME,TYPE", "connection", "show"});
  const CommandResult active = RunCommand({
      "nmcli", "-t", "-f", "NAME,TYPE", "connection", "show", "--active"});
  Ikev2ConnectionEvidence evidence;
  evidence.connection_present = NmcliListHasExactIkev2(saved.out);
  evidence.active = NmcliListHasExactIkev2(active.out);
  bool interface_inspection_ok = true;
  if (evidence.connection_present) {
    const CommandResult interface = RunCommand({
        "nmcli", "-g", "connection.interface-name", "connection", "show",
        "id", kIkev2ConnectionName});
    interface_inspection_ok = interface.ok;
    evidence.interface_name_configured =
        interface.ok && Trim(interface.out) == kIkev2InterfaceName;
  }
  evidence.inspection_ok = saved.ok && active.ok && interface_inspection_ok;
  return evidence;
}

struct Ikev2NetworkEvidence {
  bool inspected = false;
  bool dns_present = false;
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
    }
  }
  return evidence;
}

static Ikev2NetworkEvidence ReadIkev2NetworkEvidence() {
  CommandResult result = RunCommand({
      "nmcli", "-t", "-f", "IP4.DNS,IP6.DNS",
      "connection", "show", kIkev2ConnectionName});
  if (!result.ok) {
    return Ikev2NetworkEvidence();
  }
  return ParseIkev2NetworkEvidence(result.out);
}

static std::string LineTokenAfter(const std::string& line,
                                  const std::string& key) {
  std::istringstream tokens(line);
  std::string token;
  while (tokens >> token) {
    if (token == key && tokens >> token) {
      return token;
    }
  }
  return "";
}

static bool ParseReqid(const std::string& raw, guint32* reqid) {
  const std::string::size_type detail = raw.find('(');
  return ParseUint32Strict(raw.substr(0, detail), 0, reqid);
}

static bool ParseOutputMark(const std::string& raw, bool* expected) {
  const std::string::size_type slash = raw.find('/');
  guint32 mark = 0;
  if (!ParseUint32Strict(raw.substr(0, slash), 0, &mark)) {
    return false;
  }
  guint32 mask = UINT32_MAX;
  if (slash != std::string::npos &&
      !ParseUint32Strict(raw.substr(slash + 1), 0, &mask)) {
    return false;
  }
  *expected = mark == 0xdc && mask == UINT32_MAX;
  return true;
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
  *bytes = g_ascii_strtoull(
      line.substr(start, marker_pos - start).c_str(), nullptr, 10);
  return true;
}

static std::vector<std::string> SplitXfrmRecords(const std::string& output) {
  std::vector<std::string> records;
  std::istringstream stream(output);
  std::string line;
  std::string record;
  while (std::getline(stream, line)) {
    const bool top_level = !line.empty() &&
                           !g_ascii_isspace(
                               static_cast<unsigned char>(line.front()));
    if (top_level && StartsWith(Trim(line), "src ")) {
      if (!record.empty()) {
        records.push_back(record);
      }
      record.clear();
    }
    if (!record.empty() ||
        (top_level && StartsWith(Trim(line), "src "))) {
      record += line;
      record += '\n';
    }
  }
  if (!record.empty()) {
    records.push_back(record);
  }
  return records;
}

struct XfrmStateRecord {
  std::string src;
  std::string dst;
  guint32 if_id = 0;
  guint32 reqid = 0;
  bool if_id_present = false;
  bool reqid_present = false;
  bool esp = false;
  bool tunnel = false;
  bool output_mark_present = false;
  bool output_mark_safe = false;
  bool bytes_present = false;
  guint64 bytes = 0;
};

struct XfrmPolicyRecord {
  std::string direction;
  std::string template_src;
  std::string template_dst;
  guint32 if_id = 0;
  guint32 reqid = 0;
  bool if_id_present = false;
  bool reqid_present = false;
  bool template_present = false;
  bool esp = false;
  bool tunnel = false;
};

static XfrmStateRecord ParseXfrmStateRecord(const std::string& input,
                                            bool* parse_ok) {
  XfrmStateRecord state;
  std::istringstream stream(input);
  std::string line;
  bool first = true;
  while (std::getline(stream, line)) {
    line = Trim(line);
    if (first) {
      state.src = LineTokenAfter(line, "src");
      state.dst = LineTokenAfter(line, "dst");
      if (state.src.empty() || state.dst.empty()) {
        *parse_ok = false;
      }
      first = false;
      continue;
    }
    if (LineTokenAfter(line, "proto") == "esp") {
      state.esp = true;
      const std::string reqid = LineTokenAfter(line, "reqid");
      if (!reqid.empty()) {
        state.reqid_present = ParseReqid(reqid, &state.reqid);
        *parse_ok = *parse_ok && state.reqid_present;
      }
      state.tunnel = LineTokenAfter(line, "mode") == "tunnel";
    }
    const std::string if_id = LineTokenAfter(line, "if_id");
    if (!if_id.empty()) {
      guint32 parsed = 0;
      if (!ParseUint32Strict(if_id, 0, &parsed) ||
          (state.if_id_present && state.if_id != parsed)) {
        *parse_ok = false;
      } else {
        state.if_id = parsed;
        state.if_id_present = true;
      }
    }
    const std::string output_mark = LineTokenAfter(line, "output-mark");
    if (!output_mark.empty()) {
      state.output_mark_present = true;
      if (!ParseOutputMark(output_mark, &state.output_mark_safe)) {
        *parse_ok = false;
      }
    }
    guint64 bytes = 0;
    if (ParseLifetimeBytes(line, &bytes)) {
      state.bytes = bytes;
      state.bytes_present = true;
    }
  }
  return state;
}

static XfrmPolicyRecord ParseXfrmPolicyRecord(const std::string& input,
                                              bool* parse_ok) {
  XfrmPolicyRecord policy;
  std::istringstream stream(input);
  std::string line;
  bool in_template = false;
  while (std::getline(stream, line)) {
    line = Trim(line);
    const std::string direction = LineTokenAfter(line, "dir");
    if (!direction.empty()) {
      policy.direction = direction;
    }
    if (StartsWith(line, "tmpl ")) {
      if (policy.template_present) {
        *parse_ok = false;
      }
      policy.template_present = true;
      in_template = true;
      policy.template_src = LineTokenAfter(line, "src");
      policy.template_dst = LineTokenAfter(line, "dst");
      if (policy.template_src.empty() || policy.template_dst.empty()) {
        *parse_ok = false;
      }
    }
    if (in_template && LineTokenAfter(line, "proto") == "esp") {
      policy.esp = true;
      const std::string reqid = LineTokenAfter(line, "reqid");
      if (!reqid.empty()) {
        policy.reqid_present = ParseReqid(reqid, &policy.reqid);
        *parse_ok = *parse_ok && policy.reqid_present;
      }
      policy.tunnel = LineTokenAfter(line, "mode") == "tunnel";
    }
    const std::string if_id = LineTokenAfter(line, "if_id");
    if (!if_id.empty()) {
      guint32 parsed = 0;
      if (!ParseUint32Strict(if_id, 0, &parsed) ||
          (policy.if_id_present && policy.if_id != parsed)) {
        *parse_ok = false;
      } else {
        policy.if_id = parsed;
        policy.if_id_present = true;
      }
    }
  }
  return policy;
}

static std::vector<XfrmStateRecord> ParseXfrmStateRecords(
    const std::string& output,
    bool* parse_ok) {
  *parse_ok = true;
  std::vector<XfrmStateRecord> states;
  for (const std::string& record : SplitXfrmRecords(output)) {
    states.push_back(ParseXfrmStateRecord(record, parse_ok));
  }
  return states;
}

static std::vector<XfrmPolicyRecord> ParseXfrmPolicyRecords(
    const std::string& output,
    bool* parse_ok) {
  *parse_ok = true;
  std::vector<XfrmPolicyRecord> policies;
  for (const std::string& record : SplitXfrmRecords(output)) {
    policies.push_back(ParseXfrmPolicyRecord(record, parse_ok));
  }
  return policies;
}

static bool XfrmStateMatchesPolicy(const XfrmStateRecord& state,
                                   const XfrmPolicyRecord& policy,
                                   guint32 if_id) {
  return state.if_id_present && state.if_id == if_id && state.esp &&
         state.tunnel && state.reqid_present &&
         policy.if_id_present && policy.if_id == if_id && policy.esp &&
         policy.tunnel && policy.reqid_present &&
         state.reqid == policy.reqid && state.src == policy.template_src &&
         state.dst == policy.template_dst;
}

static bool OwnedXfrmPairPresent(
    const std::vector<XfrmStateRecord>& states,
    const std::vector<XfrmPolicyRecord>& policies,
    guint32 if_id) {
  for (const XfrmPolicyRecord& outbound : policies) {
    if (outbound.direction != "out") {
      continue;
    }
    for (const XfrmStateRecord& outbound_state : states) {
      if (!XfrmStateMatchesPolicy(outbound_state, outbound, if_id) ||
          !outbound_state.output_mark_present ||
          !outbound_state.output_mark_safe) {
        continue;
      }
      for (const XfrmPolicyRecord& inbound : policies) {
        if (inbound.direction != "in" ||
            inbound.reqid != outbound.reqid ||
            inbound.template_src != outbound.template_dst ||
            inbound.template_dst != outbound.template_src) {
          continue;
        }
        for (const XfrmStateRecord& inbound_state : states) {
          if (XfrmStateMatchesPolicy(inbound_state, inbound, if_id)) {
            return true;
          }
        }
      }
    }
  }
  return false;
}

static bool OwnedXfrmStatePresent(
    const std::vector<XfrmStateRecord>& states,
    guint32 if_id) {
  return std::any_of(states.begin(), states.end(), [if_id](const auto& state) {
    return state.if_id_present && state.if_id == if_id;
  });
}

static bool OwnedXfrmEspPresent(
    const std::vector<XfrmStateRecord>& states,
    guint32 if_id) {
  return std::any_of(states.begin(), states.end(), [if_id](const auto& state) {
    return state.if_id_present && state.if_id == if_id && state.esp;
  });
}

static bool OwnedXfrmPolicyPresent(
    const std::vector<XfrmPolicyRecord>& policies,
    guint32 if_id) {
  return std::any_of(
      policies.begin(), policies.end(), [if_id](const auto& policy) {
        return policy.if_id_present && policy.if_id == if_id;
      });
}

static CommandResult ReadXfrmState() {
  return RunCommand({"ip", "-s", "xfrm", "state"});
}

static CommandResult ReadXfrmPolicy() {
  return RunCommand({"ip", "xfrm", "policy"});
}

struct PersistedIkev2IfId {
  bool inspection_ok = false;
  bool present = false;
  bool valid = false;
  guint32 if_id = 0;
};

static PersistedIkev2IfId ReadPersistedIkev2IfId() {
  PersistedIkev2IfId evidence;
  struct stat st {};
  if (lstat(kIkev2IfIdPath, &st) != 0) {
    evidence.inspection_ok = errno == ENOENT;
    evidence.valid = evidence.inspection_ok;
    return evidence;
  }
  evidence.present = true;
  if (!S_ISREG(st.st_mode) || S_ISLNK(st.st_mode) || st.st_uid != 0 ||
      (st.st_mode & (S_IWGRP | S_IWOTH)) != 0) {
    evidence.inspection_ok = true;
    return evidence;
  }
  std::ifstream input(kIkev2IfIdPath);
  std::ostringstream contents;
  contents << input.rdbuf();
  evidence.inspection_ok = !input.bad();
  evidence.valid = evidence.inspection_ok &&
                   ParseUint32Strict(contents.str(), 0, &evidence.if_id);
  return evidence;
}

static bool PersistIkev2IfId(guint32 if_id) {
  const PersistedIkev2IfId existing = ReadPersistedIkev2IfId();
  if (!existing.inspection_ok || (existing.present && !existing.valid)) {
    return false;
  }
  if (existing.present) {
    return existing.if_id == if_id;
  }
  const std::string contents = std::to_string(if_id) + "\n";
  GError* error = nullptr;
  const bool written = g_file_set_contents(
      kIkev2IfIdPath, contents.c_str(), contents.size(), &error);
  if (error) {
    g_error_free(error);
  }
  if (!written || chmod(kIkev2IfIdPath, 0600) != 0) {
    return false;
  }
  const PersistedIkev2IfId verified = ReadPersistedIkev2IfId();
  return verified.inspection_ok && verified.present && verified.valid &&
         verified.if_id == if_id;
}

static bool ClearPersistedIkev2IfId() {
  return unlink(kIkev2IfIdPath) == 0 || errno == ENOENT;
}

struct Ikev2InterfaceEvidence {
  bool inspection_ok = false;
  bool present = false;
  bool xfrm = false;
  bool if_id_present = false;
  bool if_id_persisted = false;
  guint32 if_id = 0;
};

static bool ParseXfrmInterfaceId(const std::string& output,
                                 guint32* if_id) {
  std::istringstream tokens(output);
  std::string token;
  bool xfrm = false;
  guint matches = 0;
  guint32 parsed = 0;
  while (tokens >> token) {
    if (token == "xfrm") {
      xfrm = true;
      continue;
    }
    if (!xfrm || token != "if_id" || !(tokens >> token)) {
      continue;
    }
    guint32 candidate = 0;
    if (!ParseUint32Strict(token, 0, &candidate) ||
        (matches > 0 && candidate != parsed)) {
      return false;
    }
    parsed = candidate;
    matches++;
  }
  if (matches != 1) {
    return false;
  }
  *if_id = parsed;
  return true;
}

static Ikev2InterfaceEvidence ReadIkev2InterfaceEvidence() {
  const CommandResult link = RunCommand(
      {"ip", "-d", "-o", "link", "show", "dev", kIkev2InterfaceName});
  Ikev2InterfaceEvidence evidence;
  if (!link.ok) {
    const std::string diagnostic = link.out + "\n" + link.err;
    evidence.inspection_ok = link.spawned &&
        (diagnostic.find("does not exist") != std::string::npos ||
         diagnostic.find("Cannot find device") != std::string::npos);
    return evidence;
  }
  evidence.inspection_ok = true;
  evidence.present = true;
  evidence.if_id_present = ParseXfrmInterfaceId(link.out, &evidence.if_id);
  evidence.xfrm = evidence.if_id_present;
  if (evidence.if_id_present) {
    evidence.if_id_persisted = PersistIkev2IfId(evidence.if_id);
    evidence.inspection_ok = evidence.if_id_persisted;
  }
  return evidence;
}

static CommandResult ReadIkev2Routes(const char* family) {
  return RunCommand(
      {"ip", family, "-o", "-N", "route", "show", "table", "all"});
}

static bool RouteTargetsTable210(const std::string& line) {
  return LineTokenAfter(line, "table") == "210";
}

static std::string RouteDevice(const std::string& line) {
  return LineTokenAfter(line, "dev");
}

struct Ikev2RouteFamilyEvidence {
  bool owned_route_present = false;
  bool full_route_present = false;
  bool conflicting_full_route = false;
};

static Ikev2RouteFamilyEvidence ParseIkev2RouteFamilyEvidence(
    const std::string& output,
    bool ipv6) {
  Ikev2RouteFamilyEvidence evidence;
  bool owned_low_half = false;
  bool owned_high_half = false;
  std::istringstream stream(output);
  std::string line;
  while (std::getline(stream, line)) {
    line = Trim(line);
    if (!RouteTargetsTable210(line)) {
      continue;
    }
    std::istringstream tokens(line);
    std::string prefix;
    tokens >> prefix;
    const std::string device = RouteDevice(line);
    const bool owned = device == kIkev2InterfaceName;
    evidence.owned_route_present = evidence.owned_route_present || owned;
    const bool is_default = prefix == "default" ||
                            prefix == (ipv6 ? "::/0" : "0.0.0.0/0");
    const bool is_low_half = prefix == (ipv6 ? "::/1" : "0.0.0.0/1");
    const bool is_high_half =
        prefix == (ipv6 ? "8000::/1" : "128.0.0.0/1");
    if ((is_default || is_low_half || is_high_half) && !owned) {
      evidence.conflicting_full_route = true;
    }
    if (owned && is_default) {
      evidence.full_route_present = true;
    }
    owned_low_half = owned_low_half || (owned && is_low_half);
    owned_high_half = owned_high_half || (owned && is_high_half);
  }
  evidence.full_route_present =
      evidence.full_route_present || (owned_low_half && owned_high_half);
  return evidence;
}

struct Ikev2RouteEvidence {
  CommandResult routes4;
  CommandResult routes6;
  Ikev2RouteFamilyEvidence ipv4;
  Ikev2RouteFamilyEvidence ipv6;
  bool inspection_ok = false;
  bool owned_route_present = false;
  bool full_tunnel_routes_present = false;
  bool conflicting_full_route = false;
};

static Ikev2RouteEvidence ReadIkev2RouteEvidence() {
  Ikev2RouteEvidence evidence;
  evidence.routes4 = ReadIkev2Routes("-4");
  evidence.routes6 = ReadIkev2Routes("-6");
  evidence.inspection_ok = evidence.routes4.ok && evidence.routes6.ok;
  if (!evidence.inspection_ok) {
    return evidence;
  }
  evidence.ipv4 = ParseIkev2RouteFamilyEvidence(evidence.routes4.out, false);
  evidence.ipv6 = ParseIkev2RouteFamilyEvidence(evidence.routes6.out, true);
  evidence.owned_route_present = evidence.ipv4.owned_route_present ||
                                 evidence.ipv6.owned_route_present;
  // The current Linux IKEv2 service is explicitly IPv4-data-plane only.
  // Public IPv6 is blocked by an owned OUTPUT rule while the tunnel is up.
  evidence.full_tunnel_routes_present = evidence.ipv4.full_route_present;
  evidence.conflicting_full_route = evidence.ipv4.conflicting_full_route ||
                                    evidence.ipv6.conflicting_full_route;
  return evidence;
}

static CommandResult ReadIpRules(const char* family) {
  return RunCommand({"ip", family, "-N", "rule", "show"});
}

struct Ikev2Ipv6BlockEvidence {
  CommandResult inspection;
  bool present = false;
};

static bool Ikev2MarkToken(const std::string& token) {
  return token == "0xdc" || token == "0xdc/0xffffffff" ||
         token == "220" || token == "220/0xffffffff";
}

static bool Ikev2Ipv6BlockRulePresent(const std::string& output) {
  std::istringstream lines(output);
  std::string line;
  while (std::getline(lines, line)) {
    const std::vector<std::string> values = IptablesSaveTokens(line);
    if (values.size() == 17 && values[0] == "-A" &&
        values[1] == "OUTPUT" && values[2] == "-d" &&
        values[3] == "2000::/3" && values[4] == "-m" &&
        values[5] == "mark" && values[6] == "!" &&
        values[7] == "--mark" && Ikev2MarkToken(values[8]) &&
        values[9] == "-m" && values[10] == "comment" &&
        values[11] == "--comment" &&
        values[12] == "securewave-ikev2-ipv6-block-v1" &&
        values[13] == "-j" && values[14] == "REJECT" &&
        values[15] == "--reject-with" &&
        values[16] == "icmp6-adm-prohibited") {
      return true;
    }
  }
  return false;
}

static Ikev2Ipv6BlockEvidence ReadIkev2Ipv6BlockEvidence() {
  Ikev2Ipv6BlockEvidence evidence;
  evidence.inspection = RunCommand({"ip6tables-save"});
  evidence.present = evidence.inspection.ok &&
                     Ikev2Ipv6BlockRulePresent(evidence.inspection.out);
  return evidence;
}

static bool Ikev2HasUnqualifiedPref210Rule(const std::string& output) {
  std::istringstream stream(output);
  std::string line;
  while (std::getline(stream, line)) {
    line = Trim(line);
    if (line.rfind("210:", 0) != 0) {
      continue;
    }
    if (line.find("from all") != std::string::npos &&
        line.find("lookup 210") != std::string::npos &&
        line.find("fwmark") == std::string::npos) {
      return true;
    }
  }
  return false;
}

static bool Ikev2RuleTargetsTable210(const std::string& line) {
  std::istringstream tokens(line);
  std::string token;
  while (tokens >> token) {
    if (token != "lookup" && token != "table") {
      continue;
    }
    if (tokens >> token && token == "210") {
      return true;
    }
  }
  return false;
}

static bool Ikev2RuleIsExpectedSafeRule(const std::string& input) {
  std::istringstream tokens(input);
  std::vector<std::string> values;
  std::string token;
  while (tokens >> token) {
    values.push_back(token);
  }
  if (values.size() != 8 || values[0] != "210:" ||
      (values[5] != "0xdc" && values[5] != "0xdc/0xffffffff") ||
      (values[6] != "lookup" && values[6] != "table") ||
      values[7] != "210") {
    return false;
  }
  return (values[1] == "not" && values[2] == "from" &&
          values[3] == "all" && values[4] == "fwmark") ||
         (values[1] == "from" && values[2] == "all" &&
          values[3] == "not" && values[4] == "fwmark");
}

struct Ikev2RuleEvidence {
  guint expected_safe_count = 0;
  bool unexpected_table_210_rule = false;
};

static Ikev2RuleEvidence ParseIkev2RuleEvidence(const std::string& output) {
  Ikev2RuleEvidence evidence;
  std::istringstream stream(output);
  std::string line;
  while (std::getline(stream, line)) {
    line = Trim(line);
    if (!Ikev2RuleTargetsTable210(line)) {
      continue;
    }
    if (Ikev2RuleIsExpectedSafeRule(line)) {
      evidence.expected_safe_count++;
    } else {
      evidence.unexpected_table_210_rule = true;
    }
  }
  return evidence;
}

static bool Ikev2RuleEvidenceSafe(const Ikev2RuleEvidence& evidence) {
  return evidence.expected_safe_count == 1 &&
         !evidence.unexpected_table_210_rule;
}

static bool Ikev2RuleEvidenceIdleSafe(const Ikev2RuleEvidence& rules4,
                                      const Ikev2RuleEvidence& rules6) {
  return !rules4.unexpected_table_210_rule &&
         !rules6.unexpected_table_210_rule &&
         rules4.expected_safe_count <= 1 &&
         rules4.expected_safe_count == rules6.expected_safe_count;
}

struct Ikev2RuntimeSnapshot {
  CommandResult xfrm_state;
  CommandResult xfrm_policy;
  CommandResult rules4;
  CommandResult rules6;
  Ikev2ConnectionEvidence connection;
  Ikev2NetworkEvidence network;
  Ikev2InterfaceEvidence interface;
  PersistedIkev2IfId persisted_if_id;
  Ikev2RouteEvidence routes;
  Ikev2Ipv6BlockEvidence ipv6_block;
  std::vector<XfrmStateRecord> states;
  std::vector<XfrmPolicyRecord> policies;
  guint32 owned_if_id = 0;
  bool owned_if_id_present = false;
  bool ownership_inspection_ok = false;
  bool xfrm_state_inspection_ok = false;
  bool xfrm_policy_inspection_ok = false;
  bool owned_xfrm_state_present = false;
  bool owned_xfrm_esp_present = false;
  bool owned_xfrm_policy_present = false;
  bool owned_xfrm_pair_present = false;
  bool routing_loop_rule_present = false;
  bool routing_rules_safe = false;
  bool routing_rules_idle_safe = false;
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
  snapshot.interface = ReadIkev2InterfaceEvidence();
  snapshot.persisted_if_id = ReadPersistedIkev2IfId();
  snapshot.routes = ReadIkev2RouteEvidence();
  snapshot.ipv6_block = ReadIkev2Ipv6BlockEvidence();
  snapshot.ownership_inspection_ok =
      snapshot.interface.inspection_ok &&
      snapshot.persisted_if_id.inspection_ok &&
      (!snapshot.persisted_if_id.present || snapshot.persisted_if_id.valid);
  if (snapshot.interface.if_id_present) {
    snapshot.owned_if_id = snapshot.interface.if_id;
    snapshot.owned_if_id_present = true;
    snapshot.ownership_inspection_ok =
        snapshot.ownership_inspection_ok &&
        snapshot.persisted_if_id.present &&
        snapshot.persisted_if_id.valid &&
        snapshot.persisted_if_id.if_id == snapshot.interface.if_id;
  } else if (snapshot.persisted_if_id.present &&
             snapshot.persisted_if_id.valid) {
    snapshot.owned_if_id = snapshot.persisted_if_id.if_id;
    snapshot.owned_if_id_present = true;
  }
  bool state_parse_ok = false;
  bool policy_parse_ok = false;
  snapshot.states = ParseXfrmStateRecords(snapshot.xfrm_state.out,
                                           &state_parse_ok);
  snapshot.policies = ParseXfrmPolicyRecords(snapshot.xfrm_policy.out,
                                              &policy_parse_ok);
  snapshot.xfrm_state_inspection_ok = snapshot.xfrm_state.ok &&
                                      state_parse_ok &&
                                      snapshot.ownership_inspection_ok;
  snapshot.xfrm_policy_inspection_ok = snapshot.xfrm_policy.ok &&
                                       policy_parse_ok &&
                                       snapshot.ownership_inspection_ok;
  if (snapshot.owned_if_id_present) {
    snapshot.owned_xfrm_state_present =
        OwnedXfrmStatePresent(snapshot.states, snapshot.owned_if_id);
    snapshot.owned_xfrm_esp_present =
        OwnedXfrmEspPresent(snapshot.states, snapshot.owned_if_id);
    snapshot.owned_xfrm_policy_present =
        OwnedXfrmPolicyPresent(snapshot.policies, snapshot.owned_if_id);
    snapshot.owned_xfrm_pair_present =
        OwnedXfrmPairPresent(
            snapshot.states, snapshot.policies, snapshot.owned_if_id);
  }
  const Ikev2RuleEvidence rules4 =
      ParseIkev2RuleEvidence(snapshot.rules4.out);
  const Ikev2RuleEvidence rules6 =
      ParseIkev2RuleEvidence(snapshot.rules6.out);
  snapshot.routing_loop_rule_present =
      (snapshot.rules4.ok &&
       Ikev2HasUnqualifiedPref210Rule(snapshot.rules4.out)) ||
      (snapshot.rules6.ok &&
       Ikev2HasUnqualifiedPref210Rule(snapshot.rules6.out)) ||
      rules4.unexpected_table_210_rule ||
      rules6.unexpected_table_210_rule ||
      rules4.expected_safe_count > 1 ||
      rules6.expected_safe_count > 1;
  snapshot.routing_rules_safe =
      snapshot.rules4.ok && snapshot.rules6.ok &&
      Ikev2RuleEvidenceSafe(rules4) && Ikev2RuleEvidenceSafe(rules6);
  snapshot.routing_rules_idle_safe =
      snapshot.rules4.ok && snapshot.rules6.ok &&
      Ikev2RuleEvidenceIdleSafe(rules4, rules6);
  snapshot.connected =
      snapshot.connection.inspection_ok &&
      snapshot.connection.connection_present &&
      snapshot.connection.active &&
      snapshot.connection.interface_name_configured &&
      snapshot.interface.inspection_ok &&
      snapshot.interface.present &&
      snapshot.interface.xfrm &&
      snapshot.interface.if_id_present &&
      snapshot.interface.if_id_persisted &&
      snapshot.network.inspected &&
      snapshot.network.dns_present &&
      snapshot.routes.inspection_ok &&
      snapshot.routes.full_tunnel_routes_present &&
      !snapshot.routes.conflicting_full_route &&
      snapshot.ipv6_block.inspection.ok &&
      snapshot.ipv6_block.present &&
      snapshot.xfrm_state_inspection_ok &&
      snapshot.xfrm_policy_inspection_ok &&
      snapshot.owned_xfrm_pair_present &&
      snapshot.rules4.ok &&
      snapshot.rules6.ok &&
      snapshot.routing_rules_safe &&
      !snapshot.routing_loop_rule_present;
  return snapshot;
}

static bool Ikev2RuntimeEvidence() {
  return ReadIkev2RuntimeSnapshot().connected;
}

static bool Ikev2DisconnectedStateClean(bool connection_inspection_ok,
                                        bool connection_present,
                                        bool nm_active,
                                        bool interface_inspection_ok,
                                        bool interface_present,
                                        bool state_inspection_ok,
                                        bool state_present,
                                        bool policy_inspection_ok,
                                        bool policy_present,
                                        bool route_inspection_ok,
                                        bool route_present,
                                        bool ipv6_block_inspection_ok,
                                        bool ipv6_block_present,
                                        bool rule_inspection_ok,
                                        bool rules_idle_safe) {
  return connection_inspection_ok &&
         !connection_present &&
         !nm_active &&
         interface_inspection_ok &&
         !interface_present &&
         state_inspection_ok &&
         !state_present &&
         policy_inspection_ok &&
         !policy_present &&
         route_inspection_ok &&
         !route_present &&
         ipv6_block_inspection_ok &&
         !ipv6_block_present &&
         rule_inspection_ok &&
         rules_idle_safe;
}

static bool WaitIkev2Stopped() {
  for (guint i = 0; i < 20; i++) {
    const Ikev2RuntimeSnapshot snapshot = ReadIkev2RuntimeSnapshot();
    if (Ikev2DisconnectedStateClean(
            snapshot.connection.inspection_ok,
            snapshot.connection.connection_present,
            snapshot.connection.active,
            snapshot.interface.inspection_ok,
            snapshot.interface.present,
            snapshot.xfrm_state_inspection_ok,
            snapshot.owned_xfrm_state_present,
            snapshot.xfrm_policy_inspection_ok,
            snapshot.owned_xfrm_policy_present,
            snapshot.routes.inspection_ok,
            snapshot.routes.owned_route_present,
            snapshot.ipv6_block.inspection.ok,
            snapshot.ipv6_block.present,
            snapshot.rules4.ok && snapshot.rules6.ok,
            snapshot.routing_rules_idle_safe)) {
      return ClearPersistedIkev2IfId();
    }
    g_usleep(500000);
  }
  const Ikev2RuntimeSnapshot snapshot = ReadIkev2RuntimeSnapshot();
  return Ikev2DisconnectedStateClean(
      snapshot.connection.inspection_ok,
      snapshot.connection.connection_present,
      snapshot.connection.active,
      snapshot.interface.inspection_ok,
      snapshot.interface.present,
      snapshot.xfrm_state_inspection_ok,
      snapshot.owned_xfrm_state_present,
      snapshot.xfrm_policy_inspection_ok,
      snapshot.owned_xfrm_policy_present,
      snapshot.routes.inspection_ok,
      snapshot.routes.owned_route_present,
      snapshot.ipv6_block.inspection.ok,
      snapshot.ipv6_block.present,
      snapshot.rules4.ok && snapshot.rules6.ok,
      snapshot.routing_rules_idle_safe) &&
      ClearPersistedIkev2IfId();
}

static bool ParseOwnedXfrmCounters(
    const std::vector<XfrmStateRecord>& states,
    const std::vector<XfrmPolicyRecord>& policies,
    guint32 if_id,
    guint64* rx,
    guint64* tx) {
  *rx = 0;
  *tx = 0;
  if (!OwnedXfrmPairPresent(states, policies, if_id)) {
    return false;
  }
  guint inbound_states = 0;
  guint outbound_states = 0;
  for (const XfrmStateRecord& state : states) {
    if (!state.bytes_present || !state.if_id_present || state.if_id != if_id) {
      continue;
    }
    bool inbound = false;
    bool outbound = false;
    for (const XfrmPolicyRecord& policy : policies) {
      if (!XfrmStateMatchesPolicy(state, policy, if_id)) {
        continue;
      }
      if (policy.direction == "in") {
        inbound = true;
      } else if (policy.direction == "out" &&
                 state.output_mark_present && state.output_mark_safe) {
        outbound = true;
      }
    }
    if (inbound) {
      *rx += state.bytes;
      inbound_states++;
    }
    if (outbound) {
      *tx += state.bytes;
      outbound_states++;
    }
  }
  return inbound_states > 0 && outbound_states > 0;
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

static bool WireGuardHandshakeEvidence(bool* inspection_ok) {
  if (inspection_ok) {
    *inspection_ok = true;
  }
  CommandResult result = RunCommand(
      {"wg", "show", kWireGuardInterface, "latest-handshakes"});
  if (!result.ok) {
    if (inspection_ok) {
      *inspection_ok = false;
    }
    return false;
  }

  const guint64 now = static_cast<guint64>(std::time(nullptr));
  std::istringstream lines(result.out);
  std::string public_key;
  std::string timestamp;
  while (lines >> public_key >> timestamp) {
    if (public_key.empty() || timestamp.empty() ||
        timestamp.find_first_not_of("0123456789") != std::string::npos) {
      if (inspection_ok) {
        *inspection_ok = false;
      }
      return false;
    }
    const guint64 observed = g_ascii_strtoull(timestamp.c_str(), nullptr, 10);
    if (observed > 0 && observed <= now && now - observed <= 180) {
      return true;
    }
  }
  return false;
}

static bool WireGuardEndpointBypassEvidence(bool* inspection_ok) {
  if (inspection_ok) {
    *inspection_ok = true;
  }
  CommandResult endpoints =
      RunCommand({"wg", "show", kWireGuardInterface, "endpoints"});
  if (!endpoints.ok) {
    if (inspection_ok) {
      *inspection_ok = false;
    }
    return false;
  }

  bool saw_endpoint = false;
  std::istringstream lines(endpoints.out);
  std::string public_key;
  std::string endpoint;
  while (lines >> public_key >> endpoint) {
    std::string host;
    std::string family;
    if (!endpoint.empty() && endpoint.front() == '[') {
      const size_t closing = endpoint.find(']');
      if (closing <= 1 || endpoint.size() <= closing + 2 ||
          endpoint[closing + 1] != ':') {
        if (inspection_ok) {
          *inspection_ok = false;
        }
        return false;
      }
      host = endpoint.substr(1, closing - 1);
      family = "-6";
    } else {
      const size_t separator = endpoint.rfind(':');
      if (separator == std::string::npos || separator == 0 ||
          separator == endpoint.size() - 1) {
        if (inspection_ok) {
          *inspection_ok = false;
        }
        return false;
      }
      host = endpoint.substr(0, separator);
      family = host.find(':') == std::string::npos ? "-4" : "-6";
    }
    struct in_addr ipv4 {};
    struct in6_addr ipv6 {};
    const bool valid_address =
        (family == "-4" && inet_pton(AF_INET, host.c_str(), &ipv4) == 1) ||
        (family == "-6" && inet_pton(AF_INET6, host.c_str(), &ipv6) == 1);
    if (!valid_address) {
      if (inspection_ok) {
        *inspection_ok = false;
      }
      return false;
    }

    const CommandResult route = RunCommand(
        {"ip", family, "route", "get", host, "mark", "51820"});
    if (!route.ok || route.out.find(" dev sw-wg") != std::string::npos) {
      return false;
    }
    saw_endpoint = true;
  }
  return saw_endpoint;
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
  const FullTunnelRouteEvidence routes =
      ReadFullTunnelRouteEvidence(kWireGuardInterface);
  const bool route_via_sw_wg = FullTunnelRoutesPresent(routes);
  const WireGuardPolicyRuleEvidence policy_rules =
      ReadWireGuardPolicyRuleEvidence();
  const bool policy_rule_inspection_ok =
      policy_rules.ipv4.ok && policy_rules.ipv6.ok;
  const bool policy_rules_present = policy_rules.ipv4_present &&
                                    policy_rules.ipv6_present;
  const bool policy_routes_present =
      WireGuardPolicyRoutesPresentForBothFamilies();
  const bool policy_rule_residue =
      !policy_rule_inspection_ok || policy_rules.ipv4_present ||
      policy_rules.ipv6_present;
  const bool policy_route_residue = WireGuardPolicyRoutesExist();
  const WireGuardFirewallEvidence firewall =
      ReadWireGuardFirewallEvidence();
  bool handshake_inspection_ok = true;
  const bool handshake_present = interface_present
      ? WireGuardHandshakeEvidence(&handshake_inspection_ok)
      : false;
  bool endpoint_inspection_ok = true;
  const bool endpoint_bypass_present = interface_present
      ? WireGuardEndpointBypassEvidence(&endpoint_inspection_ok)
      : false;
  const bool connected = interface_present && route_via_sw_wg &&
                         policy_rules_present && policy_routes_present &&
                         firewall.inspection_ok &&
                         firewall.ipv4_kill_switch_present &&
                         firewall.ipv6_block_present &&
                         handshake_inspection_ok && handshake_present &&
                         endpoint_inspection_ok && endpoint_bypass_present;
  guint64 rx = 0;
  guint64 tx = 0;
  const bool counters = InterfaceCounters(kWireGuardInterface, &rx, &tx);
  Fields fields;
  fields["status"] = connected ? "connected" : "disconnected";
  fields["interface"] = kWireGuardInterface;
  fields["interface_present"] = interface_present ? "true" : "false";
  fields["route_via_sw_wg"] = route_via_sw_wg ? "true" : "false";
  fields["ipv4_route_via_sw_wg"] =
      routes.ipv4_via_interface ? "true" : "false";
  fields["ipv6_route_via_sw_wg"] =
      routes.ipv6_via_interface ? "true" : "false";
  fields["policy_rules_present"] = policy_rules_present ? "true" : "false";
  fields["policy_rule_inspection_ok"] =
      policy_rule_inspection_ok ? "true" : "false";
  fields["ipv4_policy_rules_present"] =
      policy_rules.ipv4_present ? "true" : "false";
  fields["ipv6_policy_rules_present"] =
      policy_rules.ipv6_present ? "true" : "false";
  fields["policy_routes_present"] = policy_routes_present ? "true" : "false";
  fields["firewall_inspection_ok"] =
      firewall.inspection_ok ? "true" : "false";
  fields["nft_table_present"] =
      firewall.nft_table_present ? "true" : "false";
  fields["iptables_rule_present"] =
      firewall.iptables_rule_present ? "true" : "false";
  fields["ip6tables_rule_present"] =
      firewall.ip6tables_rule_present ? "true" : "false";
  fields["ipv4_kill_switch_present"] =
      firewall.ipv4_kill_switch_present ? "true" : "false";
  fields["ipv6_block_present"] =
      firewall.ipv6_block_present ? "true" : "false";
  fields["ipv6_mode"] = "block";
  fields["handshake_inspection_ok"] =
      handshake_inspection_ok ? "true" : "false";
  fields["handshake_present"] = handshake_present ? "true" : "false";
  fields["endpoint_inspection_ok"] =
      endpoint_inspection_ok ? "true" : "false";
  fields["endpoint_bypass_present"] =
      endpoint_bypass_present ? "true" : "false";
  const bool firewall_residue = WireGuardFirewallResidueExists(firewall);
  const bool runtime_residue =
      interface_present || OwnedTunnelRoutePresent(routes) ||
      policy_rule_residue || policy_route_residue || firewall_residue;
  fields["firewall_residue_present"] =
      firewall_residue ? "true" : "false";
  fields["residue_present"] =
      runtime_residue ? "true" : "false";
  fields["rx_bytes"] = std::to_string(rx);
  fields["tx_bytes"] = std::to_string(tx);
  fields["counters_available"] = counters ? "true" : "false";
  if (!firewall.inspection_ok || !policy_rule_inspection_ok ||
      !handshake_inspection_ok || !endpoint_inspection_ok) {
    return Error(
        "inspection_failed",
        "Unable to inspect privileged WireGuard policy or firewall state.",
        fields);
  }
  if (!connected && runtime_residue) {
    return Error(
        "vpn_residue_present",
        "WireGuard is not connected but owned privileged runtime residue remains.",
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
    if (!WireGuardFullTunnelRoutesPresent()) {
      RunHelper({"down", config_path});
      RunHelper({"policy-clear-link", kWireGuardInterface});
      if (!WaitWireGuardClean()) {
        return Error(
            "vpn_connect_failed",
            std::string("WireGuard command completed but IPv4/IPv6 route evidence did not use sw-wg. Cleanup residue remains: ") +
                WireGuardResidueSummary());
      }
      return Error(
          "vpn_connect_failed",
          "WireGuard command completed but IPv4/IPv6 route evidence did not use sw-wg.");
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
  const FullTunnelRouteEvidence routes =
      ReadFullTunnelRouteEvidence(kOpenVpnInterface);
  const bool route_present = FullTunnelRoutesPresent(routes);
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
  fields["ipv4_route_present"] =
      routes.ipv4_via_interface ? "true" : "false";
  fields["ipv6_route_present"] =
      routes.ipv6_via_interface ? "true" : "false";
  fields["ipv6_block_configured"] =
      dns_profile_valid ? "true" : "false";
  fields["ipv6_mode"] = "block";
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
  guint64 rx = 0;
  guint64 tx = 0;
  const bool counters =
      snapshot.xfrm_state_inspection_ok &&
      snapshot.xfrm_policy_inspection_ok &&
      snapshot.owned_if_id_present &&
      ParseOwnedXfrmCounters(
          snapshot.states, snapshot.policies, snapshot.owned_if_id, &rx, &tx);
  Fields fields;
  fields["status"] = snapshot.connected ? "connected" : "disconnected";
  fields["interface"] = kIkev2InterfaceName;
  fields["rx_bytes"] = std::to_string(rx);
  fields["tx_bytes"] = std::to_string(tx);
  fields["counters_available"] = counters ? "true" : "false";
  fields["ipv6_mode"] = "block";
  fields["ipv6_block_inspection_ok"] =
      snapshot.ipv6_block.inspection.ok ? "true" : "false";
  fields["ipv6_block_present"] =
      snapshot.ipv6_block.present ? "true" : "false";
  fields["routing_loop_rule_present"] =
      snapshot.routing_loop_rule_present ? "true" : "false";
  fields["routing_rule_inspection_ok"] =
      (snapshot.rules4.ok && snapshot.rules6.ok) ? "true" : "false";
  fields["routing_rules_safe"] =
      snapshot.routing_rules_safe ? "true" : "false";
  fields["routing_rules_idle_safe"] =
      snapshot.routing_rules_idle_safe ? "true" : "false";
  fields["connection_inspection_ok"] =
      snapshot.connection.inspection_ok ? "true" : "false";
  fields["connection_present"] =
      snapshot.connection.connection_present ? "true" : "false";
  fields["nm_active"] = snapshot.connection.active ? "true" : "false";
  fields["interface_name_configured"] =
      snapshot.connection.interface_name_configured ? "true" : "false";
  fields["interface_inspection_ok"] =
      snapshot.interface.inspection_ok ? "true" : "false";
  fields["interface_present"] =
      snapshot.interface.present ? "true" : "false";
  fields["xfrm_interface"] = snapshot.interface.xfrm ? "true" : "false";
  fields["xfrm_if_id_present"] =
      snapshot.interface.if_id_present ? "true" : "false";
  fields["xfrm_if_id_persisted"] =
      snapshot.interface.if_id_persisted ? "true" : "false";
  fields["ownership_inspection_ok"] =
      snapshot.ownership_inspection_ok ? "true" : "false";
  fields["dns_present"] = snapshot.network.dns_present ? "true" : "false";
  fields["route_inspection_ok"] =
      snapshot.routes.inspection_ok ? "true" : "false";
  fields["route_present"] =
      snapshot.routes.full_tunnel_routes_present ? "true" : "false";
  fields["ipv4_full_route_present"] =
      snapshot.routes.ipv4.full_route_present ? "true" : "false";
  fields["ipv6_full_route_present"] =
      snapshot.routes.ipv6.full_route_present ? "true" : "false";
  fields["owned_route_present"] =
      snapshot.routes.owned_route_present ? "true" : "false";
  fields["route_conflict_present"] =
      snapshot.routes.conflicting_full_route ? "true" : "false";
  fields["route_or_dns_present"] =
      (snapshot.network.dns_present || snapshot.routes.owned_route_present)
          ? "true"
          : "false";
  fields["xfrm_state_inspection_ok"] =
      snapshot.xfrm_state_inspection_ok ? "true" : "false";
  fields["xfrm_policy_inspection_ok"] =
      snapshot.xfrm_policy_inspection_ok ? "true" : "false";
  fields["xfrm_state_present"] =
      snapshot.owned_xfrm_state_present ? "true" : "false";
  fields["xfrm_esp_present"] =
      snapshot.owned_xfrm_esp_present ? "true" : "false";
  fields["xfrm_policy_present"] =
      snapshot.owned_xfrm_policy_present ? "true" : "false";
  fields["xfrm_pair_present"] =
      snapshot.owned_xfrm_pair_present ? "true" : "false";

  if (!snapshot.connection.inspection_ok ||
      !snapshot.interface.inspection_ok ||
      !snapshot.ownership_inspection_ok ||
      !snapshot.xfrm_state_inspection_ok ||
      !snapshot.xfrm_policy_inspection_ok ||
      !snapshot.routes.inspection_ok ||
      !snapshot.ipv6_block.inspection.ok ||
      !snapshot.rules4.ok ||
      !snapshot.rules6.ok) {
    return Error(
        "inspection_failed",
        "Unable to inspect owned IKEv2 NetworkManager, route, or XFRM state.",
        fields);
  }
  const bool disconnected_clean = Ikev2DisconnectedStateClean(
          snapshot.connection.inspection_ok,
          snapshot.connection.connection_present,
          snapshot.connection.active,
          snapshot.interface.inspection_ok,
          snapshot.interface.present,
          snapshot.xfrm_state_inspection_ok,
          snapshot.owned_xfrm_state_present,
          snapshot.xfrm_policy_inspection_ok,
          snapshot.owned_xfrm_policy_present,
          snapshot.routes.inspection_ok,
          snapshot.routes.owned_route_present,
          snapshot.ipv6_block.inspection.ok,
          snapshot.ipv6_block.present,
          snapshot.rules4.ok && snapshot.rules6.ok,
          snapshot.routing_rules_idle_safe);
  if (!snapshot.connected && !disconnected_clean) {
    return Error(
        "vpn_residue_present",
        "IKEv2 is not connected but owned privileged runtime residue remains.",
        fields);
  }
  if (!snapshot.connected && !ClearPersistedIkev2IfId()) {
    return Error(
        "inspection_failed",
        "Owned IKEv2 runtime state is clean but its ownership record could not be cleared.",
        fields);
  }
  return Ok(fields);
}

static bool StopIkev2Runtime(std::string* message) {
  const Ikev2RuntimeSnapshot before = ReadIkev2RuntimeSnapshot();
  if (!before.connection.inspection_ok ||
      !before.interface.inspection_ok ||
      !before.ownership_inspection_ok ||
      !before.ipv6_block.inspection.ok ||
      (before.connection.active &&
       (!before.interface.present || !before.interface.if_id_present ||
        !before.interface.if_id_persisted))) {
    if (message) {
      *message = "Unable to capture the exact SecureWave IKEv2 XFRM owner before disconnect.";
    }
    return false;
  }
  const CommandResult down = RunHelper({"ikev2-down"});
  const CommandResult remove = RunHelper({"ikev2-delete"});
  if (!down.ok || !remove.ok) {
    if (message) {
      *message = !down.ok
          ? (down.message.empty() ? "IKEv2 NetworkManager disconnect failed."
                                  : down.message)
          : (remove.message.empty() ? "IKEv2 NetworkManager profile deletion failed."
                                    : remove.message);
    }
    return false;
  }
  if (!WaitIkev2Stopped()) {
    if (message) {
      *message = "IKEv2 disconnect completed but owned link, route, policy, or XFRM state remains.";
    }
    return false;
  }
  const Fields status = Ikev2Status();
  if (Field(status, "ok") != "true" ||
      Field(status, "status") != "disconnected") {
    if (message) {
      *message = "IKEv2 cleanup could not be verified as a clean disconnected state.";
    }
    return false;
  }
  return true;
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
    std::string message;
    if (!StopIkev2Runtime(&message)) {
      return Error("vpn_disconnect_failed", message);
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
  DnsServers dns_servers;
  if (server.empty() || username.empty() || password.empty()) {
    return Error("invalid_config", "IKEv2 config is missing server, EAP ID, or EAP secret.");
  }
  if (!ExtractIkev2DnsServers(contents, &dns_servers)) {
    return Error(
        "invalid_config",
        "IKEv2 config is missing a valid SecureWave DNS IP marker.");
  }
  if (!Ikev2Ipv6BlockModeConfigured(contents)) {
    return Error(
        "invalid_config",
        "IKEv2 config is missing the required SecureWave IPv6 block mode.");
  }

  std::string ca_path;
  if (!ca_pem.empty()) {
    ca_path = Dirname(config_path) + "/" + kIkev2CaName;
    std::string write_error;
    if (!WritePeerOwnedFile(ca_path, ca_pem + "\n", peer_uid, &write_error)) {
      return Error("vpn_connect_failed", "Unable to write IKEv2 CA certificate: " + write_error);
    }
  }

  std::string cleanup_message;
  if (!StopIkev2Runtime(&cleanup_message)) {
    return Error(
        "vpn_connect_failed",
        "Unable to establish a clean IKEv2 baseline: " + cleanup_message);
  }
  const auto connect_failure = [](const std::string& primary) {
    std::string cleanup_error;
    const bool cleaned = StopIkev2Runtime(&cleanup_error);
    return Error(
        "vpn_connect_failed",
        primary +
            (cleaned ? "" : " Cleanup also failed: " + cleanup_error));
  };
  std::vector<std::string> add_args = {"ikev2-add-eap", server, username, password};
  add_args.push_back(remote_id.empty() ? server : remote_id);
  if (!ca_path.empty()) {
    add_args.push_back(ca_path);
  }
  CommandResult add = RunHelper(add_args);
  if (!add.ok) {
    return connect_failure(
        add.message.empty()
            ? "IKEv2 NetworkManager profile creation failed."
            : add.message);
  }
  CommandResult dns =
      RunHelper(TaggedDnsHelperArgs("ikev2-set-dns", dns_servers));
  if (!dns.ok) {
    return connect_failure(
        dns.message.empty()
            ? "IKEv2 NetworkManager DNS enforcement failed."
            : dns.message);
  }
  CommandResult up = RunHelper({"ikev2-up"});
  if (!up.ok) {
    return connect_failure(
        up.message.empty() ? "IKEv2 start failed." : up.message);
  }
  for (guint i = 0; i < 40; i++) {
    if (Ikev2RuntimeEvidence()) {
      return Ikev2Status();
    }
    g_usleep(500000);
  }
  const bool cleaned = StopIkev2Runtime(&cleanup_message);
  return Error(
      "vpn_connect_failed",
      std::string("IKEv2 started but exact IPv4 table-210 routing, IPv6 blocking, DNS, owned XFRM state/policy, counters, and routing-loop safety evidence were not detected.") +
          (cleaned ? "" : " Cleanup also failed: " + cleanup_message));
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

static int SendRequestToRunningHelper() {
  std::string request;
  if (!ReadAll(STDIN_FILENO, &request)) {
    g_printerr("securewave-helperd request input was unreadable.\n");
    return 2;
  }
  int fd = socket(AF_UNIX, SOCK_STREAM, 0);
  if (fd < 0) {
    g_printerr("securewave-helperd request socket failed: %s\n", g_strerror(errno));
    return 2;
  }
  sockaddr_un address {};
  address.sun_family = AF_UNIX;
  g_strlcpy(address.sun_path, kSocketPath, sizeof(address.sun_path));
  const struct timeval timeout = {30, 0};
  setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
  setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
  if (connect(fd, reinterpret_cast<sockaddr*>(&address), sizeof(address)) != 0 ||
      !WriteAll(fd, request) || shutdown(fd, SHUT_WR) != 0) {
    g_printerr("securewave-helperd request connection failed: %s\n", g_strerror(errno));
    close(fd);
    return 2;
  }
  std::string response;
  const bool read = ReadAll(fd, &response);
  close(fd);
  if (!read || !WriteAll(STDOUT_FILENO, response)) {
    g_printerr("securewave-helperd response was unreadable.\n");
    return 2;
  }
  const ParsedFields parsed = ParseFields(response);
  guint32 contract = 0;
  const bool contract_ok =
      parsed.valid &&
      ParseUint32Strict(Field(parsed.fields, "contract"), 10, &contract) &&
      contract >= kContractVersion;
  return contract_ok && Field(parsed.fields, "ok") == "true" ? 0 : 1;
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
