#!/usr/bin/env python3
"""Packet leak detection for SecureWave VPN tunnels."""

from __future__ import annotations

import argparse
import json
import os
import re
import signal
import socket
import subprocess  # nosec B404 - operator-controlled validation commands
import sys
import time
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[3]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from dev_tools.sandbox.live_validation.common import (
    parse_nameservers,
    read_text,
    run_command,
    utc_now_iso,
    write_json,
)

_PHYSICAL_INTERFACE_PREFIXES = ("eth", "en", "wl", "wlan", "wwan")
_IGNORED_INTERFACE_PREFIXES = ("lo", "docker", "veth", "br-", "virbr", "cni", "flannel", "zt", "tailscale")
_TCPDUMP_LINE_RE = re.compile(
    r"^(?P<timestamp>\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}\.\d+)\s+"
    r"(?P<interface>\S+)\s+"
    r"(?P<direction>In|Out)\s+"
    r"(?P<protocol>IP6?|ARP)\s+"
    r"(?P<source>\S+)\s+>\s+(?P<destination>\S+?)(?::\s|,\s|\s)"
)


@dataclass
class PacketObservation:
    timestamp: str = ""
    interface: str = ""
    direction: str = ""
    protocol: str = ""
    source: str = ""
    destination: str = ""
    raw: str = ""

    def source_host(self) -> str:
        return normalize_endpoint_host(self.source)

    def destination_host(self) -> str:
        return normalize_endpoint_host(self.destination)


@dataclass
class TrafficCommandResult:
    name: str = ""
    command: str = ""
    success: bool = False
    stdout: str = ""
    stderr: str = ""
    duration_ms: float = 0.0


@dataclass
class PacketLeakReport:
    test_name: str = "packet_leak_detection"
    started_at: str = ""
    finished_at: str = ""
    verdict: str = "UNTESTED"

    tunnel_interface: str = ""
    default_gateway_interfaces: list[str] = field(default_factory=list)
    blocked_interfaces: list[str] = field(default_factory=list)
    probe_targets: list[str] = field(default_factory=list)

    baseline_interface_snapshot: str = ""
    baseline_capture_path: str = ""
    tunnel_capture_path: str = ""

    baseline_packet_count: int = 0
    tunnel_packet_count: int = 0
    ignored_baseline_packet_count: int = 0
    tunnel_probe_packet_count: int = 0

    traffic_commands: list[TrafficCommandResult] = field(default_factory=list)
    leak_packets: list[PacketObservation] = field(default_factory=list)

    leak_detected: bool = False
    failures: list[str] = field(default_factory=list)

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


def capture_interface_snapshot() -> str:
    return run_command(["ip", "a"], timeout_seconds=8).stdout


def parse_interface_names(snapshot: str) -> list[str]:
    names: list[str] = []
    seen: set[str] = set()
    for raw in snapshot.splitlines():
        match = re.match(r"^\d+:\s+(\S+?):", raw)
        if not match:
            continue
        name = match.group(1).split("@", 1)[0]
        if name in seen:
            continue
        seen.add(name)
        names.append(name)
    return names


def default_gateway_interfaces(route_output: str | None = None) -> list[str]:
    text = route_output
    if text is None:
        text = run_command(["ip", "route", "show", "default"], timeout_seconds=5).stdout

    interfaces: list[str] = []
    seen: set[str] = set()
    for raw in text.splitlines():
        match = re.search(r"\bdev\s+(\S+)", raw)
        if not match:
            continue
        interface = match.group(1).split("@", 1)[0]
        if interface in seen:
            continue
        seen.add(interface)
        interfaces.append(interface)
    return interfaces


def derive_blocked_interfaces(
    snapshot: str,
    *,
    tunnel_interface: str,
    default_route_interfaces: list[str] | None = None,
) -> list[str]:
    blocked: set[str] = set(default_route_interfaces or [])
    for name in parse_interface_names(snapshot):
        if name == tunnel_interface or name == "any":
            continue
        if name.startswith(_IGNORED_INTERFACE_PREFIXES):
            continue
        if name.startswith(_PHYSICAL_INTERFACE_PREFIXES):
            blocked.add(name)
    return sorted(blocked)


def normalize_endpoint_host(endpoint: str) -> str:
    value = endpoint.strip().rstrip(":,")
    if not value:
        return ""
    if value.startswith("[") and "]" in value:
        return value[1:value.index("]")]
    if re.match(r"^\d+\.\d+\.\d+\.\d+\.\d+$", value):
        return value.rsplit(".", 1)[0]
    if re.match(r"^[A-Fa-f0-9:]+\.\d+$", value):
        return value.rsplit(".", 1)[0]
    if "." in value and value.rsplit(".", 1)[1].isdigit():
        return value.rsplit(".", 1)[0]
    return value


