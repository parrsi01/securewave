#!/usr/bin/env python3
"""Leak suite threshold enforcement.

Reads leak artifacts and compares derived scores against `leak/leak_thresholds.json`.
Writes `artifacts/leak_tests/leak_violations.json`.

Exit codes:
- 0: no threshold violations
- 2: threshold violations present
- 3: thresholds/config missing or invalid
"""

from __future__ import annotations

import argparse
import ipaddress
import json
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[2]


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


def _parse_default_route_interfaces(routes: list[str]) -> list[str]:
    interfaces: list[str] = []
    for line in routes:
        parts = line.split()
        if "dev" in parts:
            idx = parts.index("dev")
            if idx + 1 < len(parts):
                interfaces.append(parts[idx + 1])
    return interfaces


def compute_metrics(leak_dir: Path) -> tuple[dict[str, float], dict[str, Any], list[str]]:
    warnings: list[str] = []

    dns_payload = _load_json(leak_dir / "dns_leak_result.json") if (leak_dir / "dns_leak_result.json").exists() else {}
    ipv6_payload = _load_json(leak_dir / "ipv6_leak_result.json") if (leak_dir / "ipv6_leak_result.json").exists() else {}
    flap_payload = _load_json(leak_dir / "interface_flap_result.json") if (leak_dir / "interface_flap_result.json").exists() else {}

    dns_metrics = dns_payload.get("metrics") or {}
    expected = list(dns_metrics.get("expected_dns") or [])
    observed = list(dns_metrics.get("observed_dns") or [])
    allow_private = str((dns_payload.get("metrics") or {}).get("allow_private", "true")).lower() != "false"

    leaked: list[str] = []
    expected_set = {str(item) for item in expected}
    for raw in observed:
        ip_raw = str(raw).strip()
        if not ip_raw:
            continue
        if ip_raw in expected_set:
            continue
        try:
            ip_obj = ipaddress.ip_address(ip_raw)
        except ValueError:
            leaked.append(ip_raw)
            continue
        if allow_private and (ip_obj.is_private or ip_obj.is_loopback or ip_obj.is_link_local):
            continue
        leaked.append(ip_raw)

    dns_leak_score = float(len(leaked))

    # IPv6 misses: if IPv6 disabled => 0. If enabled and default route exists not via tunnel => 1.
    ipv6_metrics = ipv6_payload.get("metrics") or {}
    iface = str(ipv6_metrics.get("interface") or "wg0")
    iface_present = bool(ipv6_metrics.get("interface_present"))
    strict_live = bool(ipv6_metrics.get("strict_live"))
    disabled = str(ipv6_metrics.get("ipv6_disabled_value") or "0").strip() == "1"
    ipv6_routes = list(ipv6_metrics.get("ipv6_default_routes") or [])

    ipv6_misses = 0.0
    if disabled:
        ipv6_misses = 0.0
    elif not iface_present and not strict_live:
        warnings.append("ipv6_unmeasured_interface_missing")
        ipv6_misses = 0.0
    else:
        interfaces = _parse_default_route_interfaces(ipv6_routes)
        if any(dev != iface for dev in interfaces):
            ipv6_misses = 1.0

    flap_metrics = flap_payload.get("metrics") or {}
    flap_iface_present = bool(flap_metrics.get("interface_present"))
    flap_strict_live = bool(flap_metrics.get("strict_live"))
    kill_switch = flap_metrics.get("kill_switch") or {}
    down_ok = bool(kill_switch.get("down_ok"))
    up_ok = bool(kill_switch.get("up_ok"))

    kill_switch_score = 0.0
    if not flap_iface_present and not flap_strict_live:
        warnings.append("kill_switch_unmeasured_interface_missing")
        kill_switch_score = 100.0
    else:
        if down_ok and up_ok:
            kill_switch_score = 100.0
        elif down_ok and not up_ok:
            kill_switch_score = 50.0
        else:
            kill_switch_score = 0.0

    metrics = {
        "dns_leak_score": round(dns_leak_score, 3),
        "ipv6_block_misses": round(ipv6_misses, 3),
        "kill_switch_enforcement_score": round(kill_switch_score, 3),
    }

    detail = {
        "dns": {
            "expected": expected,
            "observed": observed,
            "leaked": leaked,
        }
    }

    return metrics, detail, warnings


def evaluate_thresholds(metrics: dict[str, float], thresholds: dict[str, Any]) -> list[Violation]:
    violations: list[Violation] = []

    max_dns_leak_score = _safe_float(thresholds.get("max_dns_leak_score"), 0.0)
    ipv6_miss_tol = _safe_float(thresholds.get("ipv6_block_miss_tolerance"), 0.0)
    min_kill_score = _safe_float(thresholds.get("min_kill_switch_enforcement_score"), 0.0)

    if metrics["dns_leak_score"] > max_dns_leak_score:
        violations.append(
            Violation(
                metric="dns_leak_score",
                observed=metrics["dns_leak_score"],
                threshold=max_dns_leak_score,
                comparator="lte",
                detail="DNS leak score exceeded maximum",
            )
        )

    if metrics["ipv6_block_misses"] > ipv6_miss_tol:
        violations.append(
            Violation(
                metric="ipv6_block_misses",
                observed=metrics["ipv6_block_misses"],
                threshold=ipv6_miss_tol,
                comparator="lte",
                detail="IPv6 block misses exceeded tolerance",
            )
        )

    if metrics["kill_switch_enforcement_score"] < min_kill_score:
        violations.append(
            Violation(
                metric="kill_switch_enforcement_score",
                observed=metrics["kill_switch_enforcement_score"],
                threshold=min_kill_score,
                comparator="gte",
                detail="Kill-switch enforcement score fell below minimum",
            )
        )

    return violations


def write_violations(output_path: Path, *, thresholds_path: Path, metrics: dict[str, float], detail: dict[str, Any], violations: list[Violation], warnings: list[str]) -> None:
    payload = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "thresholds_path": str(thresholds_path),
        "metrics": metrics,
        "detail": detail,
        "warnings": warnings,
        "violation_count": len(violations),
        "violations": [v.to_dict() for v in violations],
    }
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(payload, indent=2), encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="Enforce leak thresholds")
    parser.add_argument("--leak-dir", default=str(REPO_ROOT / "artifacts" / "leak_tests"))
    parser.add_argument("--thresholds", default=str(REPO_ROOT / "leak" / "leak_thresholds.json"))
    parser.add_argument("--output", default=str(REPO_ROOT / "artifacts" / "leak_tests" / "leak_violations.json"))
    parser.add_argument("--strict", action="store_true")
    args = parser.parse_args()

    thresholds_path = Path(args.thresholds)
    if not thresholds_path.exists():
        return 3

    try:
        thresholds = _load_json(thresholds_path)
    except Exception:
        return 3

    metrics, detail, warnings = compute_metrics(Path(args.leak_dir))
    violations = evaluate_thresholds(metrics, thresholds)
    write_violations(Path(args.output), thresholds_path=thresholds_path, metrics=metrics, detail=detail, violations=violations, warnings=warnings)

    if args.strict and violations:
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
