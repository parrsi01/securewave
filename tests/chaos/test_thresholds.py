import json
from pathlib import Path

from sandbox.chaos_tests.enforce_thresholds import compute_metrics, evaluate_thresholds, write_violations


def test_chaos_thresholds_violation_detected(tmp_path: Path):
    chaos_dir = tmp_path / "chaos_tests"
    chaos_dir.mkdir(parents=True)

    (chaos_dir / "network_drop_result.json").write_text(
        json.dumps({"metrics": {"recovery_time_ms": 20000.0}}, indent=2),
        encoding="utf-8",
    )
    (chaos_dir / "db_disconnect_result.json").write_text(
        json.dumps({"steps": [{"name": "recovery_probe", "duration_ms": 8000.0}]}, indent=2),
        encoding="utf-8",
    )
    (chaos_dir / "jwt_replay_attack_result.json").write_text(
        json.dumps({"metrics": {"replay_blocked": False}}, indent=2),
        encoding="utf-8",
    )

    thresholds = {
        "max_wireguard_recovery_time_ms": 15000.0,
        "allowed_jwt_replay_failures": 0,
        "max_db_outage_recovery_seconds": 5.0,
    }

    metrics, warnings = compute_metrics(chaos_dir)
    violations = evaluate_thresholds(metrics, thresholds)

    assert {v.metric for v in violations} == {
        "wireguard_recovery_time_ms",
        "jwt_replay_failures",
        "db_outage_recovery_seconds",
    }

    out = tmp_path / "chaos_violations.json"
    write_violations(out, thresholds_path=tmp_path / "thresholds.json", metrics=metrics, violations=violations, warnings=warnings)
    assert out.exists()


def test_chaos_thresholds_pass(tmp_path: Path):
    chaos_dir = tmp_path / "chaos_tests"
    chaos_dir.mkdir(parents=True)

    (chaos_dir / "network_drop_result.json").write_text(
        json.dumps({"metrics": {"recovery_time_ms": 100.0}}, indent=2),
        encoding="utf-8",
    )
    (chaos_dir / "db_disconnect_result.json").write_text(
        json.dumps({"steps": [{"name": "recovery_probe", "duration_ms": 50.0}]}, indent=2),
        encoding="utf-8",
    )
    (chaos_dir / "jwt_replay_attack_result.json").write_text(
        json.dumps({"metrics": {"replay_blocked": True}}, indent=2),
        encoding="utf-8",
    )

    thresholds = {
        "max_wireguard_recovery_time_ms": 15000.0,
        "allowed_jwt_replay_failures": 0,
        "max_db_outage_recovery_seconds": 5.0,
    }

    metrics, warnings = compute_metrics(chaos_dir)
    violations = evaluate_thresholds(metrics, thresholds)
    assert violations == []
