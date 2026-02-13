from pathlib import Path

from sandbox.chaos_tests.db_disconnect import run_harness


def test_db_outage_recovery(tmp_path: Path):
    db_file = tmp_path / "chaos.db"
    payload = run_harness(
        output_dir=tmp_path,
        db_url=f"sqlite:///{db_file}",
        outage_url="postgresql://invalid:invalid@127.0.0.1:1/unreachable",
    )

    assert payload["overall_status"] == "pass"
    assert payload["metrics"]["outage_failure_observed"] is True
    assert payload["metrics"]["recovery_connected"] is True
    assert (tmp_path / "db_disconnect_result.json").exists()
    assert (tmp_path / "db_disconnect_summary.md").exists()