def parse_tcpdump_capture(output: str) -> list[PacketObservation]:
    packets: list[PacketObservation] = []
    for raw in output.splitlines():
        line = raw.strip()
        if not line:
            continue
        match = _TCPDUMP_LINE_RE.match(line)
        if not match:
            continue
        packets.append(
            PacketObservation(
                timestamp=match.group("timestamp"),
                interface=match.group("interface").split("@", 1)[0],
                direction=match.group("direction"),
                protocol=match.group("protocol"),
                source=match.group("source"),
                destination=match.group("destination").rstrip(":,"),
                raw=line,
            )
        )
    return packets


def packet_signature(packet: PacketObservation) -> tuple[str, str, str, str, str]:
    return (
        packet.interface,
        packet.direction,
        packet.protocol,
        packet.source_host(),
        packet.destination_host(),
    )


def analyze_packet_observations(
    observations: list[PacketObservation],
    *,
    tunnel_interface: str,
    blocked_interfaces: set[str],
    probe_targets: set[str],
    baseline_signatures: set[tuple[str, str, str, str, str]] | None = None,
) -> tuple[list[PacketObservation], int, int]:
    leaks: list[PacketObservation] = []
    ignored_baseline = 0
    tunnel_probe_packets = 0

    for packet in observations:
        if packet.direction != "Out":
            continue
        signature = packet_signature(packet)
        if baseline_signatures and signature in baseline_signatures:
            ignored_baseline += 1
            continue

        hosts = {packet.source_host(), packet.destination_host()}
        if probe_targets and not (hosts & probe_targets):
            continue

        if packet.interface == tunnel_interface:
            tunnel_probe_packets += 1
            continue

        if packet.interface in blocked_interfaces:
            leaks.append(packet)

    return leaks, ignored_baseline, tunnel_probe_packets


def _tcpdump_binary_available() -> bool:
    check = run_command(["bash", "-lc", "command -v tcpdump >/dev/null 2>&1"], timeout_seconds=3)
    return check.returncode == 0


def capture_tcpdump_pcap(
    output_path: Path,
    *,
    duration_seconds: int = 2,
    capture_filter: list[str] | None = None,
) -> dict[str, Any]:
    command = ["tcpdump", "-i", "any", "-U", "-n", *(capture_filter or ["not", "port", "22"]), "-w", str(output_path)]
    started = time.monotonic()
    try:
        proc = subprocess.Popen(  # nosec B603
            command,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
        )
    except FileNotFoundError:
        return {
            "success": False,
            "command": " ".join(command),
            "stderr": "tcpdump_not_found",
            "duration_ms": 0.0,
        }
    except Exception as exc:
        return {
            "success": False,
            "command": " ".join(command),
            "stderr": str(exc),
            "duration_ms": 0.0,
        }

    time.sleep(max(1, int(duration_seconds)))
    try:
        proc.send_signal(signal.SIGINT)
        _, stderr = proc.communicate(timeout=5)
    except Exception:
        proc.kill()
        _, stderr = proc.communicate(timeout=5)

    duration_ms = round((time.monotonic() - started) * 1000, 3)
    return {
        "success": proc.returncode == 0 and output_path.exists(),
        "command": " ".join(command),
        "stderr": (stderr or "").strip()[:800],
        "duration_ms": duration_ms,
    }


def _decode_pcap(pcap_path: Path) -> tuple[list[PacketObservation], dict[str, Any]]:
    result = run_command(["tcpdump", "-nn", "-tttt", "-e", "-r", str(pcap_path)], timeout_seconds=20)
    return parse_tcpdump_capture(result.stdout), {
        "command": result.command,
        "returncode": result.returncode,
        "stderr": result.stderr[:800],
        "duration_ms": result.duration_ms,
    }


def _linux_interface_ipv4(interface: str) -> str | None:
    result = run_command(["ip", "-4", "addr", "show", "dev", interface], timeout_seconds=5)
    if result.returncode != 0:
        return None
    for line in result.stdout.splitlines():
        line = line.strip()
        if "inet " not in line:
            continue
        parts = line.split()
        try:
            idx = parts.index("inet")
        except ValueError:
            continue
        if idx + 1 >= len(parts):
            continue
        return parts[idx + 1].split("/", 1)[0].strip()
    return None


def _current_dns_servers() -> list[str]:
    resolvers = parse_nameservers(read_text("/etc/resolv.conf"))
    seen: set[str] = set()
    ordered: list[str] = []
    for resolver in resolvers:
        if resolver in seen:
            continue
        seen.add(resolver)
        ordered.append(resolver)
    return ordered


