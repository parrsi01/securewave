#!/usr/bin/env python3
"""Benchmark threshold enforcement.

Reads benchmark artifacts and compares computed metrics against `dev_tools/benchmarks/thresholds.json`.
Writes `artifacts/benchmark/benchmark_violations.json`.

Exit codes:
- 0: no threshold violations
- 2: threshold violations present
- 3: thresholds/config missing or invalid
"""

from __future__ import annotations

import argparse
import csv
import json
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


# dev_tools/sandbox/benchmark/* -> repo root is 3 levels up
REPO_ROOT = Path(__file__).resolve().parents[3]


@dataclass(frozen=True)
class Violation:
    metric: str
    observed: float
    threshold: float
    comparator: str
    detail: str

    def to_dict(self) -> dict[str, Any]:
        return {
            "metric": self.metric,
            "observed": self.observed,
            "threshold": self.threshold,
            "comparator": self.comparator,
            "detail": self.detail,
        }


def _load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def _safe_float(raw: Any, default: float = 0.0) -> float:
    try:
        return float(raw)
    except (TypeError, ValueError):
        return default


def _percentile(values: list[float], pct: float) -> float:
    if not values:
        return 0.0
    if len(values) == 1:
        return float(values[0])
    ordered = sorted(values)
    k = (len(ordered) - 1) * (pct / 100.0)
    f = int(k)
    c = min(f + 1, len(ordered) - 1)
    return float(ordered[f] + (k - f) * (ordered[c] - ordered[f]))


def _read_csv(path: Path) -> list[dict[str, str]]:
    if not path.exists():
        return []
    with path.open("r", encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


def compute_metrics(benchmark_dir: Path) -> dict[str, float]:
    latency_rows = _read_csv(benchmark_dir / "latency_distribution.csv")
    packet_rows = _read_csv(benchmark_dir / "packet_loss.csv")
    throughput_rows = _read_csv(benchmark_dir / "throughput_summary.csv")

    handshake_result_path = benchmark_dir / "handshake_performance_result.json"
    handshake_payload = _load_json(handshake_result_path) if handshake_result_path.exists() else {}

    latencies = [_safe_float(row.get("latency_ms")) for row in latency_rows]
    p95_latency = _percentile(latencies, 95)

    jitter_values = [_safe_float(row.get("jitter_ms")) for row in packet_rows]
    max_jitter = max(jitter_values) if jitter_values else 0.0

    packet_loss_values = [_safe_float(row.get("loss_pct")) for row in packet_rows]
    max_packet_loss = max(packet_loss_values) if packet_loss_values else 0.0

    iterations = int(_safe_float(handshake_payload.get("iterations"), 0))
    success = int(_safe_float(handshake_payload.get("success_count"), 0))
    handshake_rate = (success / iterations) if iterations > 0 else 0.0

    download_values = [_safe_float(row.get("download_mbps")) for row in throughput_rows]
    upload_values = [_safe_float(row.get("upload_mbps")) for row in throughput_rows]
    throughput_effective = 0.0
    if download_values or upload_values:
        throughput_effective = min(
            max(download_values) if download_values else 0.0,
            max(upload_values) if upload_values else 0.0,
        )

    return {
        "p95_latency_ms": round(p95_latency, 3),
        "max_jitter_ms": round(max_jitter, 3),
        "max_packet_loss_pct": round(max_packet_loss, 3),
        "handshake_rate": round(handshake_rate, 4),
        "throughput_mbps": round(throughput_effective, 3),
        "latency_points": float(len(latency_rows)),
        "packet_points": float(len(packet_rows)),
        "throughput_points": float(len(throughput_rows)),
        "handshake_iterations": float(iterations),
    }


def evaluate_thresholds(metrics: dict[str, float], thresholds: dict[str, Any]) -> list[Violation]:
    violations: list[Violation] = []

    max_p95 = _safe_float(thresholds.get("max_p95_latency_ms"), 0.0)
    max_jitter = _safe_float(thresholds.get("max_jitter_ms"), 0.0)
    max_loss = _safe_float(thresholds.get("max_packet_loss_pct"), 0.0)
    min_handshake_rate = _safe_float(thresholds.get("min_handshake_rate"), 0.0)
    min_throughput = _safe_float(thresholds.get("min_throughput_mbps"), 0.0)

    if metrics["p95_latency_ms"] > max_p95:
        violations.append(
            Violation(
                metric="p95_latency_ms",
                observed=metrics["p95_latency_ms"],
                threshold=max_p95,
                comparator="lte",
                detail="p95 RTT over all samples exceeded maximum",
            )
        )

    if metrics["max_jitter_ms"] > max_jitter:
        violations.append(
            Violation(
                metric="max_jitter_ms",
                observed=metrics["max_jitter_ms"],
                threshold=max_jitter,
                comparator="lte",
                detail="max jitter exceeded maximum",
            )
        )

    if metrics["max_packet_loss_pct"] > max_loss:
        violations.append(
            Violation(
                metric="max_packet_loss_pct",
                observed=metrics["max_packet_loss_pct"],
                threshold=max_loss,
                comparator="lte",
                detail="max packet loss exceeded maximum",
            )
        )

    if metrics["handshake_rate"] < min_handshake_rate:
        violations.append(
            Violation(
                metric="handshake_rate",
                observed=metrics["handshake_rate"],
                threshold=min_handshake_rate,
                comparator="gte",
                detail="handshake success rate fell below minimum",
            )
        )

    if metrics["throughput_mbps"] < min_throughput:
        violations.append(
            Violation(
                metric="throughput_mbps",
                observed=metrics["throughput_mbps"],
                threshold=min_throughput,
                comparator="gte",
                detail="effective throughput fell below minimum",
            )
        )

    return violations


def write_violations(output_path: Path, *, thresholds_path: Path, metrics: dict[str, float], violations: list[Violation]) -> None:
    payload = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "thresholds_path": str(thresholds_path),
        "metrics": metrics,
        "violation_count": len(violations),
        "violations": [v.to_dict() for v in violations],
    }
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(payload, indent=2), encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="Enforce benchmark thresholds")
    parser.add_argument("--benchmark-dir", default=str(REPO_ROOT / "artifacts" / "benchmark"))
    parser.add_argument("--thresholds", default=str(REPO_ROOT / "dev_tools" / "benchmarks" / "thresholds.json"))
    parser.add_argument("--output", default=str(REPO_ROOT / "artifacts" / "benchmark" / "benchmark_violations.json"))
    parser.add_argument("--strict", action="store_true", help="Exit non-zero when violations exist")
    args = parser.parse_args()

    thresholds_path = Path(args.thresholds)
    if not thresholds_path.exists():
        return 3

    try:
        thresholds = _load_json(thresholds_path)
    except Exception:
        return 3

    metrics = compute_metrics(Path(args.benchmark_dir))
    violations = evaluate_thresholds(metrics, thresholds)
    write_violations(Path(args.output), thresholds_path=thresholds_path, metrics=metrics, violations=violations)

    if args.strict and violations:
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
