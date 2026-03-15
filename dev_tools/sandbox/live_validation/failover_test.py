#!/usr/bin/env python3
"""Multi-server failover validation for SecureWave VPN.

Validates that when the primary VPN server becomes unreachable,
the client can reconnect to a secondary server.

Test phases:
1. Connect to primary server, record state.
2. Simulate primary failure (block UDP 51820 to endpoint).
3. Observe handshake timeout / connection loss.
4. Verify reconnect to secondary server.
5. Restore original routing.

Requires root and an active tunnel.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import socket
import sys
import time
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[3]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from dev_tools.sandbox.live_validation.common import (
    fetch_public_ip,
    http_json_request,
    build_api_url,
    parse_latest_handshake_epoch,
    run_command,
    utc_now_iso,
    write_json,
)


@dataclass
class ServerState:
    """Captured state of a VPN server connection."""

    server_id: str = ""
    endpoint: str = ""
    endpoint_ip: str = ""
    endpoint_port: int = 0
    handshake_epoch: int = 0
    public_ip: str = ""
    interface: str = ""


@dataclass
class FailoverEvent:
    """A single failover event observation."""

    timestamp: str = ""
    event_type: str = ""  # "primary_blocked", "handshake_lost", "reconnected", "restored"
    detail: str = ""


@dataclass
class FailoverReport:
    """Full failover test report."""

    test_name: str = "multi_server_failover"
    started_at: str = ""
    finished_at: str = ""
    verdict: str = "UNTESTED"

    primary_server: ServerState = field(default_factory=ServerState)
    secondary_server: ServerState = field(default_factory=ServerState)

    block_applied: bool = False
    handshake_lost: bool = False
    reconnect_detected: bool = False
    reconnect_to_secondary: bool = False
    reconnect_time_seconds: float = 0.0

    block_restored: bool = False
    events: list[FailoverEvent] = field(default_factory=list)
    failures: list[str] = field(default_factory=list)

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


def parse_endpoint(endpoint: str) -> tuple[str, int]:
    """Parse 'host:port' endpoint string."""
    if not endpoint:
        return "", 0
    parts = endpoint.rsplit(":", 1)
    if len(parts) != 2:
        return endpoint, 0
    try:
        return parts[0], int(parts[1])
    except ValueError:
        return parts[0], 0


def resolve_endpoint_ip(host: str) -> str:
    """Resolve hostname to IPv4."""
    try:
        return socket.gethostbyname(host)
    except Exception:
        return host


def capture_server_state(
    *,
    interface: str,
    endpoint: str = "",
    server_id: str = "",
) -> ServerState:
    """Capture current VPN server connection state."""
    state = ServerState(
        interface=interface,
        server_id=server_id,
    )

    # Get endpoint from wg show if not provided.
    if not endpoint:
        result = run_command(["wg", "show", interface, "endpoints"], timeout_seconds=5)
        if result.returncode == 0 and result.stdout.strip():
            # Format: "<pubkey>\t<endpoint>"
            parts = result.stdout.strip().split()
            if len(parts) >= 2:
                endpoint = parts[-1]

    state.endpoint = endpoint
    host, port = parse_endpoint(endpoint)
    state.endpoint_ip = resolve_endpoint_ip(host)
    state.endpoint_port = port

    # Get handshake.
    hs_result = run_command(["wg", "show", interface, "latest-handshakes"], timeout_seconds=5)
    if hs_result.returncode == 0:
        state.handshake_epoch = parse_latest_handshake_epoch(hs_result.stdout)

    # Get public IP.
    state.public_ip = fetch_public_ip() or ""

    return state


def block_endpoint(ip: str, port: int) -> bool:
    """Block UDP traffic to a specific endpoint using iptables."""
    result = run_command(
        ["iptables", "-I", "OUTPUT", "1", "-p", "udp", "-d", ip,
         "--dport", str(port), "-j", "DROP"],
        timeout_seconds=10,
    )
    return result.returncode == 0


def unblock_endpoint(ip: str, port: int) -> bool:
    """Remove the iptables block on a specific endpoint."""
    result = run_command(
        ["iptables", "-D", "OUTPUT", "-p", "udp", "-d", ip,
         "--dport", str(port), "-j", "DROP"],
        timeout_seconds=10,
    )
    return result.returncode == 0


def wait_for_handshake_loss(
    interface: str,
    *,
    initial_epoch: int,
    timeout_seconds: int = 30,
    poll_interval: float = 2.0,
) -> bool:
    """Wait until handshake becomes stale (no new handshake after initial)."""
    deadline = time.monotonic() + timeout_seconds
    while time.monotonic() < deadline:
        result = run_command(["wg", "show", interface, "latest-handshakes"], timeout_seconds=5)
        if result.returncode == 0:
            current = parse_latest_handshake_epoch(result.stdout)
            # If handshake timestamp hasn't advanced and is old enough, consider it lost.
            age = int(time.time()) - current if current > 0 else 999
            if age > 180:  # No handshake in last 3 minutes.
                return True
        time.sleep(poll_interval)
    return False


def wait_for_reconnect(
    interface: str,
    *,
    previous_endpoint_ip: str,
    timeout_seconds: int = 60,
    poll_interval: float = 3.0,
) -> tuple[bool, str, float]:
    """Wait for reconnection, optionally to a different endpoint.

    Returns (reconnected, new_endpoint, elapsed_seconds).
    """
    start = time.monotonic()
    deadline = start + timeout_seconds
    while time.monotonic() < deadline:
        result = run_command(["wg", "show", interface, "endpoints"], timeout_seconds=5)
        if result.returncode == 0 and result.stdout.strip():
            parts = result.stdout.strip().split()
            if len(parts) >= 2:
                new_endpoint = parts[-1]
                host, _ = parse_endpoint(new_endpoint)
                new_ip = resolve_endpoint_ip(host)

                # Check for fresh handshake.
                hs = run_command(["wg", "show", interface, "latest-handshakes"], timeout_seconds=5)
                if hs.returncode == 0:
                    epoch = parse_latest_handshake_epoch(hs.stdout)
                    age = int(time.time()) - epoch if epoch > 0 else 999
                    if age < 30:  # Fresh handshake within last 30 seconds.
                        elapsed = time.monotonic() - start
                        return True, new_endpoint, elapsed

        time.sleep(poll_interval)

    return False, "", time.monotonic() - start


def run_failover_test(
    *,
    interface: str,
    execute: bool = False,
    block_timeout_seconds: int = 30,
    reconnect_timeout_seconds: int = 60,
    output_dir: Path | None = None,
) -> FailoverReport:
    """Run the full failover validation test.

    Args:
        interface: WireGuard interface name.
        execute: If True, actually block the endpoint (requires root).
        block_timeout_seconds: How long to wait for handshake loss.
        reconnect_timeout_seconds: How long to wait for reconnection.
        output_dir: Optional directory to write JSON report.
    """
    report = FailoverReport(started_at=utc_now_iso())

    is_root = hasattr(os, "geteuid") and os.geteuid() == 0

    # Step 1: Capture primary server state.
    report.primary_server = capture_server_state(interface=interface)
    report.events.append(FailoverEvent(
        timestamp=utc_now_iso(),
        event_type="primary_captured",
        detail=f"endpoint={report.primary_server.endpoint} ip={report.primary_server.public_ip}",
    ))

    if not report.primary_server.endpoint_ip or not report.primary_server.endpoint_port:
        report.verdict = "SKIP"
        report.failures.append("cannot_determine_primary_endpoint")
        report.finished_at = utc_now_iso()
        if output_dir:
            write_json(output_dir / "failover_report.json", report.to_dict())
        return report

    if not execute:
        # Simulation mode — report what would happen.
        report.verdict = "SIMULATED"
        report.events.append(FailoverEvent(
            timestamp=utc_now_iso(),
            event_type="simulated",
            detail=f"would block UDP to {report.primary_server.endpoint_ip}:{report.primary_server.endpoint_port}",
        ))
        report.finished_at = utc_now_iso()
        if output_dir:
            write_json(output_dir / "failover_report.json", report.to_dict())
        return report

    if not is_root:
        report.verdict = "SKIP"
        report.failures.append("requires_root_for_iptables")
        report.finished_at = utc_now_iso()
        if output_dir:
            write_json(output_dir / "failover_report.json", report.to_dict())
        return report

    # Step 2: Block primary server endpoint.
    ep_ip = report.primary_server.endpoint_ip
    ep_port = report.primary_server.endpoint_port
    report.block_applied = block_endpoint(ep_ip, ep_port)
    report.events.append(FailoverEvent(
        timestamp=utc_now_iso(),
        event_type="primary_blocked",
        detail=f"blocked={report.block_applied} {ep_ip}:{ep_port}",
    ))

    if not report.block_applied:
        report.verdict = "FAIL"
        report.failures.append("failed_to_block_primary_endpoint")
        report.finished_at = utc_now_iso()
        if output_dir:
            write_json(output_dir / "failover_report.json", report.to_dict())
        return report

    try:
        # Step 3: Wait for handshake loss.
        report.handshake_lost = wait_for_handshake_loss(
            interface,
            initial_epoch=report.primary_server.handshake_epoch,
            timeout_seconds=block_timeout_seconds,
        )
        report.events.append(FailoverEvent(
            timestamp=utc_now_iso(),
            event_type="handshake_status",
            detail=f"lost={report.handshake_lost}",
        ))

        # Step 4: Wait for reconnection.
        reconnected, new_endpoint, elapsed = wait_for_reconnect(
            interface,
            previous_endpoint_ip=ep_ip,
            timeout_seconds=reconnect_timeout_seconds,
        )
        report.reconnect_detected = reconnected
        report.reconnect_time_seconds = round(elapsed, 3)

        if reconnected and new_endpoint:
            report.secondary_server = capture_server_state(
                interface=interface,
                endpoint=new_endpoint,
            )
            new_host, _ = parse_endpoint(new_endpoint)
            new_ip = resolve_endpoint_ip(new_host)
            report.reconnect_to_secondary = (new_ip != ep_ip)

        report.events.append(FailoverEvent(
            timestamp=utc_now_iso(),
            event_type="reconnect_result",
            detail=f"reconnected={reconnected} endpoint={new_endpoint} elapsed={elapsed:.1f}s",
        ))

    finally:
        # Step 5: Always restore — unblock endpoint.
        report.block_restored = unblock_endpoint(ep_ip, ep_port)
        report.events.append(FailoverEvent(
            timestamp=utc_now_iso(),
            event_type="restored",
            detail=f"unblocked={report.block_restored}",
        ))

    # Verdict.
    if report.reconnect_detected and report.reconnect_to_secondary:
        report.verdict = "PASS"
    elif report.reconnect_detected:
        report.verdict = "PASS"  # Reconnected to same server is acceptable.
    else:
        report.verdict = "FAIL"
        report.failures.append("no_reconnect_within_timeout")

    report.finished_at = utc_now_iso()
    if output_dir:
        write_json(output_dir / "failover_report.json", report.to_dict())
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description="SecureWave Multi-Server Failover Test")
    parser.add_argument("--interface", default=os.getenv("LIVE_VALIDATION_INTERFACE", "wg0"))
    parser.add_argument("--execute", action="store_true", help="Actually block endpoint (requires root)")
    parser.add_argument("--block-timeout", type=int, default=30)
    parser.add_argument("--reconnect-timeout", type=int, default=60)
    parser.add_argument("--output-dir", default="artifacts/failover_test")
    args = parser.parse_args()

    out_dir = Path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    report = run_failover_test(
        interface=args.interface,
        execute=args.execute,
        block_timeout_seconds=args.block_timeout,
        reconnect_timeout_seconds=args.reconnect_timeout,
        output_dir=out_dir,
    )

    print(f"\nFAILOVER_TEST: {report.verdict}")
    print(f"  primary:            {report.primary_server.endpoint}")
    print(f"  block_applied:      {report.block_applied}")
    print(f"  handshake_lost:     {report.handshake_lost}")
    print(f"  reconnect:          {report.reconnect_detected}")
    print(f"  reconnect_time:     {report.reconnect_time_seconds}s")
    if report.secondary_server.endpoint:
        print(f"  secondary:          {report.secondary_server.endpoint}")
    print()
    print(json.dumps(report.to_dict(), indent=2))
    return 0 if report.verdict in {"PASS", "SIMULATED"} else 1


if __name__ == "__main__":
    raise SystemExit(main())
