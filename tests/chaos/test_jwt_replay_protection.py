from pathlib import Path

from sandbox.chaos_tests.jwt_replay_attack import run_harness


def test_jwt_replay_protection(tmp_path: Path):
    payload = run_harness(output_dir=tmp_path)

    assert payload["overall_status"] == "pass"
    assert payload["metrics"]["replay_blocked"] is True
    assert payload["metrics"]["revoked_access_rejected"] is True
    assert (tmp_path / "jwt_replay_attack_result.json").exists()
    assert (tmp_path / "jwt_replay_attack_summary.md").exists()
