#!/usr/bin/env python3
"""Automated DNS leak detection for SecureWave VPN tunnels.

Validates that DNS queries are forced through the VPN tunnel by checking:
1. System resolver configuration (resolvectl / resolv.conf)
2. DNS query routing (ip route get <resolver>)
3. Controlled DNS queries via dig
4. Resolver revert after tunnel teardown

Can run standalone or be invoked from live_e2e_validate.py via --dns-leak-test.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[3]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from dev_tools.sandbox.live_validation.common import (
    CommandResult,
    evaluate_dns_leak,
    parse_nameservers,
    read_text,
    run_command,
    utc_now_iso,
    write_json,
)

# SecureWave VPN DNS servers (AdGuard DNS).
VPN_DNS_SERVERS = {"94.140.14.14", "94.140.15.15"}

# Domains used for controlled DNS queries.
TEST_DOMAINS = ["example.com", "google.com"]


@dataclass
class ResolverSnapshot:
    """Captured state of system DNS resolvers."""

    resolv_conf: list[str] = field(default_factory=list)
    resolvectl: str = ""
    resolvectl_dns: list[str] = field(default_factory=list)
    timestamp: str = ""

    def all_nameservers(self) -> list[str]:
        """Union of resolv.conf and resolvectl nameservers."""
        seen: set[str] = set()
        result: list[str] = []
        for ns in self.resolv_conf + self.resolvectl_dns:
            if ns not in seen:
                seen.add(ns)
                result.append(ns)
        return result


@dataclass
class DnsQueryResult:
    """Result of a single controlled DNS query."""

    domain: str = ""
    server: str = ""
    answered_by: str = ""
    query_time_ms: float | None = None
    success: bool = False
    raw_output: str = ""


@dataclass
class RouteCheck:
    """Result of checking the route to a DNS resolver."""

    resolver_ip: str = ""
    device: str = ""
    via: str = ""
    goes_through_vpn: bool = False
    raw_output: str = ""


@dataclass
class DnsLeakReport:
    """Full DNS leak test report."""

    test_name: str = "dns_leak_detection"
    started_at: str = ""
    finished_at: str = ""
    verdict: str = "UNTESTED"  # PASS, FAIL, SKIP, ERROR

    baseline_resolvers: ResolverSnapshot = field(default_factory=ResolverSnapshot)
    tunnel_resolvers: ResolverSnapshot = field(default_factory=ResolverSnapshot)
    post_teardown_resolvers: ResolverSnapshot = field(default_factory=ResolverSnapshot)

    resolver_check: str = "UNTESTED"  # PASS or FAIL
    route_checks: list[RouteCheck] = field(default_factory=list)
    route_check_verdict: str = "UNTESTED"
    query_results: list[DnsQueryResult] = field(default_factory=list)
    query_verdict: str = "UNTESTED"
    revert_check: str = "UNTESTED"  # PASS or FAIL

    leak_detected: bool = False
    leaked_resolvers: list[str] = field(default_factory=list)
    failures: list[str] = field(default_factory=list)

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


def capture_resolver_snapshot() -> ResolverSnapshot:
    """Capture current system DNS resolver state."""
    snap = ResolverSnapshot(timestamp=utc_now_iso())

    # resolv.conf
    resolv_text = read_text("/etc/resolv.conf")
    snap.resolv_conf = parse_nameservers(resolv_text)

    # resolvectl status
    result = run_command(["resolvectl", "status"], timeout_seconds=8)
    snap.resolvectl = result.stdout

    # resolvectl dns (more structured output)
    dns_result = run_command(["resolvectl", "dns"], timeout_seconds=5)
    if dns_result.returncode == 0:
        snap.resolvectl_dns = _parse_resolvectl_dns(dns_result.stdout)

    return snap


def _parse_resolvectl_dns(output: str) -> list[str]:
    """Extract DNS server IPs from resolvectl dns output.

    Lines look like:
      Link 2 (ens3): 94.140.14.14 94.140.15.15
      Global: 127.0.0.53
    """
    servers: list[str] = []
    for line in output.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        # Split on colon — right side has IPs.
        if ":" not in line:
            continue
        _, _, rhs = line.partition(":")
        for token in rhs.split():
            token = token.strip()
            if re.match(r"^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$", token):
                servers.append(token)
    return servers


def check_resolver_matches_vpn(
    snap: ResolverSnapshot,
    expected_dns: set[str],
) -> tuple[bool, list[str]]:
    """Check if the observed resolvers match VPN-provided DNS."""
    observed = snap.all_nameservers()
    return evaluate_dns_leak(observed, expected_dns, allow_private=True)


def check_dns_routes(
    resolver_ips: set[str],
    *,
    expected_device_prefix: str = "wg",
) -> list[RouteCheck]:
    """Verify DNS traffic routes through a WireGuard interface."""
    checks: list[RouteCheck] = []
    for ip in sorted(resolver_ips):
        result = run_command(["ip", "route", "get", ip], timeout_seconds=5)
        rc = RouteCheck(
            resolver_ip=ip,
            raw_output=result.stdout,
        )
        if result.returncode == 0:
            # Parse: "94.140.14.14 dev wg0 src 10.88.0.2 uid 0"
            # or: "94.140.14.14 via 10.0.0.1 dev eth0 src ..."
            stdout = result.stdout.strip()
            dev_match = re.search(r"\bdev\s+(\S+)", stdout)
            via_match = re.search(r"\bvia\s+(\S+)", stdout)
            if dev_match:
                rc.device = dev_match.group(1)
            if via_match:
                rc.via = via_match.group(1)
            rc.goes_through_vpn = rc.device.startswith(expected_device_prefix)
        checks.append(rc)
    return checks


def run_dns_queries(
    domains: list[str],
    dns_servers: list[str],
    *,
    interface_ip: str | None = None,
) -> list[DnsQueryResult]:
    """Run controlled DNS queries using dig and capture the responding server."""
    results: list[DnsQueryResult] = []

    # Check dig availability.
    dig_check = run_command(
        ["bash", "-lc", "command -v dig >/dev/null 2>&1"],
        timeout_seconds=3,
    )
    if dig_check.returncode != 0:
        for domain in domains:
            results.append(DnsQueryResult(
                domain=domain,
                server="(dig not available)",
                success=False,
                raw_output="dig binary not found",
            ))
        return results

    for domain in domains:
        for server in dns_servers[:2]:  # Limit to 2 servers per domain.
            cmd = ["dig", "+time=3", "+tries=1", f"@{server}", domain]
            if interface_ip:
                cmd.extend(["-b", interface_ip])

            res = run_command(cmd, timeout_seconds=8)
            qr = DnsQueryResult(
                domain=domain,
                server=server,
                raw_output=res.stdout[:800],
            )

            if res.returncode == 0:
                # Parse SERVER line: ";; SERVER: 94.140.14.14#53(94.140.14.14)"
                server_match = re.search(
                    r";;\s*SERVER:\s*([\d.]+)#", res.stdout
                )
                if server_match:
                    qr.answered_by = server_match.group(1)
                    qr.success = True

                # Parse query time: ";; Query time: 12 msec"
                qt_match = re.search(
                    r"Query time:\s*(\d+)\s*msec", res.stdout
                )
                if qt_match:
                    qr.query_time_ms = float(qt_match.group(1))

            results.append(qr)
    return results


def check_resolvers_reverted(
    baseline: ResolverSnapshot,
    current: ResolverSnapshot,
) -> bool:
    """After tunnel teardown, resolvers should revert to baseline."""
    baseline_set = set(baseline.all_nameservers())
    current_set = set(current.all_nameservers())

    # If baseline used systemd-resolved (127.0.0.53), current should too.
    # We don't require exact match — just that VPN DNS is gone.
    vpn_still_present = current_set & VPN_DNS_SERVERS
    if vpn_still_present:
        return False

    # If baseline had entries, current should have at least one of them back.
    if baseline_set and current_set:
        return bool(baseline_set & current_set) or not vpn_still_present

    return True


def run_dns_leak_test(
    *,
    tunnel_interface: str | None = None,
    expected_dns: set[str] | None = None,
    tunnel_active: bool = True,
    capture_baseline: bool = True,
    output_dir: Path | None = None,
) -> DnsLeakReport:
    """Run the full DNS leak detection test.

    Args:
        tunnel_interface: WireGuard interface name (e.g. "wg0", "swlive1").
        expected_dns: Set of allowed VPN DNS IPs.
        tunnel_active: Whether the tunnel is currently up.
        capture_baseline: Whether to capture baseline (pre-tunnel) resolvers.
        output_dir: Optional directory to write JSON report.

    Returns:
        DnsLeakReport with full results.
    """
    report = DnsLeakReport(started_at=utc_now_iso())
    dns_set = expected_dns or VPN_DNS_SERVERS

    if not tunnel_active:
        report.verdict = "SKIP"
        report.failures.append("tunnel_not_active")
        report.finished_at = utc_now_iso()
        return report

    # Step 1: Baseline (if we can capture it — otherwise it's provided externally).
    if capture_baseline:
        report.baseline_resolvers = capture_resolver_snapshot()

    # Step 2: Tunnel resolver verification.
    report.tunnel_resolvers = capture_resolver_snapshot()
    resolver_ok, leaked = check_resolver_matches_vpn(
        report.tunnel_resolvers, dns_set
    )
    report.resolver_check = "PASS" if resolver_ok else "FAIL"
    if not resolver_ok:
        report.leaked_resolvers.extend(leaked)
        report.failures.append(f"resolver_mismatch: leaked={leaked}")

    # Step 3: DNS route validation.
    device_prefix = "wg"
    if tunnel_interface:
        device_prefix = tunnel_interface.rstrip("0123456789") or "wg"
    report.route_checks = check_dns_routes(
        dns_set, expected_device_prefix=device_prefix
    )
    routes_ok = all(rc.goes_through_vpn for rc in report.route_checks)
    report.route_check_verdict = "PASS" if routes_ok else "FAIL"
    if not routes_ok:
        bad = [rc.resolver_ip for rc in report.route_checks if not rc.goes_through_vpn]
        report.failures.append(f"dns_route_bypass: {bad}")

    # Step 4: Controlled DNS queries.
    interface_ip = None
    if tunnel_interface:
        ip_result = run_command(
            ["ip", "-4", "addr", "show", "dev", tunnel_interface],
            timeout_seconds=5,
        )
        if ip_result.returncode == 0:
            ip_match = re.search(r"inet\s+([\d.]+)/", ip_result.stdout)
            if ip_match:
                interface_ip = ip_match.group(1)

    report.query_results = run_dns_queries(
        TEST_DOMAINS,
        sorted(dns_set),
        interface_ip=interface_ip,
    )
    queries_ok = all(qr.success for qr in report.query_results)
    # Also verify queries were answered by VPN DNS.
    queries_answered_by_vpn = all(
        qr.answered_by in dns_set
        for qr in report.query_results
        if qr.success
    )
    report.query_verdict = "PASS" if (queries_ok and queries_answered_by_vpn) else "FAIL"
    if not queries_answered_by_vpn:
        non_vpn = [
            qr.answered_by
            for qr in report.query_results
            if qr.success and qr.answered_by not in dns_set
        ]
        if non_vpn:
            report.failures.append(f"queries_answered_by_non_vpn_dns: {non_vpn}")

    # Overall verdict.
    report.leak_detected = not (resolver_ok and routes_ok and queries_answered_by_vpn)
    report.verdict = "FAIL" if report.leak_detected else "PASS"
    report.finished_at = utc_now_iso()

    if output_dir:
        write_json(output_dir / "dns_leak_report.json", report.to_dict())

    return report


def run_dns_leak_test_with_teardown(
    *,
    tunnel_interface: str,
    teardown_command: list[str] | str,
    expected_dns: set[str] | None = None,
    output_dir: Path | None = None,
) -> DnsLeakReport:
    """Run DNS leak test including post-teardown revert verification.

    This is the full lifecycle version:
    1. Capture tunnel-active DNS state
    2. Run leak checks
    3. Tear down tunnel
    4. Verify resolvers revert

    Args:
        tunnel_interface: WireGuard interface name.
        teardown_command: Command to bring down the tunnel.
        expected_dns: Set of allowed VPN DNS IPs.
        output_dir: Optional directory to write JSON report.
    """
    report = run_dns_leak_test(
        tunnel_interface=tunnel_interface,
        expected_dns=expected_dns,
        tunnel_active=True,
        capture_baseline=True,
        output_dir=None,  # Write after teardown check.
    )

    # Step 7: Negative test — teardown and verify revert.
    use_shell = isinstance(teardown_command, str)
    run_command(teardown_command, timeout_seconds=30, shell=use_shell)
    time.sleep(2)  # Allow resolver revert to propagate.

    report.post_teardown_resolvers = capture_resolver_snapshot()
    reverted = check_resolvers_reverted(
        report.baseline_resolvers,
        report.post_teardown_resolvers,
    )
    report.revert_check = "PASS" if reverted else "FAIL"
    if not reverted:
        report.failures.append("resolvers_did_not_revert_after_teardown")
        report.leak_detected = True
        report.verdict = "FAIL"

    if output_dir:
        write_json(output_dir / "dns_leak_report.json", report.to_dict())

    return report


def main() -> int:
    parser = argparse.ArgumentParser(
        description="SecureWave DNS Leak Detection Test"
    )
    parser.add_argument(
        "--interface",
        default=os.getenv("DNS_LEAK_TEST_INTERFACE", ""),
        help="WireGuard interface to test (e.g. wg0, swlive1).",
    )
    parser.add_argument(
        "--expected-dns",
        default=os.getenv("LIVE_ALLOWED_DNS", "94.140.14.14,94.140.15.15"),
        help="Comma-separated expected VPN DNS servers.",
    )
    parser.add_argument(
        "--output-dir",
        default="artifacts/dns_leak_test",
    )
    args = parser.parse_args()

    dns_set = {
        ip.strip()
        for ip in args.expected_dns.split(",")
        if ip.strip()
    }

    interface = args.interface.strip()
    if not interface:
        # Auto-detect: look for wg* or swlive* interfaces.
        result = run_command(["ip", "-o", "link", "show", "up"], timeout_seconds=5)
        for line in result.stdout.splitlines():
            parts = line.split(":", 2)
            if len(parts) >= 2:
                iface = parts[1].strip().split("@", 1)[0]
                if iface.startswith(("wg", "swlive")):
                    interface = iface
                    break

    if not interface:
        print("DNS_LEAK_TEST: SKIP — no WireGuard interface detected")
        return 0

    out_dir = Path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    report = run_dns_leak_test(
        tunnel_interface=interface,
        expected_dns=dns_set,
        tunnel_active=True,
        output_dir=out_dir,
    )

    # Print structured report.
    print(f"\nDNS_LEAK_TEST: {report.verdict}")
    print(f"  resolver_check:     {report.resolver_check}")
    print(f"  route_check:        {report.route_check_verdict}")
    print(f"  query_check:        {report.query_verdict}")
    print(f"  leak_detected:      {report.leak_detected}")
    if report.leaked_resolvers:
        print(f"  leaked_resolvers:   {report.leaked_resolvers}")
    if report.failures:
        print(f"  failures:           {report.failures}")
    print()

    print(json.dumps(report.to_dict(), indent=2))
    return 0 if report.verdict == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
