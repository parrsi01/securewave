"""Shared benchmark helpers."""

from __future__ import annotations

import csv
import shutil
import subprocess  # nosec B404 - controlled benchmark command execution
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable, List, Optional


@dataclass
class LatencySample:
    timestamp: str
    region: str
    endpoint: str
    iteration: int
    latency_ms: float
    source: str
    status: str


@dataclass
class ThroughputSample:
    timestamp: str
    test_mode: str
    download_mbps: float
    upload_mbps: float
    duration_s: float
    source: str


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def percentile(values: List[float], pct: float) -> float:
    if not values:
        return 0.0
    if len(values) == 1:
        return float(values[0])
    ordered = sorted(values)
    k = (len(ordered) - 1) * (pct / 100.0)
    f = int(k)
    c = min(f + 1, len(ordered) - 1)
    return float(ordered[f] + (k - f) * (ordered[c] - ordered[f]))


def mean(values: Iterable[float]) -> float:
    data = list(values)
    if not data:
        return 0.0
    return float(sum(data) / len(data))


def parse_ping_latency_ms(output: str) -> Optional[float]:
    for line in output.splitlines():
        if "time=" in line and " ms" in line:
            try:
                tail = line.split("time=", 1)[1]
                value = tail.split(" ", 1)[0]
                return float(value)
            except (ValueError, IndexError):
                continue
        if "=" in line and "/" in line and "ms" in line:
            # Linux summary format: rtt min/avg/max/mdev = a/b/c/d ms
            right = line.split("=", 1)[1].replace(" ms", "").strip()
            parts = right.split("/")
            if len(parts) >= 2:
                try:
                    return float(parts[1])
                except ValueError:
                    continue
    return None


def ping_latency_ms(host: str, *, timeout_seconds: int = 2) -> Optional[float]:
    ping = shutil.which("ping")
    if not ping:
        return None

    cmd = [ping, "-c", "1", "-W", "1", host]
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout_seconds, check=False)  # nosec B603
    except (subprocess.SubprocessError, OSError, TimeoutError):
        return None
    if proc.returncode != 0:
        return None
    return parse_ping_latency_ms(proc.stdout)


def write_csv(path: str | Path, rows: list[dict], fieldnames: list[str]) -> Path:
    target = Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    with target.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)
    return target


def deterministic_fallback_latency(base_ms: float, iteration: int) -> float:
    # Keep fallback deterministic for stable test assertions.
    jitter = ((iteration % 7) - 3) * 1.35
    return round(max(1.0, base_ms + jitter), 3)


def ensure_dir(path: str | Path) -> Path:
    p = Path(path)
    p.mkdir(parents=True, exist_ok=True)
    return p


def benchmark_status_from_failures(failures: int) -> str:
    return "pass" if failures == 0 else "fail"