def resolve_probe_targets(*, dns_servers: list[str] | None = None) -> list[str]:
    targets: set[str] = {"1.1.1.1"}
    for resolver in dns_servers or _current_dns_servers():
        if resolver:
            targets.add(resolver)

    try:
        infos = socket.getaddrinfo("example.com", 443, socket.AF_INET, socket.SOCK_STREAM)
    except Exception:
        infos = []
    for info in infos:
        try:
            targets.add(str(info[4][0]))
        except Exception:
            continue
    return sorted(targets)


def _traffic_result(name: str, result: Any) -> TrafficCommandResult:
    return TrafficCommandResult(
        name=name,
        command=result.command,
        success=result.returncode == 0,
        stdout=(result.stdout or "")[:400],
        stderr=(result.stderr or "")[:200],
        duration_ms=result.duration_ms,
    )


def generate_probe_traffic(tunnel_interface: str) -> list[TrafficCommandResult]:
    traffic: list[TrafficCommandResult] = []

    curl_result = run_command(
        [
            "curl",
            "--interface",
            tunnel_interface,
            "--max-time",
            "10",
            "-sS",
            "https://example.com",
            "-o",
            "/dev/null",
        ],
        timeout_seconds=15,
    )
    traffic.append(_traffic_result("curl_example", curl_result))

    ping_result = run_command(
        ["ping", "-I", tunnel_interface, "-c", "3", "-W", "1", "1.1.1.1"],
        timeout_seconds=8,
    )
    traffic.append(_traffic_result("ping_1_1_1_1", ping_result))

    dig_check = run_command(["bash", "-lc", "command -v dig >/dev/null 2>&1"], timeout_seconds=3)
    if dig_check.returncode == 0:
        source_ip = _linux_interface_ipv4(tunnel_interface)
        dns_servers = _current_dns_servers()
        dig_command = ["dig", "+time=2", "+tries=1", "google.com"]
        if dns_servers:
            dig_command.insert(3, f"@{dns_servers[0]}")
        if source_ip:
            dig_command.extend(["-b", source_ip])
        dig_result = run_command(dig_command, timeout_seconds=8)
        traffic.append(_traffic_result("dig_google", dig_result))
    else:
        traffic.append(
            TrafficCommandResult(
                name="dig_google",
                command="dig",
                success=False,
                stderr="dig_not_found",
            )
        )

    return traffic


