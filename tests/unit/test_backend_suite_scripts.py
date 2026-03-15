from __future__ import annotations

import os
import subprocess
from pathlib import Path


def test_run_backend_api_suite_dry_run_lists_targets_and_coverage():
    script = Path("scripts/run_backend_api_suite.sh")
    result = subprocess.run(
        ["/bin/bash", str(script)],
        capture_output=True,
        text=True,
        env={**os.environ, "DRY_RUN": "true"},
        check=False,
    )
    assert result.returncode == 0
    assert "tests/integration/test_backend_matrix_additions.py" in result.stdout
    assert "coverage.xml" in result.stdout
    assert "--cov=routes" in result.stdout


def test_run_backend_infrastructure_validation_safe_dry_run():
    script = Path("scripts/run_backend_infrastructure_validation.sh")
    result = subprocess.run(
        ["/bin/bash", str(script)],
        capture_output=True,
        text=True,
        env={**os.environ, "DRY_RUN": "true", "MODE": "safe"},
        check=False,
    )
    assert result.returncode == 0
    assert "tests/live_network/test_live_validation_common.py" in result.stdout
    assert "tests/unit/test_infra_guard_scripts.py" in result.stdout


def test_run_backend_infrastructure_validation_live_dry_run():
    script = Path("scripts/run_backend_infrastructure_validation.sh")
    result = subprocess.run(
        ["/bin/bash", str(script), "--json-out", "/tmp/fleet.json"],
        capture_output=True,
        text=True,
        env={
            **os.environ,
            "DRY_RUN": "true",
            "MODE": "live",
            "SSH_BASELINE": "true",
            "LIVE_HANDSHAKE": "true",
        },
        check=False,
    )
    assert result.returncode == 0
    assert "validate_vpn_node_baseline.sh" in result.stdout
    assert "run_live_stress_tests.sh" in result.stdout
