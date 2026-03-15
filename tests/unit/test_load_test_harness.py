import asyncio
from types import SimpleNamespace

from dev_tools.sandbox.load_tests import run_load_tests


def test_load_harness_generates_summary_and_artifacts(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)

    summary = asyncio.run(
        run_load_tests.run(
            SimpleNamespace(
                users=8,
                profile_concurrency=2,
                real_profile_requests=3,
                refresh_attempts=4,
                refresh_concurrency=2,
                config_iterations=5,
            )
        )
    )

    out_dir = tmp_path / "artifacts" / "load_tests"
    assert summary["tests_executed"] == 4
    assert summary["profile_generation"]["target_users"] == 8
    assert summary["profile_generation"]["success"] == 8
    assert summary["jwt_refresh"]["attempts"] == 8
    assert summary["rate_limit_exhaustion"]["exhausted"] is True
    assert summary["wireguard_config_benchmark"]["iterations"] == 5
    assert (out_dir / "load_summary.json").exists()
    assert (out_dir / "latency_distribution.csv").exists()
    assert (out_dir / "cpu_memory_profile.json").exists()
