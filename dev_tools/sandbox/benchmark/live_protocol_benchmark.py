#!/usr/bin/env python3
"""Live per-protocol benchmark harness for the current host.

This runner is intentionally honest:
- It measures only what is available on the current machine.
- It does not invent upload metrics when no iperf target is configured.
- It treats missing or broken protocol paths as explicit failures/unavailable rows.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess  # nosec B404 - controlled benchmark command execution
import sys
import time
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any, Optional

REPO_ROOT = Path(__file__).resolve().parents[3]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from dev_tools.sandbox.benchmark.common import ensure_dir, utc_now_iso, write_csv

DEFAULT_DOWNLOAD_URL = os.getenv("SECUREWAVE_BENCHMARK_DOWNLOAD_URL", "https://cachefly.cachefly.net/10mb.test")
DEFAULT_PING_TARGET = os.getenv("SECUREWAVE_BENCHMARK_PING_TARGET", "1.1.1.1")
DEFAULT_OUTPUT_ROOT = REPO_ROOT / "artifacts" / "protocol_benchmarks"
DEFAULT_PUBLISH_PATH = REPO_ROOT / "static" / "data" / "performance_benchmarks.json"

PROTOCOLS = ("wireguard", "openvpn", "ikev2")
PROTOCOL_LABELS = {
    "wireguard": "WireGuard",
    "openvpn": "OpenVPN",
    "ikev2": "IKEv2",
}


@dataclass
class MetricValue:
    status: str
    value: Optional[float]
    reason: Optional[str]
    source: Optional[str]
    evidence: Optional[str]


@dataclass
class ProtocolBenchmark:
    protocol: str
    label: str
    interface: Optional[str]
    status: str
    reason: Optional[str]
    public_ip: Optional[str]
    public_ip_status: str
    public_ip_reason: Optional[str]
    latency_ms: Optional[float]
    latency_status: str
    latency_reason: Optional[str]
    download_mbps: Optional[float]
    download_status: str
    download_reason: Optional[str]
    upload_mbps: Optional[float]
    upload_status: str
    upload_reason: Optional[str]
    download_retention_pct: Optional[float]
    upload_retention_pct: Optional[float]
    latency_impact_ms: Optional[float]
    measured_at: str


def _run_command(command: list[str], *, timeout_seconds: int = 20) -> tuple[int, str, str]:
    try:
        proc = subprocess.run(  # nosec B603
            command,
            capture_output=True,
            text=True,
            timeout=timeout_seconds,
            check=False,
        )
    except (subprocess.SubprocessError, OSError, TimeoutError) as exc:
        return 98, "", str(exc)
    return proc.returncode, proc.stdout, proc.stderr


def _command_exists(binary: str) -> bool:
    return shutil.which(binary) is not None


def _list_interfaces() -> list[str]:
    code, stdout, _ = _run_command(["ip", "-o", "link", "show"], timeout_seconds=5)
    if code != 0:
        return []
    interfaces: list[str] = []
    for line in stdout.splitlines():
        match = re.match(r"\d+:\s+([^:@]+)", line)
        if match:
            interfaces.append(match.group(1))
    return interfaces


def _resolve_interface(protocol: str, explicit: Optional[str]) -> Optional[str]:
    if explicit:
        return explicit
    interfaces = _list_interfaces()
    if protocol == "wireguard":
        for candidate in interfaces:
            if candidate.startswith("wg"):
                return candidate
    if protocol == "openvpn":
        for candidate in interfaces:
            if candidate.startswith("tun") or candidate.startswith("tap"):
                return candidate
    if protocol == "ikev2":
        for candidate in interfaces:
            if candidate.startswith(("ipsec", "xfrm", "ppp")):
                return candidate
    return None


def _get_interface_ipv4(interface: str) -> Optional[str]:
    code, stdout, _ = _run_command(["ip", "-4", "-o", "addr", "show", "dev", interface], timeout_seconds=5)
    if code != 0:
        return None
    match = re.search(r"inet\s+(\d+\.\d+\.\d+\.\d+)", stdout)
    return match.group(1) if match else None


def _measure_public_ip(interface: Optional[str]) -> MetricValue:
    if not _command_exists("curl"):
        return MetricValue("unavailable", None, "curl_not_installed", None, None)
    command = ["curl", "-sS", "--connect-timeout", "6", "--max-time", "12"]
    if interface:
        command.extend(["--interface", interface])
    command.append("https://api.ipify.org")
    code, stdout, stderr = _run_command(command, timeout_seconds=14)
    if code != 0:
        reason = f"curl_exit_{code}"
        if stderr.strip():
            reason = f"{reason}:{stderr.strip().splitlines()[-1]}"
        return MetricValue("fail", None, reason, "curl", " ".join(command))
    value = stdout.strip()
    if not value:
        return MetricValue("fail", None, "empty_public_ip_response", "curl", " ".join(command))
    return MetricValue("pass", None, None, "curl", value)


def _measure_latency(interface: Optional[str], ping_target: str) -> MetricValue:
    if not _command_exists("ping"):
        return MetricValue("unavailable", None, "ping_not_installed", None, None)
    command = ["ping", "-n", "-c", "3", "-W", "2"]
    if interface:
        command.extend(["-I", interface])
    command.append(ping_target)
    code, stdout, stderr = _run_command(command, timeout_seconds=12)
    if code != 0:
        reason = f"ping_exit_{code}"
        detail = stderr.strip() or stdout.strip()
        if detail:
            reason = f"{reason}:{detail.splitlines()[-1]}"
        return MetricValue("fail", None, reason, "ping", " ".join(command))
    match = re.search(r"=\s*[\d.]+/([\d.]+)/", stdout)
    if not match:
        return MetricValue("fail", None, "ping_parse_failed", "ping", " ".join(command))
    return MetricValue("pass", round(float(match.group(1)), 3), None, "ping", " ".join(command))


def _measure_download(interface: Optional[str], download_url: str, bytes_to_fetch: int) -> MetricValue:
    if not _command_exists("curl"):
        return MetricValue("unavailable", None, "curl_not_installed", None, None)
    end = max(0, int(bytes_to_fetch) - 1)
    command = [
        "curl",
        "-L",
        "-sS",
        "-o",
        "/dev/null",
        "--connect-timeout",
        "6",
        "--max-time",
        "30",
        "--range",
        f"0-{end}",
        "-w",
        "%{http_code} %{speed_download} %{time_total}",
    ]
    if interface:
        command.extend(["--interface", interface])
    command.append(download_url)
    code, stdout, stderr = _run_command(command, timeout_seconds=35)
    if code != 0:
        reason = f"curl_exit_{code}"
        if stderr.strip():
            reason = f"{reason}:{stderr.strip().splitlines()[-1]}"
        return MetricValue("fail", None, reason, "curl", " ".join(command))
    parts = stdout.strip().split()
    if len(parts) < 3:
        return MetricValue("fail", None, "throughput_parse_failed", "curl", " ".join(command))
    http_code, speed_download, _ = parts[-3], parts[-2], parts[-1]
    if not http_code.startswith("2"):
        return MetricValue("fail", None, f"http_status_{http_code}", "curl", " ".join(command))
    try:
        mbps = round((float(speed_download) * 8.0) / (1024.0 * 1024.0), 3)
    except ValueError:
        return MetricValue("fail", None, "invalid_speed_download", "curl", " ".join(command))
    return MetricValue("pass", mbps, None, "curl", " ".join(command))


def _measure_upload(interface: Optional[str], host: Optional[str], port: int, duration: int) -> MetricValue:
    if not host:
        return MetricValue("unavailable", None, "iperf_host_not_configured", None, None)
    if not _command_exists("iperf3"):
        return MetricValue("unavailable", None, "iperf3_not_installed", None, None)
    command = ["iperf3", "-c", host, "-p", str(port), "-J", "-t", str(max(1, duration))]
    if interface:
        local_ip = _get_interface_ipv4(interface)
        if not local_ip:
            return MetricValue("unavailable", None, "interface_ipv4_not_found", None, interface)
        command.extend(["-B", local_ip])
    code, stdout, stderr = _run_command(command, timeout_seconds=max(15, duration + 10))
    if code != 0:
        reason = f"iperf3_exit_{code}"
        detail = stderr.strip() or stdout.strip()
        if detail:
            reason = f"{reason}:{detail.splitlines()[-1]}"
        return MetricValue("fail", None, reason, "iperf3", " ".join(command))
    try:
        payload = json.loads(stdout)
        sent_bps = float(payload.get("end", {}).get("sum_sent", {}).get("bits_per_second", 0.0))
    except (ValueError, TypeError, AttributeError):
        return MetricValue("fail", None, "iperf3_parse_failed", "iperf3", " ".join(command))
    if sent_bps <= 0:
        return MetricValue("fail", None, "iperf3_zero_upload", "iperf3", " ".join(command))
    return MetricValue("pass", round(sent_bps / 1_000_000.0, 3), None, "iperf3", " ".join(command))


def _status_from_metrics(*metrics: MetricValue, interface: Optional[str]) -> tuple[str, Optional[str]]:
    if not interface:
        return "unavailable", "interface_not_detected"
    if any(metric.status == "pass" for metric in metrics):
        if all(metric.status == "pass" or metric.status == "unavailable" for metric in metrics):
            if any(metric.status == "unavailable" for metric in metrics):
                missing = ",".join(sorted({metric.reason or "unavailable" for metric in metrics if metric.status == "unavailable"}))
                return "partial", missing
            return "pass", None
    reasons = [metric.reason for metric in metrics if metric.reason]
    if reasons:
        return "fail", reasons[0]
    return "fail", "benchmark_failed"


def _retention(value: Optional[float], baseline: Optional[float]) -> Optional[float]:
    if value is None or baseline is None or baseline <= 0:
        return None
    return round((value / baseline) * 100.0, 1)


def benchmark_protocol(
    *,
    protocol: str,
    interface: Optional[str],
    download_url: str,
    ping_target: str,
    bytes_to_fetch: int,
    iperf_host: Optional[str],
    iperf_port: int,
    iperf_duration: int,
    baseline_latency: Optional[float],
    baseline_download: Optional[float],
    baseline_upload: Optional[float],
) -> ProtocolBenchmark:
    public_ip = _measure_public_ip(interface)
    latency = _measure_latency(interface, ping_target)
    download = _measure_download(interface, download_url, bytes_to_fetch)
    upload = _measure_upload(interface, iperf_host, iperf_port, iperf_duration)
    status, reason = _status_from_metrics(public_ip, latency, download, upload, interface=interface)
    return ProtocolBenchmark(
        protocol=protocol,
        label=PROTOCOL_LABELS[protocol],
        interface=interface,
        status=status,
        reason=reason,
        public_ip=public_ip.evidence if public_ip.status == "pass" else None,
        public_ip_status=public_ip.status,
        public_ip_reason=public_ip.reason,
        latency_ms=latency.value,
        latency_status=latency.status,
        latency_reason=latency.reason,
        download_mbps=download.value,
        download_status=download.status,
        download_reason=download.reason,
        upload_mbps=upload.value,
        upload_status=upload.status,
        upload_reason=upload.reason,
        download_retention_pct=_retention(download.value, baseline_download),
        upload_retention_pct=_retention(upload.value, baseline_upload),
        latency_impact_ms=round(latency.value - baseline_latency, 3)
        if latency.value is not None and baseline_latency is not None
        else None,
        measured_at=utc_now_iso(),
    )


def _baseline(download_url: str, ping_target: str, bytes_to_fetch: int, iperf_host: Optional[str], iperf_port: int, iperf_duration: int) -> dict[str, Any]:
    public_ip = _measure_public_ip(None)
    latency = _measure_latency(None, ping_target)
    download = _measure_download(None, download_url, bytes_to_fetch)
    upload = _measure_upload(None, iperf_host, iperf_port, iperf_duration)
    return {
        "public_ip": public_ip.evidence if public_ip.status == "pass" else None,
        "public_ip_status": public_ip.status,
        "public_ip_reason": public_ip.reason,
        "latency_ms": latency.value,
        "latency_status": latency.status,
        "latency_reason": latency.reason,
        "download_mbps": download.value,
        "download_status": download.status,
        "download_reason": download.reason,
        "upload_mbps": upload.value,
        "upload_status": upload.status,
        "upload_reason": upload.reason,
        "measured_at": utc_now_iso(),
    }


def _website_summary(payload: dict[str, Any]) -> dict[str, Any]:
    protocols = payload["protocols"]
    baseline = payload["baseline"]
    highlight = None
    for protocol in PROTOCOLS:
        row = protocols[protocol]
        if row["status"] in {"pass", "partial"}:
            highlight = protocol
            break
    if highlight is None:
        highlight = "wireguard"
    return {
        "generated_at": payload["generated_at"],
        "host_platform": payload["host_platform"],
        "baseline": {
            "download_mbps": baseline.get("download_mbps"),
            "upload_mbps": baseline.get("upload_mbps"),
            "latency_ms": baseline.get("latency_ms"),
        },
        "highlight_protocol": highlight,
        "protocols": {
            protocol: {
                "label": protocols[protocol]["label"],
                "status": protocols[protocol]["status"],
                "reason": protocols[protocol]["reason"],
                "interface": protocols[protocol]["interface"],
                "download_mbps": protocols[protocol]["download_mbps"],
                "upload_mbps": protocols[protocol]["upload_mbps"],
                "latency_ms": protocols[protocol]["latency_ms"],
                "download_retention_pct": protocols[protocol]["download_retention_pct"],
                "upload_retention_pct": protocols[protocol]["upload_retention_pct"],
                "latency_impact_ms": protocols[protocol]["latency_impact_ms"],
            }
            for protocol in PROTOCOLS
        },
    }


def run_live_protocol_benchmark(
    *,
    output_root: Path = DEFAULT_OUTPUT_ROOT,
    publish_path: Path = DEFAULT_PUBLISH_PATH,
    download_url: str = DEFAULT_DOWNLOAD_URL,
    ping_target: str = DEFAULT_PING_TARGET,
    bytes_to_fetch: int = 5 * 1024 * 1024,
    iperf_host: Optional[str] = None,
    iperf_port: int = int(os.getenv("BENCHMARK_IPERF_PORT", "5201")),
    iperf_duration: int = int(os.getenv("BENCHMARK_IPERF_DURATION", "8")),
    wg_interface: Optional[str] = None,
    openvpn_interface: Optional[str] = None,
    ikev2_interface: Optional[str] = None,
) -> dict[str, Any]:
    stamp = time.strftime("%Y%m%d_%H%M%S", time.gmtime())
    out_dir = ensure_dir(output_root / stamp)
    interfaces = {
        "wireguard": _resolve_interface("wireguard", wg_interface),
        "openvpn": _resolve_interface("openvpn", openvpn_interface),
        "ikev2": _resolve_interface("ikev2", ikev2_interface),
    }

    baseline = _baseline(download_url, ping_target, bytes_to_fetch, iperf_host, iperf_port, iperf_duration)
    protocol_rows = {
        protocol: asdict(
            benchmark_protocol(
                protocol=protocol,
                interface=interface,
                download_url=download_url,
                ping_target=ping_target,
                bytes_to_fetch=bytes_to_fetch,
                iperf_host=iperf_host,
                iperf_port=iperf_port,
                iperf_duration=iperf_duration,
                baseline_latency=baseline.get("latency_ms"),
                baseline_download=baseline.get("download_mbps"),
                baseline_upload=baseline.get("upload_mbps"),
            )
        )
        for protocol, interface in interfaces.items()
    }

    payload = {
        "generated_at": utc_now_iso(),
        "host_platform": sys.platform.lower(),
        "download_url": download_url,
        "ping_target": ping_target,
        "iperf_host": iperf_host,
        "iperf_port": iperf_port,
        "iperf_duration": iperf_duration,
        "baseline": baseline,
        "protocols": protocol_rows,
        "website": _website_summary(
            {
                "generated_at": utc_now_iso(),
                "host_platform": sys.platform.lower(),
                "baseline": baseline,
                "protocols": protocol_rows,
            }
        ),
    }

    csv_rows = [
        {
            "protocol": "baseline",
            "interface": "",
            "status": "pass" if any(baseline.get(key) is not None for key in ("download_mbps", "upload_mbps", "latency_ms")) else "fail",
            "latency_ms": baseline.get("latency_ms"),
            "download_mbps": baseline.get("download_mbps"),
            "upload_mbps": baseline.get("upload_mbps"),
            "reason": baseline.get("download_reason") or baseline.get("upload_reason") or baseline.get("latency_reason"),
        }
    ]
    for protocol in PROTOCOLS:
        row = protocol_rows[protocol]
        csv_rows.append(
            {
                "protocol": protocol,
                "interface": row["interface"] or "",
                "status": row["status"],
                "latency_ms": row["latency_ms"],
                "download_mbps": row["download_mbps"],
                "upload_mbps": row["upload_mbps"],
                "reason": row["reason"] or row["download_reason"] or row["upload_reason"] or row["latency_reason"],
            }
        )

    write_csv(
        out_dir / "protocol_speed_results.csv",
        csv_rows,
        ["protocol", "interface", "status", "latency_ms", "download_mbps", "upload_mbps", "reason"],
    )
    (out_dir / "protocol_speed_results.json").write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    ensure_dir(publish_path.parent)
    publish_path.write_text(json.dumps(payload["website"], indent=2) + "\n", encoding="utf-8")
    return payload


def main() -> int:
    parser = argparse.ArgumentParser(description="Run honest live protocol benchmarks for the current host")
    parser.add_argument("--output-root", default=str(DEFAULT_OUTPUT_ROOT))
    parser.add_argument("--publish-path", default=str(DEFAULT_PUBLISH_PATH))
    parser.add_argument("--download-url", default=DEFAULT_DOWNLOAD_URL)
    parser.add_argument("--ping-target", default=DEFAULT_PING_TARGET)
    parser.add_argument("--bytes", type=int, default=5 * 1024 * 1024)
    parser.add_argument("--iperf-host", default=os.getenv("BENCHMARK_IPERF_HOST", ""))
    parser.add_argument("--iperf-port", type=int, default=int(os.getenv("BENCHMARK_IPERF_PORT", "5201")))
    parser.add_argument("--iperf-duration", type=int, default=int(os.getenv("BENCHMARK_IPERF_DURATION", "8")))
    parser.add_argument("--wg-interface", default=os.getenv("SECUREWAVE_WG_INTERFACE", ""))
    parser.add_argument("--openvpn-interface", default=os.getenv("SECUREWAVE_OPENVPN_INTERFACE", ""))
    parser.add_argument("--ikev2-interface", default=os.getenv("SECUREWAVE_IKEV2_INTERFACE", ""))
    args = parser.parse_args()

    payload = run_live_protocol_benchmark(
        output_root=Path(args.output_root),
        publish_path=Path(args.publish_path),
        download_url=args.download_url,
        ping_target=args.ping_target,
        bytes_to_fetch=max(1, args.bytes),
        iperf_host=args.iperf_host.strip() or None,
        iperf_port=args.iperf_port,
        iperf_duration=max(1, args.iperf_duration),
        wg_interface=args.wg_interface.strip() or None,
        openvpn_interface=args.openvpn_interface.strip() or None,
        ikev2_interface=args.ikev2_interface.strip() or None,
    )
    print(json.dumps(payload["website"], indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
