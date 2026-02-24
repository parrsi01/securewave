#!/usr/bin/env python3
"""Generate an integrated validation master report from chaos/benchmark/leak artifacts.

This report is CI-friendly:
- It consumes suite summaries (`*_summary.json`) and threshold gate outputs (`*_violations.json`).
- It classifies gates into PASS/WARN/FAIL and computes a strict regression score.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[1]
ARTIFACTS = REPO_ROOT / "artifacts"


@dataclass
class SuiteSummary:
    name: str
    total: int
    passed: int
    failed: int

    @property
    def pass_rate(self) -> float:
        if self.total == 0:
            return 0.0
        return self.passed / self.total


@dataclass(frozen=True)
class GateCheck:
    suite: str
    metric: str
    observed: float
    threshold: float
    comparator: str
    passed: bool

    def to_line(self) -> str:
        op = "<=" if self.comparator == "lte" else ">="
        status = "PASS" if self.passed else "FAIL"
        return f"- [{self.suite}] {self.metric}: {self.observed:.3f} {op} {self.threshold:.3f} -> **{status}**"


def _load_json(path: Path, default: dict[str, Any]) -> dict[str, Any]:
    if not path.exists():
        return default
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (ValueError, OSError):
        return default


def _safe_float(raw: Any, default: float = 0.0) -> float:
    try:
        return float(raw)
    except (ValueError, TypeError):
        return default


def _suite_from_summary(name: str, payload: dict[str, Any]) -> SuiteSummary:
    total = int(payload.get("total") or payload.get("total_harnesses") or 0)
    passed = int(payload.get("passed") or 0)
    failed = int(payload.get("failed") or max(0, total - passed))
    return SuiteSummary(name=name, total=total, passed=passed, failed=failed)


def _score_suites(*, chaos: SuiteSummary, benchmark: SuiteSummary, leak: SuiteSummary) -> int:
    # Suite pass-rate component only. Threshold gates are handled separately by strict scoring.
    suite_component = (chaos.pass_rate * 35.0) + (benchmark.pass_rate * 35.0) + (leak.pass_rate * 30.0)
    final = max(0.0, min(100.0, suite_component))
    return int(round(final))


def _build_checks(
    *,
    suite: str,
    metrics: dict[str, Any],
    thresholds: dict[str, Any],
    mapping: list[tuple[str, str, str]],
) -> list[GateCheck]:
    checks: list[GateCheck] = []
    for metric_key, threshold_key, comparator in mapping:
        observed = _safe_float(metrics.get(metric_key), 0.0)
        threshold = _safe_float(thresholds.get(threshold_key), 0.0)
        if comparator == "lte":
            passed = observed <= threshold
        else:
            passed = observed >= threshold
        checks.append(
            GateCheck(
                suite=suite,
                metric=metric_key,
                observed=observed,
                threshold=threshold,
                comparator=comparator,
                passed=passed,
            )
        )
    return checks


def generate_report(output_path: Path) -> dict[str, Any]:
    chaos_summary = _load_json(ARTIFACTS / "chaos_tests" / "chaos_summary.json", {})
    benchmark_summary = _load_json(ARTIFACTS / "benchmark" / "benchmark_summary.json", {})
    leak_summary = _load_json(ARTIFACTS / "leak_tests" / "leak_summary.json", {})

    chaos = _suite_from_summary("chaos", chaos_summary)
    benchmark = _suite_from_summary("benchmark", benchmark_summary)
    leak = _suite_from_summary("leak", leak_summary)

    # Thresholds were moved under dev_tools/*; keep a fallback for older layouts.
    benchmark_thresholds = _load_json(
        (REPO_ROOT / "dev_tools" / "benchmarks" / "thresholds.json")
        if (REPO_ROOT / "dev_tools" / "benchmarks" / "thresholds.json").exists()
        else (REPO_ROOT / "benchmarks" / "thresholds.json"),
        {},
    )
    chaos_thresholds = _load_json(
        (REPO_ROOT / "dev_tools" / "chaos" / "chaos_thresholds.json")
        if (REPO_ROOT / "dev_tools" / "chaos" / "chaos_thresholds.json").exists()
        else (REPO_ROOT / "chaos" / "chaos_thresholds.json"),
        {},
    )
    leak_thresholds = _load_json(
        (REPO_ROOT / "dev_tools" / "leak" / "leak_thresholds.json")
        if (REPO_ROOT / "dev_tools" / "leak" / "leak_thresholds.json").exists()
        else (REPO_ROOT / "leak" / "leak_thresholds.json"),
        {},
    )

    benchmark_gate = _load_json(ARTIFACTS / "benchmark" / "benchmark_violations.json", {})
    chaos_gate = _load_json(ARTIFACTS / "chaos_tests" / "chaos_violations.json", {})
    leak_gate = _load_json(ARTIFACTS / "leak_tests" / "leak_violations.json", {})

    warnings: list[str] = []
    violations: list[dict[str, Any]] = []

    if not benchmark_gate:
        warnings.append("benchmark_violations_missing")
    if not chaos_gate:
        warnings.append("chaos_violations_missing")
    if not leak_gate:
        warnings.append("leak_violations_missing")

    warnings.extend([f"chaos:{w}" for w in (chaos_gate.get("warnings") or [])])
    warnings.extend([f"leak:{w}" for w in (leak_gate.get("warnings") or [])])

    violations.extend([{"suite": "benchmark", **v} for v in (benchmark_gate.get("violations") or [])])
    violations.extend([{"suite": "chaos", **v} for v in (chaos_gate.get("violations") or [])])
    violations.extend([{"suite": "leak", **v} for v in (leak_gate.get("violations") or [])])

    benchmark_checks = _build_checks(
        suite="benchmark",
        metrics=benchmark_gate.get("metrics") or {},
        thresholds=benchmark_thresholds,
        mapping=[
            ("p95_latency_ms", "max_p95_latency_ms", "lte"),
            ("max_jitter_ms", "max_jitter_ms", "lte"),
            ("max_packet_loss_pct", "max_packet_loss_pct", "lte"),
            ("handshake_rate", "min_handshake_rate", "gte"),
            ("throughput_mbps", "min_throughput_mbps", "gte"),
        ],
    )

    chaos_checks = _build_checks(
        suite="chaos",
        metrics=chaos_gate.get("metrics") or {},
        thresholds=chaos_thresholds,
        mapping=[
            ("wireguard_recovery_time_ms", "max_wireguard_recovery_time_ms", "lte"),
            ("jwt_replay_failures", "allowed_jwt_replay_failures", "lte"),
            ("db_outage_recovery_seconds", "max_db_outage_recovery_seconds", "lte"),
        ],
    )

    leak_checks = _build_checks(
        suite="leak",
        metrics=leak_gate.get("metrics") or {},
        thresholds=leak_thresholds,
        mapping=[
            ("dns_leak_score", "max_dns_leak_score", "lte"),
            ("ipv6_block_misses", "ipv6_block_miss_tolerance", "lte"),
            ("kill_switch_enforcement_score", "min_kill_switch_enforcement_score", "gte"),
        ],
    )

    checks = benchmark_checks + chaos_checks + leak_checks
    passed_checks = [c for c in checks if c.passed]
    failed_checks = [c for c in checks if not c.passed]

    base_score = _score_suites(chaos=chaos, benchmark=benchmark, leak=leak)

    strict_violation_count = len(violations)
    strict_warning_count = len(warnings)

    # Strict scoring is punitive: violations are hard regressions, warnings are "unmeasured/partial-signal".
    strict_score = int(
        round(
            max(
                0.0,
                min(
                    100.0,
                    float(base_score) - (strict_violation_count * 15.0) - (strict_warning_count * 2.0),
                ),
            )
        )
    )

    strict_status = "pass"
    if strict_violation_count > 0:
        strict_status = "fail"
    elif strict_warning_count > 0:
        strict_status = "pass_with_warnings"

    recommendations = [
        "Treat any threshold violations as deploy-blocking regressions; only adjust thresholds after measuring on a known-good baseline.",
        "Run strict-live chaos/leak on staging nodes (root + wg0 present) to convert WARN(unmeasured) into measured PASS/FAIL signals.",
        "Persist artifacts/benchmark/*.csv in long-term storage to detect corridor regressions over time.",
    ]

    payload: dict[str, Any] = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "chaos": chaos.__dict__,
        "benchmark": benchmark.__dict__,
        "leak": leak.__dict__,
        "threshold_gates": {
            "benchmark": {
                "violations_path": str(ARTIFACTS / "benchmark" / "benchmark_violations.json"),
                "violation_count": int(_safe_float(benchmark_gate.get("violation_count"), 0)),
            },
            "chaos": {
                "violations_path": str(ARTIFACTS / "chaos_tests" / "chaos_violations.json"),
                "violation_count": int(_safe_float(chaos_gate.get("violation_count"), 0)),
                "warnings": chaos_gate.get("warnings") or [],
            },
            "leak": {
                "violations_path": str(ARTIFACTS / "leak_tests" / "leak_violations.json"),
                "violation_count": int(_safe_float(leak_gate.get("violation_count"), 0)),
                "warnings": leak_gate.get("warnings") or [],
            },
        },
        "threshold_checks": [c.__dict__ for c in checks],
        "threshold_warnings": warnings,
        "threshold_violations": violations,
        "validation_master_score": base_score,
        "validation_master_strict_score": strict_score,
        "validation_master_strict_status": strict_status,
        "recommendations": recommendations,
    }

    lines = [
        "# Validation Master Report",
        "",
        f"Generated: `{payload['generated_at']}`",
        "",
        "## Results Summary",
        "",
        f"- Chaos: **{chaos.passed}/{chaos.total}** passed",
        f"- Benchmark: **{benchmark.passed}/{benchmark.total}** passed",
        f"- Leak: **{leak.passed}/{leak.total}** passed",
        "",
        "## Strict Threshold Gating",
        "",
        f"- Status: **{strict_status}**",
        f"- Threshold violations: **{strict_violation_count}**",
        f"- Threshold warnings: **{strict_warning_count}**",
        "",
        "### Gate Artifacts",
        "",
        f"- Benchmark: `{ARTIFACTS / 'benchmark' / 'benchmark_violations.json'}`",
        f"- Chaos: `{ARTIFACTS / 'chaos_tests' / 'chaos_violations.json'}`",
        f"- Leak: `{ARTIFACTS / 'leak_tests' / 'leak_violations.json'}`",
        "",
        "## PASS",
        "",
    ]
    if passed_checks:
        lines.extend([c.to_line() for c in passed_checks])
    else:
        lines.append("- None")

    lines.append("")
    lines.append("## WARN")
    lines.append("")
    if warnings:
        for w in warnings:
            lines.append(f"- {w}")
    else:
        lines.append("- None")

    lines.append("")
    lines.append("## FAIL")
    lines.append("")
    if violations:
        for v in violations:
            metric = v.get("metric", "unknown")
            suite = v.get("suite", "unknown")
            observed = _safe_float(v.get("observed"), 0.0)
            threshold = _safe_float(v.get("threshold"), 0.0)
            comparator = v.get("comparator", "lte")
            op = "<=" if comparator == "lte" else ">="
            detail = v.get("detail", "")
            lines.append(f"- [{suite}] {metric}: {observed:.3f} {op} {threshold:.3f} ({detail})")
    else:
        lines.append("- None")

    lines.append("")
    lines.append("## Recommendations")
    lines.append("")
    for recommendation in recommendations:
        lines.append(f"- {recommendation}")

    lines.append("")
    lines.append("## Scores")
    lines.append("")
    lines.append(f"- VALIDATION_MASTER_SCORE: **{base_score}**")
    lines.append(f"- VALIDATION_MASTER_STRICT_SCORE: **{strict_score}**")

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return payload


def main() -> int:
    output_path = ARTIFACTS / "validation_master_report.md"
    payload = generate_report(output_path)
    print(json.dumps(payload, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
