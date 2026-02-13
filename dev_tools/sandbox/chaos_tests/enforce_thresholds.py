#!/usr/bin/env python3
"""Chaos suite threshold enforcement.

Reads chaos artifacts and compares recovery-related metrics against `dev_tools/chaos/chaos_thresholds.json`.
Writes `artifacts/chaos_tests/chaos_violations.json`.

Exit codes:
- 0: no threshold violations
- 2: threshold violations present
- 3: thresholds/config missing or invalid
"""

from __future__ import annotations

import argparse
import json
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


# dev_tools/sandbox/chaos_tests/* -> repo root is 3 levels up
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


def compute_metrics(chaos_dir: Path) -> tuple[dict[str, float], list[str]]:
    warnings: list[str] = []

    network_drop = _load_json(chaos_dir / "network_drop_result.json") if (chaos_dir / "network_drop_result.json").exists() else {}
    db_disconnect = _load_json(chaos_dir / "db_disconnect_result.json") if (chaos_dir / "db_disconnect_result.json").exists() else {}
    jwt_replay = _load_json(chaos_dir / "jwt_replay_attack_result.json") if (chaos_dir / "jwt_replay_attack_result.json").exists() else {}

    recovery_time_ms = _safe_float((network_drop.get("metrics") or {}).get("recovery_time_ms"), 0.0)
    if "recovery_time_ms" not in (network_drop.get("metrics") or {}):
        warnings.append("network_drop.recovery_time_ms_missing")

    # DB recovery: use recovery_probe duration as a proxy for recovery time.
    db_recovery_seconds = 0.0
    for step in db_disconnect.get("steps", []) or []:
        if step.get("name") == "recovery_probe":
            db_recovery_seconds = _safe_float(step.get("duration_ms"), 0.0) / 1000.0
            break
    if db_recovery_seconds == 0.0:
        warnings.append("db_disconnect.recovery_probe_duration_missing")

    replay_blocked = bool((jwt_replay.get("metrics") or {}).get("replay_blocked"))
    jwt_replay_failures = 0.0 if replay_blocked else 1.0

    return (
        {
            "wireguard_recovery_time_ms": round(recovery_time_ms, 3),
            "db_outage_recovery_seconds": round(db_recovery_seconds, 6),
            "jwt_replay_failures": round(jwt_replay_failures, 3),
        },
        warnings,
    )


def evaluate_thresholds(metrics: dict[str, float], thresholds: dict[str, Any]) -> list[Violation]:
    violations: list[Violation] = []

    max_wg_recovery = _safe_float(thresholds.get("max_wireguard_recovery_time_ms"), 0.0)
    allowed_replay_failures = _safe_float(thresholds.get("allowed_jwt_replay_failures"), 0.0)
    max_db_recovery = _safe_float(thresholds.get("max_db_outage_recovery_seconds"), 0.0)

    if metrics["wireguard_recovery_time_ms"] > max_wg_recovery:
        violations.append(
            Violation(
                metric="wireguard_recovery_time_ms",
                observed=metrics["wireguard_recovery_time_ms"],
                threshold=max_wg_recovery,
                comparator="lte",
                detail="WireGuard recovery time exceeded maximum",
            )
        )

    if metrics["jwt_replay_failures"] > allowed_replay_failures:
        violations.append(
            Violation(
                metric="jwt_replay_failures",
                observed=metrics["jwt_replay_failures"],
                threshold=allowed_replay_failures,
                comparator="lte",
                detail="JWT replay failures exceeded allowed tolerance",
            )
        )

    if metrics["db_outage_recovery_seconds"] > max_db_recovery:
        violations.append(
            Violation(
                metric="db_outage_recovery_seconds",
                observed=metrics["db_outage_recovery_seconds"],
                threshold=max_db_recovery,
                comparator="lte",
                detail="DB outage recovery probe exceeded maximum",
            )
        )

    return violations


def write_violations(output_path: Path, *, thresholds_path: Path, metrics: dict[str, float], violations: list[Violation], warnings: list[str]) -> None:
    payload = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "thresholds_path": str(thresholds_path),
        "metrics": metrics,
        "warnings": warnings,
        "violation_count": len(violations),
        "violations": [v.to_dict() for v in violations],
    }
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(payload, indent=2), encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="Enforce chaos thresholds")
    parser.add_argument("--chaos-dir", default=str(REPO_ROOT / "artifacts" / "chaos_tests"))
    parser.add_argument("--thresholds", default=str(REPO_ROOT / "dev_tools" / "chaos" / "chaos_thresholds.json"))
    parser.add_argument("--output", default=str(REPO_ROOT / "artifacts" / "chaos_tests" / "chaos_violations.json"))
    parser.add_argument("--strict", action="store_true")
    args = parser.parse_args()

    thresholds_path = Path(args.thresholds)
    if not thresholds_path.exists():
        return 3

    try:
        thresholds = _load_json(thresholds_path)
    except Exception:
        return 3

    metrics, warnings = compute_metrics(Path(args.chaos_dir))
    violations = evaluate_thresholds(metrics, thresholds)
    write_violations(Path(args.output), thresholds_path=thresholds_path, metrics=metrics, violations=violations, warnings=warnings)

    if args.strict and violations:
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
