#define SECUREWAVE_HELPERD_TESTING
#define SECUREWAVE_HELPERD_NO_MAIN
#include "../helperd/securewave_helperd.cc"

#include <ctime>
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
  WriteFile(contract, "14\n");
  WriteFile(rx_path, "21\n");
  WriteFile(tx_path, "34\n");
  WriteFile(helper,
            "#!/bin/sh\n"
            "printf '%s\\n' \"$*\" >> \"$SECUREWAVE_TEST_CALL_LOG\"\n"
            "if [ \"${SECUREWAVE_TEST_HELPER_FAIL:-0}\" = 1 ]; then exit 23; fi\n"
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