def run_packet_leak_test(
    *,
    tunnel_interface: str,
    output_dir: Path | None = None,
    baseline_capture_path: Path | None = None,
    baseline_interface_snapshot: str | None = None,
    capture_seconds: int = 4,
) -> PacketLeakReport:
    report = PacketLeakReport(started_at=utc_now_iso(), tunnel_interface=tunnel_interface)
    report.baseline_interface_snapshot = baseline_interface_snapshot or capture_interface_snapshot()
    report.default_gateway_interfaces = default_gateway_interfaces()
    report.blocked_interfaces = derive_blocked_interfaces(
        report.baseline_interface_snapshot,
        tunnel_interface=tunnel_interface,
        default_route_interfaces=report.default_gateway_interfaces,
    )
    report.probe_targets = resolve_probe_targets()

    if not tunnel_interface:
        report.verdict = "FAIL"
        report.leak_detected = True
        report.failures.append("missing_tunnel_interface")
        report.finished_at = utc_now_iso()
        return report

    if not _tcpdump_binary_available():
        report.verdict = "FAIL"
        report.leak_detected = True
        report.failures.append("tcpdump_not_found")
        report.finished_at = utc_now_iso()
        if output_dir:
            write_json(Path(output_dir) / f"packet_leak_report_{tunnel_interface}.json", report.to_dict())
        return report

    baseline_signatures: set[tuple[str, str, str, str, str]] = set()
    if baseline_capture_path and baseline_capture_path.exists():
        report.baseline_capture_path = str(baseline_capture_path)
        baseline_packets, baseline_meta = _decode_pcap(baseline_capture_path)
        report.baseline_packet_count = len(baseline_packets)
        baseline_signatures = {packet_signature(packet) for packet in baseline_packets}
        if baseline_meta["returncode"] != 0:
            report.failures.append("baseline_capture_decode_failed")

    out_dir = Path(output_dir) if output_dir else Path("artifacts/live_validation")
    out_dir.mkdir(parents=True, exist_ok=True)
    tunnel_capture_path = out_dir / f"{tunnel_interface}_tunnel_capture.pcap"
    report.tunnel_capture_path = str(tunnel_capture_path)

    capture_command = [
        "tcpdump",
        "-i",
        "any",
        "-U",
        "-n",
        "not",
        "port",
        "22",
        "-w",
        str(tunnel_capture_path),
    ]
    try:
        proc = subprocess.Popen(  # nosec B603
            capture_command,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
        )
    except Exception as exc:
        report.verdict = "FAIL"
        report.leak_detected = True
        report.failures.append(f"tunnel_capture_start_failed:{exc}")
        report.finished_at = utc_now_iso()
        write_json(out_dir / f"packet_leak_report_{tunnel_interface}.json", report.to_dict())
        return report

    time.sleep(1.0)
    report.traffic_commands = generate_probe_traffic(tunnel_interface)
    time.sleep(max(1, int(capture_seconds)))

    try:
        proc.send_signal(signal.SIGINT)
        _, stderr = proc.communicate(timeout=5)
    except Exception:
        proc.kill()
        _, stderr = proc.communicate(timeout=5)
    if proc.returncode != 0:
        report.failures.append(f"tunnel_capture_failed:{(stderr or '').strip()[:200]}")

    tunnel_packets, tunnel_meta = _decode_pcap(tunnel_capture_path)
    report.tunnel_packet_count = len(tunnel_packets)
    if tunnel_meta["returncode"] != 0:
        report.failures.append("tunnel_capture_decode_failed")

    leaks, ignored_baseline, tunnel_probe_packets = analyze_packet_observations(
        tunnel_packets,
        tunnel_interface=tunnel_interface,
        blocked_interfaces=set(report.blocked_interfaces),
        probe_targets=set(report.probe_targets),
        baseline_signatures=baseline_signatures,
    )
    report.leak_packets = leaks
    report.ignored_baseline_packet_count = ignored_baseline
    report.tunnel_probe_packet_count = tunnel_probe_packets

    if leaks:
        report.verdict = "FAIL"
        report.leak_detected = True
        report.failures.append(
            "non_vpn_egress_detected:" + ",".join(sorted({packet.interface for packet in leaks}))
        )
    elif tunnel_probe_packets == 0:
        report.verdict = "FAIL"
        report.leak_detected = True
        report.failures.append("no_probe_packets_observed_on_tunnel")
    elif not all(item.success for item in report.traffic_commands):
        report.verdict = "FAIL"
        report.leak_detected = True
        report.failures.append("probe_traffic_generation_failed")
    else:
        report.verdict = "PASS"
        report.leak_detected = False

    report.finished_at = utc_now_iso()
    write_json(out_dir / f"packet_leak_report_{tunnel_interface}.json", report.to_dict())
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description="SecureWave packet leak detection")
    parser.add_argument("--interface", default=os.getenv("PACKET_LEAK_TEST_INTERFACE", ""))
    parser.add_argument("--output-dir", default="artifacts/packet_leak_test")
    parser.add_argument(
        "--capture-seconds",
        type=int,
        default=int(os.getenv("PACKET_LEAK_CAPTURE_SECONDS", "4")),
    )
    parser.add_argument(
        "--baseline-capture-seconds",
        type=int,
        default=int(os.getenv("PACKET_LEAK_BASELINE_SECONDS", "2")),
    )
    args = parser.parse_args()

    interface = args.interface.strip()
    if not interface:
        result = run_command(["ip", "-o", "link", "show", "up"], timeout_seconds=5)
        for line in result.stdout.splitlines():
            parts = line.split(":", 2)
            if len(parts) < 2:
                continue
            candidate = parts[1].strip().split("@", 1)[0]
            if candidate.startswith(("wg", "swlive")):
                interface = candidate
                break

    if not interface:
        payload = PacketLeakReport(
            started_at=utc_now_iso(),
            finished_at=utc_now_iso(),
            verdict="FAIL",
            leak_detected=True,
            failures=["no_wireguard_interface_detected"],
        )
        print(json.dumps(payload.to_dict(), indent=2))
        return 1

    out_dir = Path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    baseline_snapshot = capture_interface_snapshot()
    baseline_capture = out_dir / f"{interface}_baseline.pcap"
    baseline_meta = capture_tcpdump_pcap(
        baseline_capture,
        duration_seconds=max(1, args.baseline_capture_seconds),
    )
    if not baseline_meta.get("success"):
        payload = PacketLeakReport(
            started_at=utc_now_iso(),
            finished_at=utc_now_iso(),
            verdict="FAIL",
            tunnel_interface=interface,
            leak_detected=True,
            baseline_interface_snapshot=baseline_snapshot,
            baseline_capture_path=str(baseline_capture),
            failures=[f"baseline_capture_failed:{baseline_meta.get('stderr') or 'unknown'}"],
        )
        print(json.dumps(payload.to_dict(), indent=2))
        return 1

    report = run_packet_leak_test(
        tunnel_interface=interface,
        output_dir=out_dir,
        baseline_capture_path=baseline_capture,
        baseline_interface_snapshot=baseline_snapshot,
        capture_seconds=max(1, args.capture_seconds),
    )
    print(json.dumps(report.to_dict(), indent=2))
    return 0 if report.verdict == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
