#!/usr/bin/env python3
"""Concurrent live stress harness for profile issuance and tunnel connect/disconnect cycles."""

from __future__ import annotations

import argparse
import json
import os
import stat
import sys
import tempfile
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from sandbox.live_validation.common import (
    build_interface_name,
    ensure_dir,
    fetch_vpn_profile,
    mean,
    parse_latest_handshake_epoch,
    parse_wireguard_config,
    percentile,
    redact,
    register_or_login_user,
    run_command,
    stdev,
    utc_now_iso,
    write_csv,
    write_json,
)


def _detect_platforms(args: argparse.Namespace) -> list[str]:
    selected: list[str] = []
    if args.linux:
        selected.append("linux")
    if args.windows:
        selected.append("windows")
    if args.android:
        selected.append("android")
    if selected:
        return selected
    if os.name == "nt":
        return ["windows"]
    if os.getenv("ANDROID_ROOT"):
        return ["android"]
    return ["linux"]


def _command_from_template(template: str, *, config_path: Path, interface: str) -> str:
    return template.format(config_path=str(config_path), interface=interface)


def _platform_commands(platform: str, *, config_path: Path, interface: str) -> tuple[list[str] | str, list[str] | str, list[str] | str]:
    if platform == "linux":
        return (
            ["wg-quick", "up", str(config_path)],
            ["wg-quick", "down", str(config_path)],
            ["wg", "show", interface, "latest-handshakes"],
        )

    if platform == "windows":
        return (
            _command_from_template(
                os.getenv("LIVE_WG_WINDOWS_CONNECT_CMD", 'wireguard.exe /installtunnelservice "{config_path}"'),
                config_path=config_path,
                interface=interface,
            ),
            _command_from_template(
                os.getenv("LIVE_WG_WINDOWS_DISCONNECT_CMD", 'wireguard.exe /uninstalltunnelservice "{interface}"'),
                config_path=config_path,
                interface=interface,
            ),
            _command_from_template(
                os.getenv("LIVE_WG_WINDOWS_HANDSHAKE_CMD", 'wg.exe show "{interface}" latest-handshakes'),
                config_path=config_path,
                interface=interface,
            ),
        )

    return (
        _command_from_template(os.getenv("LIVE_ANDROID_CONNECT_CMD", ""), config_path=config_path, interface=interface),
        _command_from_template(os.getenv("LIVE_ANDROID_DISCONNECT_CMD", ""), config_path=config_path, interface=interface),
        _command_from_template(os.getenv("LIVE_ANDROID_HANDSHAKE_CMD", ""), config_path=config_path, interface=interface),
    )


def _exec(cmd: list[str] | str, *, timeout_seconds: int) -> tuple[bool, str]:
    if isinstance(cmd, str):
        if not cmd.strip():
            return False, "missing command"
        result = run_command(cmd, shell=True, timeout_seconds=timeout_seconds)
    else:
        result = run_command(cmd, timeout_seconds=timeout_seconds)
    output = f"{result.stdout}\n{result.stderr}".strip()
    return result.returncode == 0, output[:1000]


def _write_config(path: Path, config_text: str) -> None:
    path.write_text(config_text.strip() + "\n", encoding="utf-8")
    try:
        path.chmod(stat.S_IRUSR | stat.S_IWUSR)
    except Exception:
        pass


def _throughput_probe(url: str, *, interface: str | None, platform: str) -> tuple[bool, float]:
    sink = "NUL" if platform == "windows" else "/dev/null"
    if platform == "linux" and interface:
        cmd = ["curl", "--interface", interface, "--max-time", "15", "-sS", "-o", sink, "-w", "%{speed_download}", url]
    else:
        cmd = ["curl", "--max-time", "15", "-sS", "-o", sink, "-w", "%{speed_download}", url]
    result = run_command(cmd, timeout_seconds=20)
    if result.returncode != 0:
        return False, 0.0
    try:
        bytes_per_second = float(result.stdout.strip())
    except Exception:
        return False, 0.0
    mbps = (bytes_per_second * 8.0) / 1_000_000.0
    return True, round(mbps, 3)


