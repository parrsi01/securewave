"""CI-safe unit tests for IPv6 leak detection logic.

No root, tunnel, or network access required.
"""

from __future__ import annotations

from unittest.mock import patch

from dev_tools.sandbox.live_validation.common import CommandResult
from dev_tools.sandbox.live_validation.ipv6_leak_test import (
    IPv6Address,
    IPv6LeakReport,
    get_ipv6_addresses,
    detect_ipv6_enabled,
    check_ipv6_route_device,
    check_ipv6_disabled_on_tunnel,
    run_ipv6_leak_test,
)


class TestDetectIpv6Enabled:
    @patch("dev_tools.sandbox.live_validation.ipv6_leak_test.run_command")
    def test_enabled_when_global_scope_exists(self, mock_run):
        mock_run.return_value = CommandResult(
            "ip -6 addr show scope global", 0,
            "2: ens3    inet6 2001:db8::1/64 scope global", "", 1.0,
        )
        assert detect_ipv6_enabled() is True

    @patch("dev_tools.sandbox.live_validation.ipv6_leak_test.run_command")
    def test_disabled_when_empty_output(self, mock_run):
        mock_run.return_value = CommandResult(
            "ip -6 addr show scope global", 0, "", "", 1.0,
        )
        assert detect_ipv6_enabled() is False


class TestGetIpv6Addresses:
    @patch("dev_tools.sandbox.live_validation.ipv6_leak_test.run_command")
    def test_parses_addresses(self, mock_run):
        output = (
            "1: lo: <LOOPBACK>\n"
            "    inet6 ::1/128 scope host\n"
            "2: ens3: <BROADCAST>\n"
            "    inet6 2001:db8::1/64 scope global\n"
            "    inet6 fe80::1/64 scope link\n"
        )
        mock_run.return_value = CommandResult("ip -6 addr show", 0, output, "", 1.0)
        addrs = get_ipv6_addresses()
        assert len(addrs) == 3
        assert addrs[0].interface == "lo"
        assert addrs[0].scope == "host"
        assert addrs[1].interface == "ens3"
        assert addrs[1].address == "2001:db8::1"
        assert addrs[1].scope == "global"
        assert addrs[2].scope == "link"

    @patch("dev_tools.sandbox.live_validation.ipv6_leak_test.run_command")
    def test_empty_on_failure(self, mock_run):
        mock_run.return_value = CommandResult("ip -6 addr show", 1, "", "error", 1.0)
        assert get_ipv6_addresses() == []


class TestCheckIpv6RouteDevice:
    @patch("dev_tools.sandbox.live_validation.ipv6_leak_test.run_command")
    def test_returns_device(self, mock_run):
        mock_run.return_value = CommandResult(
            "ip -6 route show default", 0,
            "default via fe80::1 dev wg0 metric 1024", "", 1.0,
        )
        assert check_ipv6_route_device() == "wg0"

    @patch("dev_tools.sandbox.live_validation.ipv6_leak_test.run_command")
    def test_empty_on_no_route(self, mock_run):
        mock_run.return_value = CommandResult(
            "ip -6 route show default", 0, "", "", 1.0,
        )
        assert check_ipv6_route_device() == ""


class TestCheckIpv6Disabled:
    @patch("dev_tools.sandbox.live_validation.ipv6_leak_test.run_command")
    def test_disabled_when_sysctl_1(self, mock_run):
        mock_run.return_value = CommandResult("sysctl", 0, "1", "", 1.0)
        assert check_ipv6_disabled_on_tunnel() is True

    @patch("dev_tools.sandbox.live_validation.ipv6_leak_test.run_command")
    def test_enabled_when_sysctl_0(self, mock_run):
        mock_run.return_value = CommandResult("sysctl", 0, "0", "", 1.0)
        assert check_ipv6_disabled_on_tunnel() is False


class TestRunIpv6LeakTest:
    @patch("dev_tools.sandbox.live_validation.ipv6_leak_test.check_ipv6_disabled_on_tunnel")
    @patch("dev_tools.sandbox.live_validation.ipv6_leak_test.get_ipv6_addresses")
    @patch("dev_tools.sandbox.live_validation.ipv6_leak_test.detect_ipv6_enabled")
    def test_pass_when_ipv6_disabled(self, mock_enabled, mock_addrs, mock_sysctl):
        mock_enabled.return_value = False
        mock_addrs.return_value = []
        report = run_ipv6_leak_test(tunnel_interface="wg0")
        assert report.verdict == "PASS"
        assert report.leak_detected is False

    def test_skip_when_tunnel_not_active(self):
        report = run_ipv6_leak_test(tunnel_interface="wg0", tunnel_active=False)
        assert report.verdict == "SKIP"

    @patch("dev_tools.sandbox.live_validation.ipv6_leak_test.probe_ipv6_public_ip")
    @patch("dev_tools.sandbox.live_validation.ipv6_leak_test.check_ipv6_route_device")
    @patch("dev_tools.sandbox.live_validation.ipv6_leak_test.check_ipv6_disabled_on_tunnel")
    @patch("dev_tools.sandbox.live_validation.ipv6_leak_test.get_ipv6_addresses")
    @patch("dev_tools.sandbox.live_validation.ipv6_leak_test.detect_ipv6_enabled")
    def test_pass_when_probe_blocked(self, mock_en, mock_addr, mock_sys, mock_route, mock_probe):
        mock_en.return_value = True
        mock_addr.return_value = [IPv6Address("ens3", "2001:db8::1", "global")]
        mock_sys.return_value = False
        mock_route.return_value = "ens3"
        mock_probe.return_value = (False, "")
        report = run_ipv6_leak_test(tunnel_interface="wg0")
        assert report.verdict == "PASS"
        assert report.leak_reason == "ipv6_probe_blocked"


class TestIpv6LeakReport:
    def test_to_dict(self):
        r = IPv6LeakReport(verdict="PASS", ipv6_enabled=False)
        d = r.to_dict()
        assert d["verdict"] == "PASS"
        assert d["ipv6_enabled"] is False
        assert "baseline_addresses" in d
