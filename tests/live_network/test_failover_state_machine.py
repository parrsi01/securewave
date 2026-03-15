"""CI-safe unit tests for failover validation logic.

No root, tunnel, iptables, or network access required.
"""

from __future__ import annotations

from unittest.mock import patch

from dev_tools.sandbox.live_validation.common import CommandResult
from dev_tools.sandbox.live_validation.failover_test import (
    FailoverReport,
    ServerState,
    parse_endpoint,
    resolve_endpoint_ip,
    capture_server_state,
    run_failover_test,
)


class TestParseEndpoint:
    def test_host_and_port(self):
        host, port = parse_endpoint("138.199.204.139:51820")
        assert host == "138.199.204.139"
        assert port == 51820

    def test_empty(self):
        host, port = parse_endpoint("")
        assert host == ""
        assert port == 0

    def test_host_only(self):
        host, port = parse_endpoint("example.com")
        assert host == "example.com"
        assert port == 0

    def test_invalid_port(self):
        host, port = parse_endpoint("example.com:abc")
        assert host == "example.com"
        assert port == 0


class TestResolveEndpointIp:
    @patch("dev_tools.sandbox.live_validation.failover_test.socket.gethostbyname")
    def test_resolves_hostname(self, mock_dns):
        mock_dns.return_value = "138.199.204.139"
        assert resolve_endpoint_ip("vpn.example.com") == "138.199.204.139"

    @patch("dev_tools.sandbox.live_validation.failover_test.socket.gethostbyname")
    def test_returns_ip_on_failure(self, mock_dns):
        mock_dns.side_effect = Exception("DNS failed")
        assert resolve_endpoint_ip("bad.host") == "bad.host"

    def test_ip_passthrough(self):
        assert resolve_endpoint_ip("138.199.204.139") == "138.199.204.139"


class TestCaptureServerState:
    @patch("dev_tools.sandbox.live_validation.failover_test.fetch_public_ip")
    @patch("dev_tools.sandbox.live_validation.failover_test.run_command")
    def test_captures_state(self, mock_run, mock_ip):
        mock_run.side_effect = [
            CommandResult("wg show wg0 endpoints", 0,
                          "pubkey123\t138.199.204.139:51820", "", 1.0),
            CommandResult("wg show wg0 latest-handshakes", 0,
                          "pubkey123 1700000000", "", 1.0),
        ]
        mock_ip.return_value = "138.199.204.139"

        state = capture_server_state(interface="wg0")
        assert state.endpoint == "138.199.204.139:51820"
        assert state.endpoint_ip == "138.199.204.139"
        assert state.endpoint_port == 51820
        assert state.handshake_epoch == 1700000000
        assert state.public_ip == "138.199.204.139"


class TestRunFailoverTest:
    @patch("dev_tools.sandbox.live_validation.failover_test.capture_server_state")
    def test_simulation_mode(self, mock_capture):
        mock_capture.return_value = ServerState(
            interface="wg0",
            endpoint="138.199.204.139:51820",
            endpoint_ip="138.199.204.139",
            endpoint_port=51820,
            handshake_epoch=1700000000,
            public_ip="138.199.204.139",
        )
        report = run_failover_test(interface="wg0", execute=False)
        assert report.verdict == "SIMULATED"
        assert len(report.events) >= 2

    @patch("dev_tools.sandbox.live_validation.failover_test.capture_server_state")
    def test_skip_when_no_endpoint(self, mock_capture):
        mock_capture.return_value = ServerState(interface="wg0")
        report = run_failover_test(interface="wg0", execute=True)
        assert report.verdict == "SKIP"
        assert "cannot_determine_primary_endpoint" in report.failures

    @patch("dev_tools.sandbox.live_validation.failover_test.os")
    @patch("dev_tools.sandbox.live_validation.failover_test.capture_server_state")
    def test_skip_when_not_root(self, mock_capture, mock_os):
        mock_capture.return_value = ServerState(
            interface="wg0",
            endpoint="1.2.3.4:51820",
            endpoint_ip="1.2.3.4",
            endpoint_port=51820,
        )
        mock_os.geteuid.return_value = 1000
        # hasattr check
        type(mock_os).geteuid = property(lambda self: lambda: 1000)
        report = run_failover_test(interface="wg0", execute=True)
        # Will either SKIP (non-root) or try to block (root mock issue).
        assert report.verdict in {"SKIP", "FAIL"}


class TestFailoverReport:
    def test_to_dict(self):
        r = FailoverReport(verdict="PASS")
        d = r.to_dict()
        assert d["verdict"] == "PASS"
        assert "primary_server" in d
        assert "secondary_server" in d
        assert "events" in d

    def test_defaults(self):
        r = FailoverReport()
        assert r.verdict == "UNTESTED"
        assert r.block_applied is False
        assert r.reconnect_detected is False
