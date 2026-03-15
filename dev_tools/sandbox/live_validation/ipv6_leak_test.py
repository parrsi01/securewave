#!/usr/bin/env python3
"""IPv6 leak detection for SecureWave VPN tunnels.

Validates that IPv6 traffic either:
- Routes through the VPN tunnel, OR
- Is completely disabled/blocked while the tunnel is active.

An IPv6 leak occurs when IPv6 traffic bypasses the tunnel and uses the
host's native IPv6 connectivity, exposing the real IPv6 address.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[3]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from dev_tools.sandbox.live_validation.common import (
    run_command,
    utc_now_iso,
    write_json,
)


@dataclass
class IPv6Address:
    """A single IPv6 address on an interface."""

    interface: str = ""
    address: str = ""
    scope: str = ""  # global, link, host


@dataclass
class IPv6LeakReport:
    """Full IPv6 leak test report."""

    test_name: str = "ipv6_leak_detection"
    started_at: str = ""
    finished_at: str = ""
    verdict: str = "UNTESTED"  # PASS, FAIL, SKIP

    ipv6_enabled: bool = False
    baseline_addresses: list[IPv6Address] = field(default_factory=list)
    baseline_public_ipv6: str = ""

    tunnel_active: bool = False
    tunnel_interface: str = ""
    tunnel_ipv6_route_device: str = ""

    probe_ipv6: str = ""
    probe_success: bool = False

    leak_detected: bool = False
    leak_reason: str = ""
    failures: list[str] = field(default_factory=list)

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


def detect_ipv6_enabled() -> bool:
    """Check whether the host has any global-scope IPv6 addresses."""
    result = run_command(["ip", "-6", "addr", "show", "scope", "global"], timeout_seconds=5)
    return result.returncode == 0 and bool(result.stdout.strip())


def get_ipv6_addresses() -> list[IPv6Address]:
    """Parse all IPv6 addresses from the system."""
    result = run_command(["ip", "-6", "addr", "show"], timeout_seconds=5)
    if result.returncode != 0:
        return []

    addresses: list[IPv6Address] = []
    current_iface = ""
    for line in result.stdout.splitlines():
        # Interface line: "2: ens3: <BROADCAST..."
        iface_match = re.match(r"^\d+:\s+(\S+?):", line)
        if iface_match:
            current_iface = iface_match.group(1)
            continue

        # Address line: "    inet6 2001:db8::1/64 scope global"
        addr_match = re.search(r"inet6\s+([\da-fA-F:]+)/\d+\s+scope\s+(\S+)", line.strip())
        if addr_match and current_iface:
            addresses.append(IPv6Address(
                interface=current_iface,
                address=addr_match.group(1),
                scope=addr_match.group(2),
            ))

    return addresses


def probe_ipv6_public_ip(*, timeout_seconds: int = 8) -> tuple[bool, str]:
    """Attempt to fetch public IPv6 address via an external service."""
    result = run_command(
        ["curl", "-6", "--max-time", str(timeout_seconds), "-sS", "https://api64.ipify.org"],
        timeout_seconds=timeout_seconds + 3,
    )
    if result.returncode == 0 and result.stdout.strip():
        ip = result.stdout.strip()
        # Basic IPv6 validation.
        if ":" in ip:
            return True, ip
    return False, ""


def check_ipv6_route_device(*, expected_prefix: str = "wg") -> str:
    """Check which device the default IPv6 route uses."""
    result = run_command(["ip", "-6", "route", "show", "default"], timeout_seconds=5)
    if result.returncode != 0:
        return ""
    dev_match = re.search(r"\bdev\s+(\S+)", result.stdout)
    return dev_match.group(1) if dev_match else ""


def check_ipv6_disabled_on_tunnel() -> bool:
    """Check if IPv6 is disabled system-wide via sysctl (common VPN kill-switch approach)."""
    result = run_command(
        ["sysctl", "-n", "net.ipv6.conf.all.disable_ipv6"],
        timeout_seconds=5,
    )
    return result.returncode == 0 and result.stdout.strip() == "1"


def run_ipv6_leak_test(
    *,
    tunnel_interface: str | None = None,
    tunnel_active: bool = True,
    output_dir: Path | None = None,
) -> IPv6LeakReport:
    """Run the full IPv6 leak detection test.

    Args:
        tunnel_interface: WireGuard interface name (e.g. "wg0").
        tunnel_active: Whether the tunnel is currently up.
        output_dir: Optional directory to write JSON report.

    Returns:
        IPv6LeakReport with full results.
    """
    report = IPv6LeakReport(started_at=utc_now_iso())
    report.tunnel_active = tunnel_active
    report.tunnel_interface = tunnel_interface or ""

    if not tunnel_active:
        report.verdict = "SKIP"
        report.failures.append("tunnel_not_active")
        report.finished_at = utc_now_iso()
        return report

    # Step 1: Check if IPv6 is enabled.
    report.ipv6_enabled = detect_ipv6_enabled()
    report.baseline_addresses = get_ipv6_addresses()

    if not report.ipv6_enabled:
        # IPv6 disabled system-wide — no leak possible.
        report.verdict = "PASS"
        report.leak_detected = False
        report.leak_reason = "ipv6_disabled_on_host"
        report.finished_at = utc_now_iso()
        if output_dir:
            write_json(output_dir / "ipv6_leak_report.json", report.to_dict())
        return report

    # Step 2: Check if IPv6 is disabled via sysctl (VPN kill-switch).
    if check_ipv6_disabled_on_tunnel():
        report.verdict = "PASS"
        report.leak_detected = False
        report.leak_reason = "ipv6_disabled_via_sysctl"
        report.finished_at = utc_now_iso()
        if output_dir:
            write_json(output_dir / "ipv6_leak_report.json", report.to_dict())
        return report

    # Step 3: Check IPv6 default route device.
    device_prefix = "wg"
    if tunnel_interface:
        device_prefix = tunnel_interface.rstrip("0123456789") or "wg"
    route_device = check_ipv6_route_device(expected_prefix=device_prefix)
    report.tunnel_ipv6_route_device = route_device

    routes_through_vpn = route_device.startswith(device_prefix) if route_device else False

    # Step 4: Probe external IPv6 address.
    probe_ok, probe_ip = probe_ipv6_public_ip()
    report.probe_success = probe_ok
    report.probe_ipv6 = probe_ip

    if not probe_ok:
        # IPv6 probe failed — IPv6 traffic is blocked, which is safe.
        report.verdict = "PASS"
        report.leak_detected = False
        report.leak_reason = "ipv6_probe_blocked"
        report.finished_at = utc_now_iso()
        if output_dir:
            write_json(output_dir / "ipv6_leak_report.json", report.to_dict())
        return report

    # Step 5: Compare probe result against baseline.
    baseline_global_addrs = {
        a.address for a in report.baseline_addresses
        if a.scope == "global" and not a.interface.startswith(device_prefix)
    }

    if probe_ip in baseline_global_addrs:
        # IPv6 exit IP matches a non-VPN interface address — leak.
        report.leak_detected = True
        report.leak_reason = f"ipv6_exit_matches_baseline: {probe_ip}"
        report.verdict = "FAIL"
        report.failures.append(f"ipv6_leak: exit_ip={probe_ip} matches baseline non-VPN address")
    elif not routes_through_vpn:
        # IPv6 doesn't route through VPN but exit IP is different — suspicious.
        report.leak_detected = True
        report.leak_reason = f"ipv6_default_route_bypasses_vpn: dev={route_device}"
        report.verdict = "FAIL"
        report.failures.append(f"ipv6_route_bypass: default route dev={route_device}")
    else:
        report.verdict = "PASS"
        report.leak_detected = False
        report.leak_reason = "ipv6_routes_through_vpn"

    report.finished_at = utc_now_iso()
    if output_dir:
        write_json(output_dir / "ipv6_leak_report.json", report.to_dict())
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description="SecureWave IPv6 Leak Detection Test")
    parser.add_argument("--interface", default=os.getenv("DNS_LEAK_TEST_INTERFACE", ""))
    parser.add_argument("--output-dir", default="artifacts/ipv6_leak_test")
    args = parser.parse_args()

    interface = args.interface.strip()
    if not interface:
        result = run_command(["ip", "-o", "link", "show", "up"], timeout_seconds=5)
        for line in result.stdout.splitlines():
            parts = line.split(":", 2)
            if len(parts) >= 2:
                iface = parts[1].strip().split("@", 1)[0]
                if iface.startswith(("wg", "swlive")):
                    interface = iface
                    break

    if not interface:
        print("IPV6_LEAK_TEST: SKIP — no WireGuard interface detected")
        return 0

    out_dir = Path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    report = run_ipv6_leak_test(
        tunnel_interface=interface,
        tunnel_active=True,
        output_dir=out_dir,
    )

    print(f"\nIPV6_LEAK_TEST: {report.verdict}")
    print(f"  ipv6_enabled:       {report.ipv6_enabled}")
    print(f"  probe_success:      {report.probe_success}")
    print(f"  probe_ipv6:         {report.probe_ipv6}")
    print(f"  route_device:       {report.tunnel_ipv6_route_device}")
    print(f"  leak_detected:      {report.leak_detected}")
    print(f"  reason:             {report.leak_reason}")
    print()
    print(json.dumps(report.to_dict(), indent=2))
    return 0 if report.verdict == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
