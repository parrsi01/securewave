#!/usr/bin/env python3
"""Optional competitor endpoint probing with normalized scoring."""

from __future__ import annotations

import argparse
import csv
import json
import sys
from pathlib import Path

# dev_tools/sandbox/benchmark/* -> repo root is 3 levels up
REPO_ROOT = Path(__file__).resolve().parents[3]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from dev_tools.sandbox.benchmark.common import (
    deterministic_fallback_latency,
    ensure_dir,
    mean,
    ping_latency_ms,
    utc_now_iso,
    write_csv,
)


def parse_competitors(raw: str) -> list[tuple[str, str]]:
    competitors: list[tuple[str, str]] = []
    for item in (part.strip() for part in raw.split(",") if part.strip()):
        if "=" not in item:
            continue
        name, endpoint = item.split("=", 1)
        name = name.strip().lower().replace(" ", "-")
        endpoint = endpoint.strip()
        if name and endpoint:
            competitors.append((name, endpoint))
    return competitors


def _securewave_baseline_ms(latency_csv: Path) -> float:
    if not latency_csv.exists():
        return 120.0

    values: list[float] = []
    with latency_csv.open("r", encoding="utf-8") as fh:
        reader = csv.DictReader(fh)
        for row in reader:
            try:
                values.append(float(row.get("latency_ms", "0") or 0.0))
            except ValueError:
                continue
    return mean(values) if values else 120.0


def run_probe(*, output_dir: Path, latency_csv: Path, competitors: list[tuple[str, str]], samples: int) -> dict:
    out_dir = ensure_dir(output_dir)
    baseline_ms = _securewave_baseline_ms(latency_csv)

    if not competitors:
        payload = {
            "harness": "competitor_probe",
            "generated_at": utc_now_iso(),
            "overall_status": "pass",
            "mode": "skipped",
            "reason": "no_competitor_endpoints_configured",
            "securewave_baseline_ms": round(baseline_ms, 3),
            "comparisons": [],
        }
        (out_dir / "competitor_probe_result.json").write_text(json.dumps(payload, indent=2), encoding="utf-8")
        return payload

    rows: list[dict] = []
    for name, endpoint in competitors:
        latencies: list[float] = []
        source = "measured"
        for idx in range(1, max(1, samples) + 1):
            measured = ping_latency_ms(endpoint)
            if measured is None:
                measured = deterministic_fallback_latency(130.0, idx)
                source = "simulated"
            latencies.append(float(measured))

        avg_latency_ms = mean(latencies)
        normalized_score = 0.0
        if avg_latency_ms > 0:
            normalized_score = max(0.0, (baseline_ms / avg_latency_ms) * 100.0)

        rows.append(
            {
                "timestamp": utc_now_iso(),
                "provider": name,
                "endpoint": endpoint,
                "avg_latency_ms": round(avg_latency_ms, 3),
                "securewave_baseline_ms": round(baseline_ms, 3),
                "normalized_score": round(normalized_score, 3),
                "source": source,
            }
        )

    csv_path = write_csv(
        out_dir / "competitor_comparison.csv",
        rows,
        [
            "timestamp",
            "provider",
            "endpoint",
            "avg_latency_ms",
            "securewave_baseline_ms",
            "normalized_score",
            "source",
        ],
    )

    payload = {
        "harness": "competitor_probe",
        "generated_at": utc_now_iso(),
        "overall_status": "pass",
        "mode": "executed",
        "securewave_baseline_ms": round(baseline_ms, 3),
        "comparisons": rows,
        "csv": str(csv_path),
    }
    (out_dir / "competitor_probe_result.json").write_text(json.dumps(payload, indent=2), encoding="utf-8")
    return payload


def main() -> int:
    parser = argparse.ArgumentParser(description="Probe competitor endpoints and normalize benchmark data")
    parser.add_argument("--output-dir", default="artifacts/benchmark")
    parser.add_argument("--latency-csv", default="artifacts/benchmark/latency_distribution.csv")
    parser.add_argument("--competitors", default="", help="Comma separated provider=host entries")
    parser.add_argument("--samples", type=int, default=4)
    args = parser.parse_args()

    payload = run_probe(
        output_dir=Path(args.output_dir),
        latency_csv=Path(args.latency_csv),
        competitors=parse_competitors(args.competitors),
        samples=args.samples,
    )
    print(json.dumps(payload, indent=2))
    return 0 if payload["overall_status"] == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
