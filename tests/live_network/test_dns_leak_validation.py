"""CI-safe unit tests for DNS leak detection logic.

These tests exercise the detection logic without requiring root,
a live tunnel, or network access.
"""

from __future__ import annotations

from unittest.mock import patch

from dev_tools.sandbox.live_validation.common import (
    evaluate_dns_leak,
    parse_nameservers,
)
from dev_tools.sandbox.live_validation.dns_leak_test import (
    DnsLeakReport,
    ResolverSnapshot,
    RouteCheck,
    VPN_DNS_SERVERS,
    _parse_resolvectl_dns,
    capture_resolver_snapshot,
    check_dns_routes,
    check_resolver_matches_vpn,
    check_resolvers_reverted,
    run_dns_queries,
)


# ---------------------------------------------------------------------------
# Resolver snapshot parsing
# ---------------------------------------------------------------------------


class TestParseResolvectlDns:
    def test_parses_link_and_global_entries(self):
        output = (
            "Global: 127.0.0.53\n"
            "Link 2 (ens3): 94.140.14.14 94.140.15.15\n"
            "Link 3 (wg0): 94.140.14.14\n"
        )
        result = _parse_resolvectl_dns(output)
        assert "127.0.0.53" in result
        assert "94.140.14.14" in result
        assert "94.140.15.15" in result

    def test_empty_output(self):
        assert _parse_resolvectl_dns("") == []

    def test_ignores_non_ip_tokens(self):
        output = "Link 2 (ens3): some-hostname 94.140.14.14\n"
        result = _parse_resolvectl_dns(output)
        assert result == ["94.140.14.14"]


class TestResolverSnapshot:
    def test_all_nameservers_deduplicates(self):
        snap = ResolverSnapshot(
            resolv_conf=["127.0.0.53", "94.140.14.14"],
            resolvectl_dns=["94.140.14.14", "94.140.15.15"],
        )
        ns = snap.all_nameservers()
        assert ns == ["127.0.0.53", "94.140.14.14", "94.140.15.15"]

    def test_empty_snapshot(self):
        snap = ResolverSnapshot()
        assert snap.all_nameservers() == []


# ---------------------------------------------------------------------------
# Resolver match checking
# ---------------------------------------------------------------------------


class TestCheckResolverMatchesVpn:
    def test_pass_when_only_vpn_dns(self):
        snap = ResolverSnapshot(resolv_conf=["94.140.14.14", "94.140.15.15"])
        ok, leaked = check_resolver_matches_vpn(snap, VPN_DNS_SERVERS)
        assert ok is True
        assert leaked == []

    def test_pass_with_loopback_and_vpn_dns(self):
        snap = ResolverSnapshot(resolv_conf=["127.0.0.53", "94.140.14.14"])
        ok, leaked = check_resolver_matches_vpn(snap, VPN_DNS_SERVERS)
        assert ok is True
        assert leaked == []

    def test_fail_with_public_non_vpn_dns(self):
        snap = ResolverSnapshot(resolv_conf=["8.8.8.8"])
        ok, leaked = check_resolver_matches_vpn(snap, VPN_DNS_SERVERS)
        assert ok is False
        assert "8.8.8.8" in leaked

    def test_fail_with_mixed_vpn_and_public(self):
        snap = ResolverSnapshot(resolv_conf=["94.140.14.14", "1.1.1.1"])
        ok, leaked = check_resolver_matches_vpn(snap, VPN_DNS_SERVERS)
        assert ok is False
        assert "1.1.1.1" in leaked


# ---------------------------------------------------------------------------
# Route checking
# ---------------------------------------------------------------------------


class TestCheckDnsRoutes:
    @patch("dev_tools.sandbox.live_validation.dns_leak_test.run_command")
    def test_pass_when_route_goes_through_wg(self, mock_run):
        from dev_tools.sandbox.live_validation.common import CommandResult

        mock_run.return_value = CommandResult(
            command="ip route get 94.140.14.14",
            returncode=0,
            stdout="94.140.14.14 dev wg0 src 10.88.0.2 uid 0",
            stderr="",
            duration_ms=1.0,
        )
        checks = check_dns_routes({"94.140.14.14"})
        assert len(checks) == 1
        assert checks[0].goes_through_vpn is True
        assert checks[0].device == "wg0"

    @patch("dev_tools.sandbox.live_validation.dns_leak_test.run_command")
    def test_fail_when_route_goes_through_eth(self, mock_run):
        from dev_tools.sandbox.live_validation.common import CommandResult

        mock_run.return_value = CommandResult(
            command="ip route get 94.140.14.14",
            returncode=0,
            stdout="94.140.14.14 via 192.168.1.1 dev eth0 src 192.168.1.100",
            stderr="",
            duration_ms=1.0,
        )
        checks = check_dns_routes({"94.140.14.14"})
        assert len(checks) == 1
        assert checks[0].goes_through_vpn is False
        assert checks[0].device == "eth0"

    @patch("dev_tools.sandbox.live_validation.dns_leak_test.run_command")
    def test_custom_device_prefix(self, mock_run):
        from dev_tools.sandbox.live_validation.common import CommandResult

        mock_run.return_value = CommandResult(
            command="ip route get 94.140.14.14",
            returncode=0,
            stdout="94.140.14.14 dev swlive1 src 10.88.0.2 uid 0",
            stderr="",
            duration_ms=1.0,
        )
        checks = check_dns_routes({"94.140.14.14"}, expected_device_prefix="swlive")
        assert checks[0].goes_through_vpn is True


