from __future__ import annotations

import os
import subprocess
from pathlib import Path


def test_run_dev_gate_dry_run_includes_local_validation_and_skips_release_only_steps():
    script = Path("scripts/run_dev_gate.sh")
    result = subprocess.run(
        ["/bin/bash", str(script)],
        capture_output=True,
        text=True,
        env={**os.environ, "DRY_RUN": "true"},
        check=False,
    )

    assert result.returncode == 0, result.stderr
    assert ".venv/bin/python -c import\\ main" in result.stdout
    assert "pytest -q" in result.stdout
    assert "flutter analyze" in result.stdout
    assert "go test ./..." in result.stdout
    assert "release_preflight.sh" not in result.stdout
    assert "sync_github_release_secrets.sh" not in result.stdout
    assert "audit_github_release_secrets.sh" not in result.stdout
