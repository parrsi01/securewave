#!/usr/bin/env python3
"""Aggregate live validation outputs into readiness report artifacts."""

from __future__ import annotations

import argparse
import csv
import json
import sys
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[3]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from dev_tools.sandbox.live_validation.common import mean, percentile, utc_now_iso, write_json, write_markdown


def _read_json(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}
    return data if isinstance(data, dict) else {}


def _read_csv_rows(path: Path) -> list[dict[str, str]]:
    if not path.exists():
        return []
    with path.open("r", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        return [dict(row) for row in reader]


def _float(row: dict[str, str], key: str, default: float = 0.0) -> float:
    try:
        return float(row.get(key, default))
    except Exception:
        return default


def compute_handshake_summary(rows: list[dict[str, str]]) -> dict[str, float]:
    latencies = [_float(row, "handshake_ms") for row in rows if row.get("success", "").lower() == "true"]
    return {
        "samples": float(len(latencies)),
        "p50_ms": round(percentile(latencies, 50), 3),
        "p95_ms": round(percentile(latencies, 95), 3),
        "avg_ms": round(mean(latencies), 3),
    }


def compute_dns_summary(rows: list[dict[str, str]]) -> dict[str, Any]:
    total = len(rows)
    leaks = sum(1 for row in rows if row.get("status", "").lower() != "ok")
    return {
        "checks": total,
        "leaks": leaks,
        "pass_rate_pct": round(0.0 if total == 0 else ((total - leaks) / total) * 100.0, 2),
    }


def compute_geo_summary(rows: list[dict[str, str]]) -> dict[str, Any]:
    grouped: dict[str, list[float]] = {}
    for row in rows:
        region = row.get("region", "unknown")
        grouped.setdefault(region, []).append(_float(row, "effective_latency_ms"))

    region_avgs = {region: round(mean(values), 3) for region, values in grouped.items()}
    barbados = region_avgs.get("barbados")
    europe = region_avgs.get("europe")
    corridor_delta = None
    if barbados is not None and europe is not None:
        corridor_delta = round(barbados - europe, 3)

    return {
        "regions": region_avgs,
        "caribbean_eu_delta_ms": corridor_delta,
    }


def compute_routing_summary(rows: list[dict[str, str]]) -> dict[str, Any]:
    total = len(rows)
    failures = sum(1 for row in rows if row.get("routing_status", "").lower() != "ok")
    api_failures = sum(1 for row in rows if row.get("api_health_status", "").lower() != "ok")
    return {
        "checks": total,
        "routing_failures": failures,
        "api_health_failures": api_failures,
        "pass_rate_pct": round(0.0 if total == 0 else ((total - failures) / total) * 100.0, 2),
    }


def compute_readiness_score(
    *,
    handshake: dict[str, float],
    dns: dict[str, Any],
    e2e_status: str,
    stress_status: str,
    fault_status: str,
) -> int:
    score = 100

    if e2e_status != "pass":
        score -= 30
    if stress_status != "pass":
        score -= 20
    if fault_status not in {"pass", "simulated"}:
        score -= 15

    if handshake.get("samples", 0.0) < 1:
        score -= 20
    if handshake.get("p95_ms", 0.0) > 2500:
        score -= 10
    if handshake.get("p50_ms", 0.0) > 1200:
        score -= 5

    dns_leaks = int(dns.get("leaks", 0) or 0)
    if dns_leaks > 0:
        score -= min(20, dns_leaks * 5)

    return max(0, min(100, score))


def generate_readiness_report(output_dir: Path) -> dict[str, Any]:
    out_dir = output_dir
    out_dir.mkdir(parents=True, exist_ok=True)

    e2e = _read_json(out_dir / "live_e2e_result.json")
    stress = _read_json(out_dir / "live_stress_summary.json")
    faults = _read_json(out_dir / "network_faults_result.json")

    handshake_rows = _read_csv_rows(out_dir / "handshake_stats.csv")
    dns_rows = _read_csv_rows(out_dir / "dns_checks.csv")
    geo_rows = _read_csv_rows(out_dir / "geo_latency_report.csv")
    routing_rows = _read_csv_rows(out_dir / "routing_checks.csv")

    handshake_summary = compute_handshake_summary(handshake_rows)
    dns_summary = compute_dns_summary(dns_rows)
    geo_summary = compute_geo_summary(geo_rows)
    routing_summary = compute_routing_summary(routing_rows)

    e2e_status = str(e2e.get("overall_status", "unknown"))
    stress_status = str(stress.get("overall_status", "unknown"))
    fault_status = str(faults.get("overall_status", "unknown"))

    readiness_score = compute_readiness_score(
        handshake=handshake_summary,
        dns=dns_summary,
        e2e_status=e2e_status,
        stress_status=stress_status,
        fault_status=fault_status,
    )

    summary = {
        "generated_at": utc_now_iso(),
        "overall_status": "pass" if readiness_score >= 80 else "warn" if readiness_score >= 60 else "fail",
        "readiness_score": readiness_score,
        "statuses": {
            "e2e": e2e_status,
            "stress": stress_status,
            "fault_injection": fault_status,
        },
        "handshake": handshake_summary,
        "dns": dns_summary,
        "geo": geo_summary,
        "routing": routing_summary,
    }

    write_json(out_dir / "validation_summary.json", summary)

    lines = [
        "# PRODUCTION_NETWORK_READINESS",
        "",
        f"- Generated: `{summary['generated_at']}`",
        f"- Overall status: **{summary['overall_status']}**",
        f"- Readiness score: **{summary['readiness_score']} / 100**",
        "",
        "## Handshake",
        f"- Samples: **{int(handshake_summary['samples'])}**",
        f"- P50: **{handshake_summary['p50_ms']} ms**",
        f"- P95: **{handshake_summary['p95_ms']} ms**",
        f"- Average: **{handshake_summary['avg_ms']} ms**",
        "",
        "## DNS Leak Results",
        f"- Checks: **{dns_summary['checks']}**",
        f"- Leaks: **{dns_summary['leaks']}**",
        f"- Pass rate: **{dns_summary['pass_rate_pct']}%**",
        "",
        "## Routing Safeguards",
        f"- Checks: **{routing_summary['checks']}**",
        f"- Routing failures: **{routing_summary['routing_failures']}**",
        f"- API health failures: **{routing_summary['api_health_failures']}**",
        f"- Pass rate: **{routing_summary['pass_rate_pct']}%**",
        "",
        "## Throughput and Latency",
        f"- Stress status: **{stress_status}**",
        f"- Geo status: **{e2e.get('geo_status', 'n/a')}**",
    ]
    if geo_summary.get("caribbean_eu_delta_ms") is not None:
        lines.append(f"- Barbados vs Europe delta: **{geo_summary['caribbean_eu_delta_ms']} ms**")

    lines.extend(
        [
            "",
            "## Recommendations",
            "1. Keep weekly live runs with strict mode enabled on at least one Linux runner with root access.",
            "2. Alert on handshake P95 above 2500ms or any DNS leak detection.",
            "3. Re-run fault injection after firewall or kernel networking changes.",
        ]
    )

    write_markdown(out_dir / "PRODUCTION_NETWORK_READINESS.md", "\n".join(lines) + "\n")
    return summary


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate production network readiness report")
    parser.add_argument("--output-dir", default="artifacts/live_validation")
    args = parser.parse_args()

    summary = generate_readiness_report(Path(args.output_dir))
    print(json.dumps(summary, indent=2))
    return 0 if summary.get("overall_status") in {"pass", "warn"} else 1


if __name__ == "__main__":
    raise SystemExit(main())
