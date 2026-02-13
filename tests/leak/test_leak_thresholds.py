import json
from pathlib import Path

from sandbox.leak_tests.enforce_thresholds import compute_metrics, evaluate_thresholds, write_violations


def test_leak_thresholds_violation_detected(tmp_path: Path):
    leak_dir = tmp_path / "leak_tests"
    leak_dir.mkdir(parents=True)

    (leak_dir / "dns_leak_result.json").write_text(
        json.dumps(
            {
                "metrics": {
                    "expected_dns": ["1.1.1.1"],
                    "observed_dns": ["8.8.8.8"],
                    "allow_private": True,
                }
            },
            indent=2,
        ),
        encoding="utf-8",
    )
    (leak_dir / "ipv6_leak_result.json").write_text(
        json.dumps(
            {
                "metrics": {
                    "interface": "wg0",
                    "interface_present": True,
                    "strict_live": True,
                    "ipv6_disabled_value": "0",
                    "ipv6_default_routes": ["default dev eth0"],
                }
            },
            indent=2,
        ),
        encoding="utf-8",
    )
    (leak_dir / "interface_flap_result.json").write_text(
        json.dumps(
            {
                "metrics": {
                    "interface_present": True,
                    "strict_live": True,
                    "kill_switch": {"down_ok": True, "up_ok": False},
                }
            },
            indent=2,
        ),
        encoding="utf-8",
    )

    thresholds = {
        "max_dns_leak_score": 0.0,
        "ipv6_block_miss_tolerance": 0,
        "min_kill_switch_enforcement_score": 80.0,
    }

    metrics, detail, warnings = compute_metrics(leak_dir)
    violations = evaluate_thresholds(metrics, thresholds)

    assert {v.metric for v in violations} == {
        "dns_leak_score",
        "ipv6_block_misses",
        "kill_switch_enforcement_score",
    }

    out = tmp_path / "leak_violations.json"
    write_violations(
        out,
        thresholds_path=tmp_path / "thresholds.json",
        metrics=metrics,
        detail=detail,
        violations=violations,
        warnings=warnings,
    )
    assert out.exists()


def test_leak_thresholds_pass_when_unmeasured_in_ci(tmp_path: Path):
    leak_dir = tmp_path / "leak_tests"
    leak_dir.mkdir(parents=True)

    (leak_dir / "dns_leak_result.json").write_text(
        json.dumps(
            {
                "metrics": {
                    "expected_dns": ["1.1.1.1"],
                    "observed_dns": ["127.0.0.53"],
                    "allow_private": True,
                }
            },
            indent=2,
        ),
        encoding="utf-8",
    )
    (leak_dir / "ipv6_leak_result.json").write_text(
        json.dumps(
            {
                "metrics": {
                    "interface": "wg0",
                    "interface_present": False,
                    "strict_live": False,
                    "ipv6_disabled_value": "0",
                    "ipv6_default_routes": [],
                }
            },
            indent=2,
        ),
        encoding="utf-8",
    )
    (leak_dir / "interface_flap_result.json").write_text(
        json.dumps(
            {
                "metrics": {
                    "interface_present": False,
                    "strict_live": False,
                    "kill_switch": {"down_ok": True, "up_ok": False},
                }
            },
            indent=2,
        ),
        encoding="utf-8",
    )

    thresholds = {
        "max_dns_leak_score": 0.0,
        "ipv6_block_miss_tolerance": 0,
        "min_kill_switch_enforcement_score": 80.0,
    }

    metrics, detail, warnings = compute_metrics(leak_dir)
    violations = evaluate_thresholds(metrics, thresholds)
    assert violations == []