# ---------------------------------------------------------------------------
# DNS query verification
# ---------------------------------------------------------------------------


class TestRunDnsQueries:
    @patch("dev_tools.sandbox.live_validation.dns_leak_test.run_command")
    def test_parses_dig_output(self, mock_run):
        from dev_tools.sandbox.live_validation.common import CommandResult

        dig_output = (
            ";; ANSWER SECTION:\n"
            "example.com.\t\t86400\tIN\tA\t93.184.216.34\n"
            "\n"
            ";; Query time: 12 msec\n"
            ";; SERVER: 94.140.14.14#53(94.140.14.14)\n"
        )
        # First call: dig availability check.
        # Subsequent calls: dig queries.
        mock_run.side_effect = [
            CommandResult("command -v dig", 0, "/usr/bin/dig", "", 1.0),
            CommandResult("dig @94.140.14.14 example.com", 0, dig_output, "", 15.0),
        ]
        results = run_dns_queries(
            ["example.com"],
            ["94.140.14.14"],
        )
        assert len(results) == 1
        assert results[0].success is True
        assert results[0].answered_by == "94.140.14.14"
        assert results[0].query_time_ms == 12.0

    @patch("dev_tools.sandbox.live_validation.dns_leak_test.run_command")
    def test_handles_missing_dig(self, mock_run):
        from dev_tools.sandbox.live_validation.common import CommandResult

        mock_run.return_value = CommandResult("command -v dig", 1, "", "", 1.0)
        results = run_dns_queries(["example.com"], ["94.140.14.14"])
        assert len(results) == 1
        assert results[0].success is False


# ---------------------------------------------------------------------------
# Resolver revert check
# ---------------------------------------------------------------------------


class TestCheckResolversReverted:
    def test_pass_when_vpn_dns_removed(self):
        baseline = ResolverSnapshot(resolv_conf=["127.0.0.53"])
        current = ResolverSnapshot(resolv_conf=["127.0.0.53"])
        assert check_resolvers_reverted(baseline, current) is True

    def test_fail_when_vpn_dns_still_present(self):
        baseline = ResolverSnapshot(resolv_conf=["127.0.0.53"])
        current = ResolverSnapshot(resolv_conf=["94.140.14.14", "127.0.0.53"])
        assert check_resolvers_reverted(baseline, current) is False

    def test_pass_when_baseline_restored(self):
        baseline = ResolverSnapshot(resolv_conf=["8.8.8.8", "8.8.4.4"])
        current = ResolverSnapshot(resolv_conf=["8.8.8.8"])
        assert check_resolvers_reverted(baseline, current) is True


# ---------------------------------------------------------------------------
# Report structure
# ---------------------------------------------------------------------------


class TestDnsLeakReport:
    def test_to_dict_returns_all_fields(self):
        report = DnsLeakReport(
            verdict="PASS",
            resolver_check="PASS",
            route_check_verdict="PASS",
            query_verdict="PASS",
            revert_check="PASS",
            leak_detected=False,
        )
        d = report.to_dict()
        assert d["verdict"] == "PASS"
        assert d["leak_detected"] is False
        assert "baseline_resolvers" in d
        assert "tunnel_resolvers" in d
        assert "route_checks" in d
        assert "query_results" in d

    def test_defaults_to_untested(self):
        report = DnsLeakReport()
        assert report.verdict == "UNTESTED"
        assert report.resolver_check == "UNTESTED"


# ---------------------------------------------------------------------------
# evaluate_dns_leak (common.py — additional coverage)
# ---------------------------------------------------------------------------


class TestEvaluateDnsLeak:
    def test_private_ips_allowed_by_default(self):
        ok, leaked = evaluate_dns_leak(
            ["127.0.0.53", "10.0.0.1", "94.140.14.14"],
            {"94.140.14.14", "94.140.15.15"},
        )
        assert ok is True
        assert leaked == []

    def test_private_ips_rejected_when_disabled(self):
        ok, leaked = evaluate_dns_leak(
            ["10.0.0.1"],
            {"94.140.14.14"},
            allow_private=False,
        )
        assert ok is False
        assert "10.0.0.1" in leaked

    def test_empty_observed_is_clean(self):
        ok, leaked = evaluate_dns_leak([], {"94.140.14.14"})
        assert ok is True
        assert leaked == []