def run_stress(
    *,
    output_dir: Path,
    api_base_url: str,
    platforms: list[str],
    cycles: int,
    workers: int,
    strict: bool,
    enable_tunnel: bool,
    timeout_seconds: int,
    interface_prefix: str,
    device_type: str,
    http_probe_url: str,
    server_id: str | None,
) -> dict[str, Any]:
    out_dir = ensure_dir(output_dir)
    password = os.getenv("LIVE_VALIDATION_PASSWORD", "LiveValidate#123")
    email_prefix = os.getenv("LIVE_VALIDATION_EMAIL_PREFIX", "live.stress")

    latency_rows: list[dict[str, Any]] = []
    jitter_rows: list[dict[str, Any]] = []
    throughput_rows: list[dict[str, Any]] = []
    handshake_rows: list[dict[str, Any]] = []
    fail_rate_rows: list[dict[str, Any]] = []

    global_failures = 0
    strict_failures = 0
    platform_summaries: list[dict[str, Any]] = []

    for platform in platforms:
        tunnel_lock = threading.Lock()
        per_cycle_results: list[dict[str, Any]] = []

        def _worker(worker_id: int, cycle_id: int) -> dict[str, Any]:
            email = f"{email_prefix}+{platform}.{worker_id}.{cycle_id}.{int(time.time())}@example.com"
            ok_auth, token, _ = register_or_login_user(
                api_base_url=api_base_url,
                email=email,
                password=password,
                timeout_seconds=timeout_seconds,
            )
            if not ok_auth or not token:
                return {
                    "ok": False,
                    "worker": worker_id,
                    "cycle": cycle_id,
                    "profile_latency_ms": 0.0,
                    "handshake_ms": 0.0,
                    "throughput_mbps": 0.0,
                    "detail": "auth_failed",
                }

            profile = fetch_vpn_profile(
                api_base_url=api_base_url,
                access_token=token,
                device_name=f"live-stress-{worker_id}-{cycle_id}",
                device_type=device_type,
                timeout_seconds=timeout_seconds,
                server_id=server_id,
            )
            if profile.status_code != 200 or not isinstance(profile.body, dict):
                return {
                    "ok": False,
                    "worker": worker_id,
                    "cycle": cycle_id,
                    "profile_latency_ms": profile.duration_ms,
                    "handshake_ms": 0.0,
                    "throughput_mbps": 0.0,
                    "detail": f"profile_status={profile.status_code}",
                }

            config_text = str(profile.body.get("wireguard_config", "")).strip()
            sections = parse_wireguard_config(config_text)
            peer_public_key = sections.get("peer", {}).get("publickey")
            if "interface" not in sections or "peer" not in sections:
                return {
                    "ok": False,
                    "worker": worker_id,
                    "cycle": cycle_id,
                    "profile_latency_ms": profile.duration_ms,
                    "handshake_ms": 0.0,
                    "throughput_mbps": 0.0,
                    "detail": "invalid_profile",
                }

            if not enable_tunnel:
                return {
                    "ok": True,
                    "worker": worker_id,
                    "cycle": cycle_id,
                    "profile_latency_ms": profile.duration_ms,
                    "handshake_ms": profile.duration_ms,
                    "throughput_mbps": 0.0,
                    "detail": "profile_only",
                }

            interface = build_interface_name(f"{interface_prefix}{worker_id}", cycle_id)
            with tempfile.TemporaryDirectory(prefix=f"securewave_stress_{platform}_") as tmp:
                conf_path = Path(tmp) / f"{interface}.conf"
                _write_config(conf_path, config_text)
                connect_cmd, disconnect_cmd, handshake_cmd = _platform_commands(
                    platform,
                    config_path=conf_path,
                    interface=interface,
                )

                with tunnel_lock:
                    up_ok, up_detail = _exec(connect_cmd, timeout_seconds=timeout_seconds)
                    if not up_ok:
                        return {
                            "ok": False,
                            "worker": worker_id,
                            "cycle": cycle_id,
                            "profile_latency_ms": profile.duration_ms,
                            "handshake_ms": 0.0,
                            "throughput_mbps": 0.0,
                            "detail": f"connect_failed:{up_detail}",
                        }

                    hs_started = time.monotonic()
                    handshake_ok = False
                    handshake_ms = 0.0
                    while (time.monotonic() - hs_started) <= max(5, timeout_seconds):
                        hs_ok, hs_output = _exec(handshake_cmd, timeout_seconds=max(5, timeout_seconds // 2))
                        if hs_ok:
                            epoch = parse_latest_handshake_epoch(hs_output, peer_public_key)
                            if epoch > 0:
                                handshake_ok = True
                                handshake_ms = round((time.monotonic() - hs_started) * 1000, 3)
                                break
                        time.sleep(0.75)

                    throughput_ok, throughput_mbps = _throughput_probe(http_probe_url, interface=interface, platform=platform)
                    _exec(disconnect_cmd, timeout_seconds=timeout_seconds)

            return {
                "ok": handshake_ok,
                "worker": worker_id,
                "cycle": cycle_id,
                "profile_latency_ms": profile.duration_ms,
                "handshake_ms": handshake_ms,
                "throughput_mbps": throughput_mbps if throughput_ok else 0.0,
                "detail": "ok" if handshake_ok else "handshake_failed",
                "token": redact(token),
            }

        futures = []
        with ThreadPoolExecutor(max_workers=max(1, workers)) as executor:
            for cycle_id in range(1, max(1, cycles) + 1):
                for worker_id in range(1, max(1, workers) + 1):
                    futures.append(executor.submit(_worker, worker_id, cycle_id))

            for future in as_completed(futures):
                per_cycle_results.append(future.result())

        per_cycle_results.sort(key=lambda row: (int(row["worker"]), int(row["cycle"])))
        handshake_values: list[float] = [float(row["handshake_ms"]) for row in per_cycle_results if row.get("ok")]
        latency_values: list[float] = [float(row["profile_latency_ms"]) for row in per_cycle_results]
        throughput_values: list[float] = [float(row["throughput_mbps"]) for row in per_cycle_results if float(row.get("throughput_mbps", 0.0)) > 0]

        for row in per_cycle_results:
            success = bool(row.get("ok"))
            if not success:
                global_failures += 1
                if strict:
                    strict_failures += 1

            latency_rows.append(
                {
                    "timestamp": utc_now_iso(),
                    "platform": platform,
                    "worker": row["worker"],
                    "cycle": row["cycle"],
                    "profile_latency_ms": row["profile_latency_ms"],
                    "status": "ok" if success else "failed",
                    "detail": row.get("detail", ""),
                }
            )
            handshake_rows.append(
                {
                    "timestamp": utc_now_iso(),
                    "platform": platform,
                    "worker": row["worker"],
                    "cycle": row["cycle"],
                    "handshake_ms": row["handshake_ms"],
                    "success": success,
                }
            )
            throughput_rows.append(
                {
                    "timestamp": utc_now_iso(),
                    "platform": platform,
                    "worker": row["worker"],
                    "cycle": row["cycle"],
                    "throughput_mbps": row["throughput_mbps"],
                    "status": "ok" if float(row.get("throughput_mbps", 0.0)) > 0 else "failed",
                }
            )

        # Jitter approximation: absolute diff between successive handshake latencies per worker.
        for worker_id in range(1, max(1, workers) + 1):
            worker_vals = [
                float(item["handshake_ms"])
                for item in per_cycle_results
                if int(item["worker"]) == worker_id and float(item.get("handshake_ms", 0.0)) > 0
            ]
            for index in range(1, len(worker_vals)):
                jitter_rows.append(
                    {
                        "timestamp": utc_now_iso(),
                        "platform": platform,
                        "worker": worker_id,
                        "sample": index,
                        "jitter_ms": round(abs(worker_vals[index] - worker_vals[index - 1]), 3),
                    }
                )

        total_cycles = len(per_cycle_results)
        failed_cycles = sum(1 for row in per_cycle_results if not row.get("ok"))
        fail_rate_pct = round((failed_cycles / total_cycles) * 100.0, 3) if total_cycles else 0.0
        fail_rate_rows.append(
            {
                "timestamp": utc_now_iso(),
                "platform": platform,
                "total_cycles": total_cycles,
                "failed_cycles": failed_cycles,
                "fail_rate_pct": fail_rate_pct,
            }
        )

        platform_summaries.append(
            {
                "platform": platform,
                "total_cycles": total_cycles,
                "failed_cycles": failed_cycles,
                "fail_rate_pct": fail_rate_pct,
                "handshake_p50_ms": round(percentile(handshake_values, 50), 3),
                "handshake_p95_ms": round(percentile(handshake_values, 95), 3),
                "handshake_avg_ms": round(mean(handshake_values), 3),
                "handshake_jitter_ms": round(stdev(handshake_values), 3),
                "throughput_avg_mbps": round(mean(throughput_values), 3),
                "latency_avg_ms": round(mean(latency_values), 3),
            }
        )

    write_csv(
        out_dir / "latency_metrics.csv",
        latency_rows,
        ["timestamp", "platform", "worker", "cycle", "profile_latency_ms", "status", "detail"],
    )
    write_csv(
        out_dir / "jitter_metrics.csv",
        jitter_rows,
        ["timestamp", "platform", "worker", "sample", "jitter_ms"],
    )
    write_csv(
        out_dir / "throughput_metrics.csv",
        throughput_rows,
        ["timestamp", "platform", "worker", "cycle", "throughput_mbps", "status"],
    )
    write_csv(
        out_dir / "fail_rate_metrics.csv",
        fail_rate_rows,
        ["timestamp", "platform", "total_cycles", "failed_cycles", "fail_rate_pct"],
    )
    write_csv(
        out_dir / "handshake_stats.csv",
        handshake_rows,
        ["timestamp", "platform", "worker", "cycle", "handshake_ms", "success"],
    )

    summary = {
        "harness": "live_stress_runner",
        "generated_at": utc_now_iso(),
        "overall_status": "pass" if strict_failures == 0 else "fail",
        "strict": strict,
        "enable_tunnel": enable_tunnel,
        "platforms": platforms,
        "workers": workers,
        "cycles": cycles,
        "global_failures": global_failures,
        "strict_failures": strict_failures,
        "platform_summaries": platform_summaries,
    }
    write_json(out_dir / "live_stress_summary.json", summary)
    return summary


def main() -> int:
    parser = argparse.ArgumentParser(description="Run concurrent live network stress cycles")
    parser.add_argument("--output-dir", default="artifacts/live_validation")
    parser.add_argument("--api-base-url", default=os.getenv("LIVE_API_BASE_URL", ""))
    parser.add_argument("--cycles", type=int, default=int(os.getenv("LIVE_STRESS_CYCLES", "4")))
    parser.add_argument("--workers", type=int, default=int(os.getenv("LIVE_STRESS_WORKERS", "4")))
    parser.add_argument("--strict", action="store_true")
    parser.add_argument("--linux", action="store_true")
    parser.add_argument("--windows", action="store_true")
    parser.add_argument("--android", action="store_true")
    parser.add_argument("--enable-tunnel", action="store_true")
    parser.add_argument("--timeout-seconds", type=int, default=int(os.getenv("LIVE_STRESS_TIMEOUT_SECONDS", "25")))
    parser.add_argument("--interface-prefix", default=os.getenv("LIVE_STRESS_INTERFACE_PREFIX", "swstr"))
    parser.add_argument("--device-type", default=os.getenv("LIVE_STRESS_DEVICE_TYPE", "linux"))
    parser.add_argument("--http-probe-url", default=os.getenv("LIVE_HTTP_PROBE_URL", "https://api.ipify.org"))
    parser.add_argument("--server-id", default=os.getenv("LIVE_VALIDATION_SERVER_ID", ""))
    args = parser.parse_args()

    if not args.api_base_url.strip():
        raise SystemExit("LIVE_API_BASE_URL is required")

    summary = run_stress(
        output_dir=Path(args.output_dir),
        api_base_url=args.api_base_url.strip(),
        platforms=_detect_platforms(args),
        cycles=max(1, args.cycles),
        workers=max(1, args.workers),
        strict=args.strict,
        enable_tunnel=args.enable_tunnel,
        timeout_seconds=max(5, args.timeout_seconds),
        interface_prefix=args.interface_prefix,
        device_type=args.device_type,
        http_probe_url=args.http_probe_url,
        server_id=args.server_id.strip() or None,
    )
    print(json.dumps(summary, indent=2))
    return 0 if summary.get("overall_status") == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
