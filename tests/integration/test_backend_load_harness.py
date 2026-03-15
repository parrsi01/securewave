from __future__ import annotations

import asyncio
from argparse import Namespace

import pytest

from dev_tools.sandbox.load_tests.run_load_tests import run


@pytest.mark.slow
def test_load_harness_generates_summary_and_artifacts(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)

    summary = asyncio.run(
        run(
            Namespace(
                users=12,
                profile_concurrency=4,
                real_profile_requests=4,
                refresh_attempts=6,
                refresh_concurrency=3,
                config_iterations=25,
            )
        )
    )

    assert summary["tests_executed"] == 4
    assert summary["profile_generation"]["success"] >= summary["profile_generation"]["real_requests_executed"]
    assert summary["jwt_refresh"]["attempts"] >= 6
    assert summary["rate_limit_exhaustion"]["exhausted"] is True
    assert summary["wireguard_config_benchmark"]["iterations"] == 25

    artifacts_dir = tmp_path / "artifacts" / "load_tests"
    assert (artifacts_dir / "load_summary.json").exists()
    assert (artifacts_dir / "latency_distribution.csv").exists()
    assert (artifacts_dir / "cpu_memory_profile.json").exists()
