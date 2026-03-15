#!/usr/bin/env python3
"""DPI resistance and anti-censorship validation for SecureWave VPN.

Tests whether the WireGuard tunnel is identifiable or blockable by
Deep Packet Inspection systems through four test categories:

1. WireGuard fingerprint detection — packet size/timing analysis
2. Port blocking simulation — resilience when UDP 51820 is blocked
3. UDP throttling — handshake stability under packet loss
4. Traffic pattern detection — entropy and burst analysis

Requires root for tcpdump captures and tc/iptables operations.
Can run in simulation mode without root.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import re
import struct
import sys
import time
from collections import Counter
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

# Known WireGuard handshake packet sizes (RFC 8439 / Noise IK pattern).
# Initiation: 148 bytes, Response: 92 bytes, Cookie: 64 bytes.
WG_HANDSHAKE_INITIATION_SIZE = 148
WG_HANDSHAKE_RESPONSE_SIZE = 92
WG_HANDSHAKE_COOKIE_SIZE = 64
WG_KNOWN_SIZES = {WG_HANDSHAKE_INITIATION_SIZE, WG_HANDSHAKE_RESPONSE_SIZE, WG_HANDSHAKE_COOKIE_SIZE}

# WireGuard message type bytes (first 4 bytes of UDP payload).
WG_MSG_TYPE_INITIATION = 1
WG_MSG_TYPE_RESPONSE = 2
WG_MSG_TYPE_COOKIE = 3
WG_MSG_TYPE_DATA = 4


@dataclass
class PacketMeta:
    """Metadata for a single captured packet."""

    timestamp: float = 0.0
    size: int = 0
    src_ip: str = ""
    dst_ip: str = ""
    src_port: int = 0
    dst_port: int = 0
    udp_payload_size: int = 0


@dataclass
class FingerprintResult:
    """WireGuard fingerprint detection result."""

    verdict: str = "UNTESTED"
    packets_captured: int = 0
    handshake_signature_match: bool = False
    initiation_count: int = 0
    response_count: int = 0
    cookie_count: int = 0
    known_size_ratio: float = 0.0
    packet_sizes: list[int] = field(default_factory=list)
    detail: str = ""


@dataclass
class PortBlockResult:
    """Port blocking resilience result."""

    verdict: str = "UNTESTED"
    block_applied: bool = False
    block_restored: bool = False
    connection_attempted: bool = False
    connection_failed_as_expected: bool = False
    fallback_behavior: str = ""
    detail: str = ""


@dataclass
class ThrottleResult:
    """UDP throttling resilience result."""

    verdict: str = "UNTESTED"
    qdisc_applied: bool = False
    qdisc_restored: bool = False
    loss_percent: int = 0
    handshake_survived: bool = False
    latency_ms_before: float | None = None
    latency_ms_during: float | None = None
    detail: str = ""


@dataclass
class TrafficPatternResult:
    """Traffic pattern entropy analysis result."""

    verdict: str = "UNTESTED"
    packets_analyzed: int = 0
    size_entropy: float = 0.0
    interval_entropy: float = 0.0
    combined_entropy: float = 0.0
    size_variance: float = 0.0
    burst_count: int = 0
    avg_interval_ms: float = 0.0
    identifiable: bool = False
    detail: str = ""


@dataclass
class DpiResistanceReport:
    """Full DPI resistance test report."""

    test_name: str = "dpi_resistance"
    started_at: str = ""
    finished_at: str = ""
    verdict: str = "UNTESTED"

    tunnel_interface: str = ""
    endpoint_port: int = 51820
    execute: bool = False

    fingerprint: FingerprintResult = field(default_factory=FingerprintResult)
    port_block: PortBlockResult = field(default_factory=PortBlockResult)
    throttle: ThrottleResult = field(default_factory=ThrottleResult)
    traffic_pattern: TrafficPatternResult = field(default_factory=TrafficPatternResult)

    failures: list[str] = field(default_factory=list)

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


# ---------------------------------------------------------------------------
# Entropy / statistics helpers
# ---------------------------------------------------------------------------


def shannon_entropy(values: list[int | float]) -> float:
    """Calculate Shannon entropy of a distribution.

    Higher entropy = more random = harder to fingerprint.
    Returns value in range [0, log2(n)] where n is number of distinct values.
    Normalized to [0, 1] by dividing by log2(len(values)) if len > 1.
    """
    if not values:
        return 0.0
    total = len(values)
    counts = Counter(values)
    probs = [count / total for count in counts.values()]
    raw_entropy = -sum(p * math.log2(p) for p in probs if p > 0)
    # Normalize.
    max_entropy = math.log2(total) if total > 1 else 1.0
    return round(raw_entropy / max_entropy, 6) if max_entropy > 0 else 0.0


def variance(values: list[float]) -> float:
    """Calculate population variance."""
    if len(values) < 2:
        return 0.0
    mean = sum(values) / len(values)
    return sum((v - mean) ** 2 for v in values) / len(values)


def count_bursts(intervals_ms: list[float], *, threshold_ms: float = 5.0) -> int:
    """Count burst groups where inter-packet interval < threshold."""
    if not intervals_ms:
        return 0
    bursts = 0
    in_burst = False
    for interval in intervals_ms:
        if interval < threshold_ms:
            if not in_burst:
                bursts += 1
                in_burst = True
        else:
            in_burst = False
    return bursts


def bucket_sizes(sizes: list[int], *, bucket_width: int = 16) -> list[int]:
    """Bucket packet sizes for entropy calculation.

    Reduces noise from padding while preserving size distribution shape.
    """
    return [s // bucket_width * bucket_width for s in sizes]


# ---------------------------------------------------------------------------
# Packet capture and parsing
# ---------------------------------------------------------------------------


def parse_tcpdump_text(output: str) -> list[PacketMeta]:
    """Parse tcpdump -nn -q output lines into PacketMeta.

    Expected format (simplified):
      12:34:56.789012 IP 1.2.3.4.51820 > 5.6.7.8.12345: UDP, length 148
    """
    packets: list[PacketMeta] = []
    for line in output.splitlines():
        line = line.strip()
        if not line or "UDP" not in line:
            continue

        # Extract timestamp.
        ts_match = re.match(r"(\d{2}:\d{2}:\d{2}\.\d+)", line)
        timestamp = 0.0
        if ts_match:
            parts = ts_match.group(1).split(":")
            try:
                timestamp = float(parts[0]) * 3600 + float(parts[1]) * 60 + float(parts[2])
            except (ValueError, IndexError):
                pass

        # Extract src/dst.
        addr_match = re.search(
            r"(\d+\.\d+\.\d+\.\d+)\.(\d+)\s+>\s+(\d+\.\d+\.\d+\.\d+)\.(\d+)",
            line,
        )
        src_ip = src_port = dst_ip = dst_port = ""
        if addr_match:
            src_ip = addr_match.group(1)
            src_port = int(addr_match.group(2))
            dst_ip = addr_match.group(3)
            dst_port = int(addr_match.group(4))

        # Extract length.
        len_match = re.search(r"length\s+(\d+)", line)
        udp_len = int(len_match.group(1)) if len_match else 0

        packets.append(PacketMeta(
            timestamp=timestamp,
            size=udp_len + 42,  # Approximate: 14 eth + 20 IP + 8 UDP + payload.
            src_ip=src_ip,
            dst_ip=dst_ip,
            src_port=src_port,
            dst_port=dst_port,
            udp_payload_size=udp_len,
        ))
    return packets


def classify_wg_handshake_packets(packets: list[PacketMeta]) -> dict[str, int]:
    """Classify packets by WireGuard handshake type based on UDP payload size."""
    counts = {"initiation": 0, "response": 0, "cookie": 0, "data": 0, "other": 0}
    for p in packets:
        if p.udp_payload_size == WG_HANDSHAKE_INITIATION_SIZE:
            counts["initiation"] += 1
        elif p.udp_payload_size == WG_HANDSHAKE_RESPONSE_SIZE:
            counts["response"] += 1
        elif p.udp_payload_size == WG_HANDSHAKE_COOKIE_SIZE:
            counts["cookie"] += 1
        elif p.udp_payload_size > 0:
            counts["data"] += 1
        else:
            counts["other"] += 1
    return counts


# ---------------------------------------------------------------------------
# Test category implementations
# ---------------------------------------------------------------------------


def check_fingerprint(
    interface: str,
    *,
    port: int = 51820,
    capture_count: int = 50,
    capture_timeout: int = 15,
    execute: bool = False,
) -> FingerprintResult:
    """Category 1: WireGuard fingerprint detection via packet capture."""
    result = FingerprintResult()

    if not execute:
        result.verdict = "SIMULATED"
        result.detail = "would capture packets and analyze WireGuard fingerprint"
        return result

    # Capture packets with tcpdump.
    cap = run_command(
        ["tcpdump", "-i", "any", "-nn", "-q",
         f"udp port {port}", "-c", str(capture_count)],
        timeout_seconds=capture_timeout + 5,
    )

    if cap.returncode != 0 and not cap.stdout.strip():
        result.verdict = "SKIP"
        result.detail = f"tcpdump failed: {cap.stderr[:200]}"
        return result

    packets = parse_tcpdump_text(cap.stdout)
    result.packets_captured = len(packets)

    if not packets:
        result.verdict = "SKIP"
        result.detail = "no packets captured"
        return result

    # Classify packets.
    counts = classify_wg_handshake_packets(packets)
    result.initiation_count = counts["initiation"]
    result.response_count = counts["response"]
    result.cookie_count = counts["cookie"]
    result.packet_sizes = [p.udp_payload_size for p in packets]

    # Calculate known-size ratio.
    known_count = sum(
        1 for p in packets if p.udp_payload_size in WG_KNOWN_SIZES
    )
    result.known_size_ratio = round(known_count / len(packets), 4) if packets else 0.0

    # Signature match: if we see initiation+response pair with exact sizes.
    result.handshake_signature_match = (
        counts["initiation"] > 0 and counts["response"] > 0
    )

    # Verdict: detectable if signature matches and high ratio of known sizes.
    if result.handshake_signature_match and result.known_size_ratio > 0.3:
        result.verdict = "DETECTABLE"
        result.detail = (
            f"WireGuard handshake pattern detected: "
            f"{counts['initiation']} init, {counts['response']} resp, "
            f"known_size_ratio={result.known_size_ratio:.2%}"
        )
    else:
        result.verdict = "PASS"
        result.detail = "no clear WireGuard fingerprint in captured traffic"

    return result


def check_port_block(
    interface: str,
    *,
    port: int = 51820,
    execute: bool = False,
) -> PortBlockResult:
    """Category 2: Port blocking simulation."""
    result = PortBlockResult()

    if not execute:
        result.verdict = "SIMULATED"
        result.detail = f"would block UDP port {port} via iptables and test resilience"
        return result

    is_root = hasattr(os, "geteuid") and os.geteuid() == 0
    if not is_root:
        result.verdict = "SKIP"
        result.detail = "requires root for iptables"
        return result

    # Apply block.
    add = run_command(
        ["iptables", "-I", "OUTPUT", "1", "-p", "udp",
         "--dport", str(port), "-j", "DROP"],
        timeout_seconds=10,
    )
    result.block_applied = add.returncode == 0

    if not result.block_applied:
        result.verdict = "FAIL"
        result.detail = f"failed to apply iptables rule: {add.stderr[:200]}"
        return result

    try:
        result.connection_attempted = True

        # Check if WireGuard handshake fails (expected).
        time.sleep(3)
        wg = run_command(["wg", "show", interface, "latest-handshakes"], timeout_seconds=5)
        if wg.returncode == 0:
            # Parse handshake age.
            for line in wg.stdout.splitlines():
                parts = line.strip().split()
                if len(parts) >= 2:
                    try:
                        epoch = int(parts[1])
                        age = int(time.time()) - epoch
                        result.connection_failed_as_expected = age > 10
                    except ValueError:
                        pass
                    break

        if result.connection_failed_as_expected:
            result.verdict = "PASS"
            result.fallback_behavior = "handshake_blocked_as_expected"
            result.detail = "tunnel correctly unable to maintain handshake with port blocked"
        else:
            result.verdict = "INCONCLUSIVE"
            result.fallback_behavior = "handshake_still_active"
            result.detail = "handshake may still be active from pre-block state"

    finally:
        # Restore.
        rm = run_command(
            ["iptables", "-D", "OUTPUT", "-p", "udp",
             "--dport", str(port), "-j", "DROP"],
            timeout_seconds=10,
        )
        result.block_restored = rm.returncode == 0

    return result


def check_udp_throttle(
    interface: str,
    *,
    physical_interface: str = "eth0",
    loss_percent: int = 30,
    duration_seconds: int = 10,
    execute: bool = False,
) -> ThrottleResult:
    """Category 3: UDP throttling / packet loss simulation."""
    result = ThrottleResult(loss_percent=loss_percent)

    if not execute:
        result.verdict = "SIMULATED"
        result.detail = f"would apply {loss_percent}% packet loss via tc netem for {duration_seconds}s"
        return result

    is_root = hasattr(os, "geteuid") and os.geteuid() == 0
    if not is_root:
        result.verdict = "SKIP"
        result.detail = "requires root for tc qdisc"
        return result

    # Detect physical interface.
    if not physical_interface:
        route = run_command(["ip", "route", "show", "default"], timeout_seconds=5)
        dev_match = re.search(r"\bdev\s+(\S+)", route.stdout)
        physical_interface = dev_match.group(1) if dev_match else "eth0"

    # Baseline latency.
    ping_before = run_command(["ping", "-c", "3", "-W", "2", "1.1.1.1"], timeout_seconds=8)
    for line in ping_before.stdout.splitlines():
        if "min/avg" in line:
            try:
                result.latency_ms_before = float(line.split("=")[1].split("/")[1])
            except (IndexError, ValueError):
                pass
            break

    # Apply netem.
    add = run_command(
        ["tc", "qdisc", "add", "dev", physical_interface,
         "root", "netem", "loss", f"{loss_percent}%"],
        timeout_seconds=10,
    )
    result.qdisc_applied = add.returncode == 0

    if not result.qdisc_applied:
        result.verdict = "SKIP"
        result.detail = f"tc qdisc add failed: {add.stderr[:200]}"
        return result

    try:
        time.sleep(duration_seconds)

        # Check handshake.
        wg = run_command(["wg", "show", interface, "latest-handshakes"], timeout_seconds=5)
        if wg.returncode == 0:
            for line in wg.stdout.splitlines():
                parts = line.strip().split()
                if len(parts) >= 2:
                    try:
                        epoch = int(parts[1])
                        age = int(time.time()) - epoch
                        result.handshake_survived = age < 180
                    except ValueError:
                        pass
                    break

        # Latency during throttle.
        ping_during = run_command(["ping", "-c", "3", "-W", "3", "1.1.1.1"], timeout_seconds=12)
        for line in ping_during.stdout.splitlines():
            if "min/avg" in line:
                try:
                    result.latency_ms_during = float(line.split("=")[1].split("/")[1])
                except (IndexError, ValueError):
                    pass
                break

        result.verdict = "PASS" if result.handshake_survived else "FAIL"
        result.detail = (
            f"handshake_survived={result.handshake_survived} "
            f"latency_before={result.latency_ms_before}ms "
            f"latency_during={result.latency_ms_during}ms"
        )

    finally:
        rm = run_command(
            ["tc", "qdisc", "del", "dev", physical_interface, "root"],
            timeout_seconds=10,
        )
        result.qdisc_restored = rm.returncode == 0

    return result


def check_traffic_pattern(
    interface: str,
    *,
    port: int = 51820,
    capture_seconds: int = 10,
    execute: bool = False,
) -> TrafficPatternResult:
    """Category 4: Traffic pattern entropy analysis."""
    result = TrafficPatternResult()

    if not execute:
        result.verdict = "SIMULATED"
        result.detail = f"would capture {capture_seconds}s of traffic and analyze entropy"
        return result

    # Capture traffic.
    cap = run_command(
        ["timeout", str(capture_seconds + 2),
         "tcpdump", "-i", "any", "-nn", "-q",
         f"udp port {port}"],
        timeout_seconds=capture_seconds + 8,
    )

    packets = parse_tcpdump_text(cap.stdout)
    result.packets_analyzed = len(packets)

    if len(packets) < 5:
        result.verdict = "SKIP"
        result.detail = f"insufficient packets for analysis: {len(packets)}"
        return result

    # Size entropy.
    sizes = [p.udp_payload_size for p in packets]
    bucketed = bucket_sizes(sizes)
    result.size_entropy = shannon_entropy(bucketed)
    result.size_variance = round(variance([float(s) for s in sizes]), 2)

    # Interval entropy.
    timestamps = [p.timestamp for p in packets if p.timestamp > 0]
    intervals_ms: list[float] = []
    if len(timestamps) >= 2:
        intervals_ms = [
            round((timestamps[i + 1] - timestamps[i]) * 1000, 3)
            for i in range(len(timestamps) - 1)
            if timestamps[i + 1] > timestamps[i]
        ]
    if intervals_ms:
        bucketed_intervals = [int(i) // 5 * 5 for i in intervals_ms]
        result.interval_entropy = shannon_entropy(bucketed_intervals)
        result.avg_interval_ms = round(sum(intervals_ms) / len(intervals_ms), 3)

    # Combined entropy (geometric mean).
    if result.size_entropy > 0 and result.interval_entropy > 0:
        result.combined_entropy = round(
            math.sqrt(result.size_entropy * result.interval_entropy), 6
        )
    else:
        result.combined_entropy = max(result.size_entropy, result.interval_entropy)

    # Burst analysis.
    result.burst_count = count_bursts(intervals_ms)

    # Identifiability threshold.
    # Low entropy + matching known sizes = identifiable.
    known_ratio = sum(1 for s in sizes if s in WG_KNOWN_SIZES) / len(sizes)
    result.identifiable = result.combined_entropy < 0.3 and known_ratio > 0.2

    result.verdict = "DETECTABLE" if result.identifiable else "PASS"
    result.detail = (
        f"size_entropy={result.size_entropy:.4f} "
        f"interval_entropy={result.interval_entropy:.4f} "
        f"combined={result.combined_entropy:.4f} "
        f"variance={result.size_variance:.0f} "
        f"bursts={result.burst_count} "
        f"known_size_ratio={known_ratio:.2%}"
    )

    return result


# ---------------------------------------------------------------------------
# Main test runner
# ---------------------------------------------------------------------------


def run_dpi_resistance_test(
    *,
    tunnel_interface: str,
    endpoint_port: int = 51820,
    execute: bool = False,
    physical_interface: str = "",
    loss_percent: int = 30,
    capture_seconds: int = 10,
    output_dir: Path | None = None,
) -> DpiResistanceReport:
    """Run all DPI resistance tests.

    Args:
        tunnel_interface: WireGuard interface name.
        endpoint_port: UDP port used by WireGuard.
        execute: If True, run destructive tests (requires root).
        physical_interface: Physical NIC for tc netem (auto-detected if empty).
        loss_percent: Packet loss % for throttle test.
        capture_seconds: Duration for traffic pattern capture.
        output_dir: Optional directory to write JSON report.
    """
    report = DpiResistanceReport(
        started_at=utc_now_iso(),
        tunnel_interface=tunnel_interface,
        endpoint_port=endpoint_port,
        execute=execute,
    )

    # Category 1: Fingerprint detection.
    report.fingerprint = check_fingerprint(
        tunnel_interface,
        port=endpoint_port,
        execute=execute,
    )
    if report.fingerprint.verdict == "DETECTABLE":
        report.failures.append("wireguard_fingerprint_detectable")

    # Category 2: Port blocking.
    report.port_block = check_port_block(
        tunnel_interface,
        port=endpoint_port,
        execute=execute,
    )

    # Category 3: UDP throttling.
    report.throttle = check_udp_throttle(
        tunnel_interface,
        physical_interface=physical_interface,
        loss_percent=loss_percent,
        execute=execute,
    )
    if report.throttle.verdict == "FAIL":
        report.failures.append("handshake_failed_under_throttle")

    # Category 4: Traffic pattern.
    report.traffic_pattern = check_traffic_pattern(
        tunnel_interface,
        port=endpoint_port,
        capture_seconds=capture_seconds,
        execute=execute,
    )
    if report.traffic_pattern.verdict == "DETECTABLE":
        report.failures.append("traffic_pattern_identifiable")

    # Overall verdict.
    verdicts = [
        report.fingerprint.verdict,
        report.port_block.verdict,
        report.throttle.verdict,
        report.traffic_pattern.verdict,
    ]
    if any(v == "FAIL" for v in verdicts):
        report.verdict = "FAIL"
    elif any(v == "DETECTABLE" for v in verdicts):
        report.verdict = "DETECTABLE"
    elif all(v in {"SIMULATED", "SKIP"} for v in verdicts):
        report.verdict = "SIMULATED"
    else:
        report.verdict = "PASS"

    report.finished_at = utc_now_iso()
    if output_dir:
        write_json(output_dir / "dpi_resistance_report.json", report.to_dict())
    return report


def main() -> int:
    parser = argparse.ArgumentParser(
        description="SecureWave DPI Resistance / Anti-Censorship Test"
    )
    parser.add_argument(
        "--interface",
        default=os.getenv("DPI_TEST_INTERFACE", "wg0"),
    )
    parser.add_argument(
        "--port", type=int,
        default=int(os.getenv("DPI_TEST_PORT", "51820")),
    )
    parser.add_argument(
        "--execute", action="store_true",
        help="Run destructive tests (requires root).",
    )
    parser.add_argument(
        "--physical-interface",
        default=os.getenv("DPI_TEST_PHYSICAL_INTERFACE", ""),
        help="Physical NIC for tc netem (auto-detected if empty).",
    )
    parser.add_argument(
        "--loss-percent", type=int, default=30,
        help="Packet loss %% for throttle test.",
    )
    parser.add_argument(
        "--capture-seconds", type=int, default=10,
        help="Duration for traffic pattern capture.",
    )
    parser.add_argument(
        "--output-dir", default="artifacts/dpi_resistance_test",
    )
    args = parser.parse_args()

    out_dir = Path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    report = run_dpi_resistance_test(
        tunnel_interface=args.interface,
        endpoint_port=args.port,
        execute=args.execute,
        physical_interface=args.physical_interface,
        loss_percent=args.loss_percent,
        capture_seconds=args.capture_seconds,
        output_dir=out_dir,
    )

    print(f"\nDPI_RESISTANCE_TEST: {report.verdict}")
    print(f"  fingerprint:        {report.fingerprint.verdict}")
    print(f"  port_block:         {report.port_block.verdict}")
    print(f"  udp_throttle:       {report.throttle.verdict}")
    print(f"  traffic_pattern:    {report.traffic_pattern.verdict}")
    if report.traffic_pattern.combined_entropy > 0:
        print(f"  entropy:            {report.traffic_pattern.combined_entropy:.4f}")
    if report.failures:
        print(f"  failures:           {report.failures}")
    print()
    print(json.dumps(report.to_dict(), indent=2))
    return 0 if report.verdict in {"PASS", "SIMULATED"} else 1


if __name__ == "__main__":
    raise SystemExit(main())
