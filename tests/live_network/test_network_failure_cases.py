from pathlib import Path

from sandbox.live_validation.network_failure_cases import categorize_fault_result, run_fault_cases


def test_categorize_fault_result_values():
    assert categorize_fault_result("simulated", True) == "simulated"
    assert categorize_fault_result("pass", True) == "recovered"
    assert categorize_fault_result("pass", False) == "partial"
    assert categorize_fault_result("failed", False) == "failed"


def test_run_fault_cases_safe_mode(tmp_path: Path):
    result = run_fault_cases(
        output_dir=tmp_path,
        api_base_url="https://example.com",
        interface="wg0",
        execute=False,
        strict=False,
    )

    assert result["overall_status"] == "pass"
    assert result["destructive_allowed"] is False
    assert len(result["scenarios"]) == 4
    assert all(item["status"] == "simulated" for item in result["scenarios"])
    assert (tmp_path / "network_faults_result.json").exists()
    assert (tmp_path / "network_faults_summary.md").exists()


def test_run_fault_cases_strict_fails_in_safe_mode(tmp_path: Path):
    result = run_fault_cases(
        output_dir=tmp_path,
        api_base_url="https://example.com",
        interface="wg0",
        execute=False,
        strict=True,
    )
    assert result["overall_status"] == "fail"
