// Included inside the helper's private namespace, after its constrained IPC
// and command utilities. No account JWTs, private keys or HTTP live here.
struct UsageRecord {
  std::string id, token, config, expected_peer, stopped_at, reason, boot;
  uid_t uid = 0;
  guint64 sequence = 1, ack = 0, rx = 0, tx = 0, raw_rx = 0, raw_tx = 0;
  int owner_fd = -1;
  pid_t owner_pid = 0;
  bool final = false, verified = false, gap = false;
};
static std::map<std::string, UsageRecord> usage_records;
static std::string active_usage;
static bool usage_healthy = true;
static volatile sig_atomic_t usage_stopping = 0;

static bool HexToken(const std::string& value) {
  return value.size() == 64 && std::all_of(value.begin(), value.end(),
      [](char c) { return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'); });
}
static std::string UsageDirectory() {
  return RuntimePath("SECUREWAVE_TEST_USAGE_ROOT", "/var/lib/securewave/usage");
}
static std::string CurrentBoot() {
  std::ifstream input("/proc/sys/kernel/random/boot_id");
  std::string boot;
  std::getline(input, boot);
  return boot;
}
static std::string UsageTime() {
  GDateTime* now = g_date_time_new_now_utc();
  gchar* value = g_date_time_format(now, "%Y-%m-%dT%H:%M:%S.%fZ");
  std::string result(value);
  g_free(value);
  g_date_time_unref(now);
  return result;
}
static bool SaveUsage(const UsageRecord& record) {
  const std::string directory = UsageDirectory();
  if (g_mkdir_with_parents(directory.c_str(), 0700) != 0) return false;
  struct stat st {};
  if (lstat(directory.c_str(), &st) != 0 || !S_ISDIR(st.st_mode) ||
      st.st_uid != geteuid() || (st.st_mode & 0077)) return false;
  GKeyFile* file = g_key_file_new();
  auto string = [&](const char* key, const std::string& value) {
    g_key_file_set_string(file, "usage", key, value.c_str());
  };
  auto number = [&](const char* key, guint64 value) {
    g_key_file_set_uint64(file, "usage", key, value);
  };
  string("id", record.id); string("token", record.token);
  string("config", record.config); string("peer", record.expected_peer);
  string("boot", record.boot); string("stopped_at", record.stopped_at);
  string("reason", record.reason);
  number("uid", record.uid); number("sequence", record.sequence);
  number("ack", record.ack); number("rx", record.rx); number("tx", record.tx);
  number("raw_rx", record.raw_rx); number("raw_tx", record.raw_tx);
  g_key_file_set_boolean(file, "usage", "final", record.final);
  g_key_file_set_boolean(file, "usage", "verified", record.verified);
  g_key_file_set_boolean(file, "usage", "gap", record.gap);
  gsize length = 0;
  gchar* contents = g_key_file_to_data(file, &length, nullptr);
  const std::string path = directory + "/" + record.id + ".ini";
  // GLib's durable replace fsyncs the file and containing directory.
  const bool saved = g_file_set_contents_full(path.c_str(), contents, length,
      static_cast<GFileSetContentsFlags>(G_FILE_SET_CONTENTS_CONSISTENT | G_FILE_SET_CONTENTS_DURABLE),
      0600, nullptr);
  g_free(contents); g_key_file_unref(file);
  return saved;
}
static bool ReadUsageCounters(UsageRecord* record) {
  const CommandResult result = RunHelper({"wireguard-transfer"});
  if (!result.ok) return false;
  std::istringstream lines(result.out);
  std::string line;
  bool found = false;
  guint64 rx = 0, tx = 0;
  while (std::getline(lines, line)) {
    if (Trim(line).empty()) continue;
    std::istringstream row(line);
    std::string key, raw_rx, raw_tx, extra;
    if (!(row >> key >> raw_rx >> raw_tx) || row >> extra ||
        key != record->expected_peer || found ||
        !ParseUint64Strict(raw_rx, &rx) || !ParseUint64Strict(raw_tx, &tx)) return false;
    found = true;
  }
  if (!found) return false;
  if (rx < record->raw_rx || tx < record->raw_tx) record->gap = true;
  const guint64 drx = rx >= record->raw_rx ? rx - record->raw_rx : rx;
  const guint64 dtx = tx >= record->raw_tx ? tx - record->raw_tx : tx;
  if (drx > G_MAXINT64 - record->rx || dtx > G_MAXINT64 - record->tx) return false;
  record->rx += drx; record->tx += dtx;
  record->raw_rx = rx; record->raw_tx = tx;
  return true;
}
static bool FinishUsage(UsageRecord* record, const std::string& reason, bool recovering = false) {
  if (record->final) return true;
  const bool present = g_file_test(WireGuardSysfsPath().c_str(), G_FILE_TEST_IS_DIR);
  if (present) {
    if (!RunHelper({"quiesce"}).ok || !ReadUsageCounters(record)) record->gap = true;
  } else if (reason != "connect_failed") {
    record->gap = true;
  }
  if (recovering) record->gap = true;
  record->final = true; record->reason = reason; record->stopped_at = UsageTime();
  record->sequence++;
  const bool saved = SaveUsage(*record);
  const bool down = RunHelper({"down", record->config}).ok &&
      !g_file_test(WireGuardSysfsPath().c_str(), G_FILE_TEST_IS_DIR);
  if (down && ExistingConfigFileSafe(record->config, record->uid)) unlink(record->config.c_str());
  if (record->owner_fd >= 0) { close(record->owner_fd); record->owner_fd = -1; }
  active_usage.clear();
  // Teardown must happen even when the filesystem is unavailable.
  return saved && down;
}
static void LoadUsage() {
  GDir* dir = g_dir_open(UsageDirectory().c_str(), 0, nullptr);
  if (!dir) return;
  const gchar* name;
  while ((name = g_dir_read_name(dir))) {
    if (!g_str_has_suffix(name, ".ini")) continue;
    const std::string path = UsageDirectory() + "/" + name;
    struct stat st {};
    if (lstat(path.c_str(), &st) != 0 || !S_ISREG(st.st_mode) || st.st_uid != geteuid() ||
        (st.st_mode & 0077) || st.st_size > 16384) {
      usage_healthy = false; continue;
    }
    GKeyFile* file = g_key_file_new();
    if (!g_key_file_load_from_file(file, path.c_str(), G_KEY_FILE_NONE, nullptr)) {
      usage_healthy = false; g_key_file_unref(file); continue;
    }
    auto string = [&](const char* key) {
      gchar* value = g_key_file_get_string(file, "usage", key, nullptr);
      std::string result(value ? value : ""); g_free(value); return result;
    };
    auto number = [&](const char* key) { return g_key_file_get_uint64(file, "usage", key, nullptr); };
    UsageRecord record;
    record.id = string("id"); record.token = string("token"); record.config = string("config");
    record.expected_peer = string("peer"); record.boot = string("boot");
    record.reason = string("reason"); record.stopped_at = string("stopped_at");
    record.uid = number("uid"); record.sequence = number("sequence"); record.ack = number("ack");
    record.rx = number("rx"); record.tx = number("tx");
    record.raw_rx = number("raw_rx"); record.raw_tx = number("raw_tx");
    record.final = g_key_file_get_boolean(file, "usage", "final", nullptr);
    record.verified = g_key_file_get_boolean(file, "usage", "verified", nullptr);
    record.gap = g_key_file_get_boolean(file, "usage", "gap", nullptr);
    g_key_file_unref(file);
    guint64 id = 0;
    if (!ParseUint64Strict(record.id, &id) || id == 0 ||
        std::string(name) != record.id + ".ini" || !HexToken(record.token) ||
        !IsApprovedConfigPath(record.config, record.uid) || !IsWireGuardPublicKey(record.expected_peer) ||
        record.sequence == 0 || record.sequence > G_MAXINT64 || record.rx > G_MAXINT64 || record.tx > G_MAXINT64) {
      usage_healthy = false; continue;
    }
    if (!record.final) {
      if (record.boot != CurrentBoot()) { record.raw_rx = 0; record.raw_tx = 0; }
      FinishUsage(&record, "interrupted", true);
    }
    usage_records[record.id] = record;
  }
  g_dir_close(dir);
}
static void TickUsage() {
  auto it = usage_records.find(active_usage);
  if (it == usage_records.end()) return;
  UsageRecord& record = it->second;
  struct pollfd owner {record.owner_fd, POLLIN, 0};
  if (record.owner_fd < 0 || poll(&owner, 1, 0) > 0) {
    FinishUsage(&record, "app_crash"); return;
  }
  if (!ReadUsageCounters(&record)) {
    record.gap = true; FinishUsage(&record, "recording_error"); return;
  }
  record.sequence++;
  if (!SaveUsage(record)) { record.gap = true; FinishUsage(&record, "recording_error"); }
}
static bool ReporterPeer(const PeerCredentials& peer) {
  const struct passwd* reporter = getpwnam("securewave-meter");
  return peer.valid && (peer.uid == 0 || (reporter && peer.uid == reporter->pw_uid));
}
static Fields UsagePending() {
  std::string json = "[";
  int count = 0;
  for (const auto& entry : usage_records) {
    const UsageRecord& r = entry.second;
    if (r.ack >= r.sequence || count >= 16) continue;
    if (count++) json += ",";
    json += "{\"session_id\":" + r.id + ",\"token\":\"" + r.token +
      "\",\"sequence\":" + std::to_string(r.sequence) +
      ",\"bytes_received\":" + std::to_string(r.rx) +
      ",\"bytes_sent\":" + std::to_string(r.tx) +
      ",\"final\":" + (r.final ? "true" : "false") +
      ",\"verified\":" + (r.verified ? "true" : "false") +
      ",\"gap\":" + (r.gap ? "true" : "false");
    if (r.final) json += ",\"reason\":\"" + r.reason + "\",\"stopped_at\":\"" + r.stopped_at + "\"";
    json += "}";
  }
  json += "]";
  return Ok({{"records", json}});
}
static Fields UsageStatus(uid_t uid, pid_t pid) {
  const UsageRecord* latest = nullptr;
  guint pending = 0;
  for (const auto& item : usage_records) {
    const auto& r = item.second;
    if (r.uid != uid) continue;
    if (r.ack < r.sequence) pending++;
    if (!latest || std::stoull(r.id) > std::stoull(latest->id)) latest = &r;
  }
  const auto active = usage_records.find(active_usage);
  const bool owned = active != usage_records.end() && active->second.uid == uid && active->second.owner_pid == pid;
  return Ok({{"owned", owned ? "true" : "false"}, {"pending", std::to_string(pending)},
             {"gap", latest && latest->gap ? "true" : "false"},
             {"bytes_sent", latest ? std::to_string(latest->tx) : "0"},
             {"bytes_received", latest ? std::to_string(latest->rx) : "0"}});
}
