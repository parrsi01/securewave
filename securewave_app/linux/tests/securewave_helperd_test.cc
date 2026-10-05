#define SECUREWAVE_HELPERD_TESTING
#define SECUREWAVE_HELPERD_NO_MAIN
#include "../helperd/securewave_helperd.cc"

#include <ctime>
#include <sys/wait.h>
#include <fstream>
#include <string>

namespace {

void Require(bool condition, const char* message) {
  if (!condition) {
    g_printerr("helperd test failed: %s\n", message);
    std::exit(1);
  }
}

void WriteFile(const std::string& path, const std::string& contents) {
  std::ofstream output(path.c_str(), std::ios::binary);
  output << contents;
  output.close();
  Require(output.good(), "could not write test fixture");
}

Fields Request(const std::string& op) {
  Fields request;
  request["version"] = "1";
  request["op"] = op;
  return request;
}

Fields AsRoot(const Fields& request) {
  PeerCredentials peer;
  peer.uid = 0;
  peer.valid = true;
  return HandleRequest(request, peer);
}

std::string ReadFile(const std::string& path) {
  std::ifstream input(path.c_str(), std::ios::binary);
  return std::string(std::istreambuf_iterator<char>(input),
                     std::istreambuf_iterator<char>());
}

}  // namespace

int main() {
  char temp_template[] = "/tmp/securewave-helperd-test-XXXXXX";
  char* temp = mkdtemp(temp_template);
  Require(temp != nullptr, "could not create test directory");
  const std::string root(temp);
  const std::string helper = root + "/mock-securewave-helper";
  const std::string contract = root + "/contract";
  const std::string calls = root + "/helper-calls";
  const std::string sysfs = root + "/sys/class/net";
  const std::string interface = sysfs + "/sw-wg";
  const std::string statistics = interface + "/statistics";
  const std::string rx_path = statistics + "/rx_bytes";
  const std::string tx_path = statistics + "/tx_bytes";
  const std::string empty_sysfs = root + "/empty-sysfs";
  const std::string marker = root + "/arbitrary-command-ran";

  Require(g_mkdir_with_parents(statistics.c_str(), 0700) == 0,
          "could not create interface fixture");
  Require(g_mkdir_with_parents(empty_sysfs.c_str(), 0700) == 0,
          "could not create empty sysfs fixture");
  WriteFile(contract, "15\n");
  WriteFile(rx_path, "21\n");
  WriteFile(tx_path, "34\n");
  WriteFile(helper,
            "#!/bin/sh\n"
            "printf '%s\\n' \"$*\" >> \"$SECUREWAVE_TEST_CALL_LOG\"\n"
            "if [ \"${SECUREWAVE_TEST_HELPER_FAIL:-0}\" = 1 ]; then exit 23; fi\n"
            "if [ \"$1\" = wireguard-transfer ]; then printf '%s' \"$SECUREWAVE_TEST_TRANSFER\"; exit 0; fi\n"
            "if [ \"$1\" = quiesce ] || [ \"$1\" = down ]; then exit 0; fi\n"
            "if [ \"$#\" -ne 1 ] || [ \"$1\" != \"wireguard-peer-handshakes\" ]; then exit 64; fi\n"
            "printf '%s' \"${SECUREWAVE_TEST_PEER_STATUS:-}\"\n");
  Require(chmod(helper.c_str(), 0755) == 0,
          "could not make helper fixture executable");

  setenv("SECUREWAVE_TEST_HELPER_PATH", helper.c_str(), 1);
  setenv("SECUREWAVE_TEST_CONTRACT_PATH", contract.c_str(), 1);
  setenv("SECUREWAVE_TEST_SYSFS_ROOT", sysfs.c_str(), 1);
  setenv("SECUREWAVE_TEST_CALL_LOG", calls.c_str(), 1);
  const std::string peer_key = "w1bQ0wAmvob32mgEBQvVkTTAu10bSmyK7bGkC/06pGA=";
  const std::string handshake =
      peer_key + " " + std::to_string(static_cast<guint64>(std::time(nullptr))) + "\n";
  setenv("SECUREWAVE_TEST_PEER_STATUS", handshake.c_str(), 1);

  PeerCredentials root_peer;
  root_peer.uid = 0;
  root_peer.valid = true;
  const std::string malformed =
      "version=1\nop=wireguard.runtime\nmissing-separator\n";
  Fields result = HandleRequestBody(malformed, root_peer);
  Require(Field(result, "code") == "invalid_request",
          "malformed request was not rejected");

  Fields unsupported = Request("run");
  unsupported["command"] = "touch " + marker;
  result = AsRoot(unsupported);
  Require(Field(result, "code") == "invalid_operation",
          "unsupported operation was not rejected");
  Require(access(marker.c_str(), F_OK) != 0,
          "unsupported request executed an arbitrary command");
  const CommandResult arbitrary_command = RunCommand({"touch", marker});
  Require(!arbitrary_command.spawned && access(marker.c_str(), F_OK) != 0,
          "helper command allowlist executed an arbitrary binary");

  Fields injected_command = Request("wireguard.runtime");
  injected_command["command"] = "touch " + marker;
  result = AsRoot(injected_command);
  Require(Field(result, "code") == "invalid_request",
          "runtime operation accepted a command argument");
  Require(access(marker.c_str(), F_OK) != 0,
          "runtime operation executed an arbitrary command");

  Fields injected_interface = Request("wireguard.runtime");
  injected_interface["interface"] = "eth0";
  result = AsRoot(injected_interface);
  Require(Field(result, "code") == "invalid_request",
          "runtime operation accepted an arbitrary interface");

  PeerCredentials unauthorized;
  result = HandleRequest(Request("wireguard.runtime"), unauthorized);
  Require(Field(result, "code") == "unauthorized",
          "unauthorized IPC peer was not rejected");

  Fields status_request = Request("wireguard.status");
  result = AsRoot(status_request);
  Require(Field(result, "ok") == "true" &&
              Field(result, "status") == "connected" &&
              Field(result, "interface") == "sw-wg" &&
              Field(result, "rx_bytes") == "21" &&
              Field(result, "tx_bytes") == "34",
          "valid status request did not return the fixed interface counters");

  result = AsRoot(Request("wireguard.runtime"));
  Require(Field(result, "ok") == "true" &&
              Field(result, "status") == "connected" &&
              Field(result, "interface") == "sw-wg" &&
              Field(result, "rx_bytes") == "21" &&
              Field(result, "tx_bytes") == "34" &&
              Field(result, "counters_available") == "true" &&
              Field(result, "peer_handshakes") == handshake,
          "runtime request did not return validated peer and counter state");
  Require(ReadFile(calls) == "wireguard-peer-handshakes\n",
          "runtime request did not use its fixed helper operation");

  std::string normalized;
  std::string parse_error;
  Require(ParsePeerHandshakes(handshake, &normalized, &parse_error) &&
              normalized == handshake,
          "valid peer and handshake output was not parsed");
  Require(!ParsePeerHandshakes("invalid-key 5\n", &normalized, &parse_error),
          "malformed peer output was accepted");
  Require(!ParsePeerHandshakes(handshake + handshake,
                               &normalized,
                               &parse_error),
          "duplicate peer output was accepted");

  setenv("SECUREWAVE_TEST_PEER_STATUS", "invalid-key 5\n", 1);
  result = AsRoot(Request("wireguard.runtime"));
  Require(Field(result, "code") == "peer_status_invalid",
          "malformed helper output did not fail closed");

  setenv("SECUREWAVE_TEST_PEER_STATUS", handshake.c_str(), 1);
  setenv("SECUREWAVE_TEST_HELPER_FAIL", "1", 1);
  result = AsRoot(Request("wireguard.runtime"));
  Require(Field(result, "code") == "peer_status_unavailable",
          "helper failure did not propagate");
  unsetenv("SECUREWAVE_TEST_HELPER_FAIL");

  WriteFile(rx_path, "not-a-counter\n");
  result = AsRoot(Request("wireguard.runtime"));
  Require(Field(result, "code") == "runtime_counters_unavailable",
          "malformed RX counter did not fail closed");
  WriteFile(rx_path, "21\n");

  setenv("SECUREWAVE_TEST_SYSFS_ROOT", empty_sysfs.c_str(), 1);
  const std::string calls_before_disconnected = ReadFile(calls);
  result = AsRoot(Request("wireguard.runtime"));
  Require(Field(result, "ok") == "true" &&
              Field(result, "status") == "disconnected" &&
              Field(result, "interface") == "sw-wg" &&
              Field(result, "counters_available") == "false" &&
              ReadFile(calls) == calls_before_disconnected,
          "disconnected interface state was not reported accurately");

  // Durable cumulative snapshots, reset honesty, scoped IPC and replay.
  const std::string usage_root = root + "/usage";
  setenv("SECUREWAVE_TEST_USAGE_ROOT", usage_root.c_str(), 1);
  UsageRecord recording;
  recording.id = "101"; recording.token = std::string(64, 'b');
  recording.uid = geteuid(); recording.expected_peer = peer_key;
  recording.config = "/run/securewave/sw-wg.conf"; recording.boot = CurrentBoot();
  recording.owner_pid = getpid(); recording.owner_fd = syscall(SYS_pidfd_open, getpid(), 0);
  Require(recording.owner_fd >= 0, "could not track recorder process identity");
  setenv("SECUREWAVE_TEST_TRANSFER", (peer_key + " 5000000000 7000000000\n").c_str(), 1);
  Require(ReadUsageCounters(&recording) && SaveUsage(recording), "could not persist large measured counters");
  Require(recording.rx == 5000000000ULL && recording.tx == 7000000000ULL, "large counters were truncated");
  setenv("SECUREWAVE_TEST_TRANSFER", (peer_key + " 3 5\n").c_str(), 1);
  Require(ReadUsageCounters(&recording) && recording.gap && recording.rx == 5000000003ULL,
          "counter reset lost already observed bytes or hid the gap");
  recording.sequence++; recording.final = true; recording.reason = "app_crash";
  recording.stopped_at = UsageTime();
  Require(SaveUsage(recording), "could not persist final snapshot");
  usage_records.clear(); LoadUsage();
  Require(usage_records.at("101").rx == recording.rx && usage_records.at("101").final,
          "restart lost the final journal");
  Require(Field(HandleRequest(Request("usage.pending"), unauthorized), "code") == "unauthorized",
          "untrusted user could read reporting capabilities");
  Fields pending = AsRoot(Request("usage.pending"));
  Require(Field(pending, "records").find("5000000003") != std::string::npos,
          "pending replay lost cumulative bytes");
  Fields ack = Request("usage.ack"); ack["session_id"] = "101"; ack["sequence"] = "999";
  Require(Field(AsRoot(ack), "ok") != "true", "ack accepted an unmeasured future sequence");
  ack["sequence"] = std::to_string(recording.sequence);
  Require(Field(AsRoot(ack), "ok") == "true" && usage_records.empty(), "final ack did not clear durable backlog");
  close(recording.owner_fd);
  pid_t child = fork();
  Require(child >= 0, "could not create tracked process");
  if (child == 0) { pause(); _exit(0); }
  UsageRecord crashed;
  crashed.id = "102"; crashed.token = std::string(64, 'c'); crashed.uid = geteuid();
  crashed.expected_peer = peer_key; crashed.config = "/run/securewave/sw-wg.conf";
  crashed.boot = CurrentBoot(); crashed.owner_pid = child;
  crashed.owner_fd = syscall(SYS_pidfd_open, child, 0);
  crashed.rx = 400; crashed.tx = 200;
  Require(crashed.owner_fd >= 0 && SaveUsage(crashed), "could not prepare crash recorder");
  usage_records[crashed.id] = crashed; active_usage = crashed.id;
  kill(child, SIGKILL); waitpid(child, nullptr, 0);
  TickUsage();
  Require(active_usage.empty() && usage_records.at("102").final &&
          usage_records.at("102").reason == "app_crash" && usage_records.at("102").rx == 400,
          "process death did not finalize the durable measurement");
  ack["session_id"] = "102"; ack["sequence"] = std::to_string(usage_records.at("102").sequence);
  Require(Field(AsRoot(ack), "ok") == "true", "crash finalization could not be acknowledged");
  g_rmdir(usage_root.c_str());

  g_remove(rx_path.c_str());
  g_remove(tx_path.c_str());
  g_rmdir(statistics.c_str());
  g_rmdir(interface.c_str());
  g_rmdir((sysfs + "/class/net").c_str());
  g_rmdir((sysfs + "/class").c_str());
  g_rmdir(sysfs.c_str());
  g_rmdir(empty_sysfs.c_str());
  g_remove(helper.c_str());
  g_remove(contract.c_str());
  g_remove(calls.c_str());
  g_rmdir(root.c_str());
  return 0;
}
