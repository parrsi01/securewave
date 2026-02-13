from pathlib import Path

from dev_tools.sandbox.chaos_tests.network_drop import run_harness


def test_wireguard_crash_recovery(tmp_path: Path):
    payload = run_harness(output_dir=tmp_path, interface="wg0", execute=False)
    assert payload["overall_status"] == "pass"
    assert payload["metrics"]["destructive_mode"] is False
    assert any(step["name"] == "wireguard_process_crash" for step in payload["steps"])
    assert (tmp_path / "network_drop_result.json").exists()
    assert (tmp_path / "network_drop_summary.md").exists()
