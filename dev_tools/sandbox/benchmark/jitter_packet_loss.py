#!/usr/bin/env python3
"""Jitter and packet-loss assessment harness."""

from __future__ import annotations

import argparse
import json
import math
import shutil
import subprocess  # nosec B404 - controlled benchmark command execution
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from dev_tools.sandbox.benchmark.common import deterministic_fallback_latency, ensure_dir, mean, utc_now_iso, write_csv

DEFAULT_TARGETS = "barbados=1.1.1.1,frankfurt=8.8.8.8"


def parse_targets(raw: str) -> list[tuple[str, str]]:
    targets: list[tuple[str, str]] = []
    for item in (part.strip() for part in raw.split(",") if part.strip()):
        if "=" not in item:
            continue
        region, endpoint = item.split("=", 1)
        region = region.strip().lower()
        endpoint = endpoint.strip()
        if region and endpoint:
            targets.append((region, endpoint))
    return targets


def _parse_packet_line(output: str) -> tuple[int, int, float]:
    sent = received = 0
    loss_pct = 100.0
    for line in output.splitlines():
        if "packet loss" in line and "transmitted" in line:
            # Example: 5 packets transmitted, 5 received, 0% packet loss, time 4007ms
            parts = [p.strip() for p in line.split(",")]
            try:
                sent = int(parts[0].split(" ")[0])
                received = int(parts[1].split(" ")[0])
                loss_raw = [p for p in parts if "packet loss" in p][0].split("%")[0]
                loss_pct = float(loss_raw.split(" ")[-1])
                return sent, received, loss_pct
            except (ValueError, IndexError):
                continue
    return sent, received, loss_pct


def _stddev(values: list[float]) -> float:
    if len(values) <= 1:
        return 0.0
    avg = mean(values)
    variance = sum((v - avg) ** 2 for v in values) / len(values)
    return math.sqrt(variance)


def _ping_batch(endpoint: str, count: int, timeout_seconds: int = 5) -> tuple[int, int, float, list[float], str]:
    # With `ping -W 1`, total duration can exceed the naive timeout for higher counts.
    # Ensure the subprocess timeout is large enough to avoid false "simulated" fallbacks.
    timeout_seconds = max(int(timeout_seconds), int(count) + 4)
    ping = shutil.which("ping")
    if not ping:
        return count, count, 0.0, [deterministic_fallback_latency(100.0, i) for i in range(1, count + 1)], "simulated"

    cmd = [ping, "-c", str(count), "-W", "1", endpoint]
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout_seconds, check=False)  # nosec B603
    except (subprocess.SubprocessError, OSError, TimeoutError):
        # If ICMP is blocked in CI/sandbox, degrade rather than fail.
        return count, count, 0.0, [deterministic_fallback_latency(110.0, i) for i in range(1, count + 1)], "simulated"

    if proc.returncode != 0:
        # If ICMP is blocked in CI/sandbox, degrade rather than fail.
        return count, count, 0.0, [deterministic_fallback_latency(120.0, i) for i in range(1, count + 1)], "simulated"

    sent, received, loss_pct = _parse_packet_line(proc.stdout)
    latencies: list[float] = []
    for line in proc.stdout.splitlines():
        if "time=" in line and " ms" in line:
            try:
                value = line.split("time=", 1)[1].split(" ", 1)[0]
                latencies.append(float(value))
            except (ValueError, IndexError):
                continue

    return sent or count, received, float(loss_pct), latencies, "measured"


def run_benchmark(*, output_dir: Path, targets: list[tuple[str, str]], count: int, strict: bool = False) -> dict:
    out_dir = ensure_dir(output_dir)
    rows: list[dict] = []
    failures = 0

    for region, endpoint in targets:
        sent, received, loss_pct, latencies, source = _ping_batch(endpoint, count)
        jitter_ms = round(_stddev(latencies), 3)
        avg_latency_ms = round(mean(latencies), 3)
        status = "ok"
        if source == "simulated":
            status = "failed" if strict else "degraded"
            if strict:
                failures += 1
        else:
            if loss_pct >= 15.0:
                status = "failed"
                failures += 1
            elif loss_pct > 0:
                status = "degraded"

        rows.append(
            {
                "timestamp": utc_now_iso(),
                "region": region,
                "endpoint": endpoint,
                "sent": int(sent),
                "received": int(received),
                "loss_pct": round(float(loss_pct), 3),
                "jitter_ms": jitter_ms,
                "avg_latency_ms": avg_latency_ms,
                "source": source,
                "status": status,
            }
        )

    csv_path = write_csv(
        out_dir / "packet_loss.csv",
        rows,
        [
            "timestamp",
            "region",
            "endpoint",
            "sent",
            "received",
            "loss_pct",
            "jitter_ms",
            "avg_latency_ms",
            "source",
            "status",
        ],
    )

    payload = {
        "harness": "jitter_packet_loss",
        "generated_at": utc_now_iso(),
        "overall_status": "pass" if failures == 0 else "fail",
        "targets": [{"region": r, "endpoint": e} for r, e in targets],
        "strict": strict,
        "rows": rows,
        "csv": str(csv_path),
    }
    (out_dir / "jitter_packet_loss_result.json").write_text(json.dumps(payload, indent=2), encoding="utf-8")
    return payload


def main() -> int:
    parser = argparse.ArgumentParser(description="Collect packet loss and jitter metrics")
    parser.add_argument("--output-dir", default="artifacts/benchmark")
    parser.add_argument("--targets", default=DEFAULT_TARGETS, help="Comma separated region=host entries")
    parser.add_argument("--count", type=int, default=8)
    parser.add_argument("--strict", action="store_true", help="Fail when network probes cannot be measured")
    args = parser.parse_args()

    targets = parse_targets(args.targets)
    if not targets:
        print("No valid targets")
        return 1

    payload = run_benchmark(output_dir=Path(args.output_dir), targets=targets, count=max(2, args.count), strict=args.strict)
    print(json.dumps(payload, indent=2))
    return 0 if payload["overall_status"] == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
