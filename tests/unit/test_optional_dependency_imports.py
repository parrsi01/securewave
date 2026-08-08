"""Regression tests for optional dependencies not blocking authentication imports."""

import os
import subprocess
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]


def _run_clean_import(script: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, "-c", script],
        cwd=REPO_ROOT,
        env={**os.environ, "PYTHONPATH": str(REPO_ROOT)},
        capture_output=True,
        text=True,
        check=False,
    )


def test_stripe_sdk_is_not_imported_for_service_module_import():
    """A missing or malformed payment SDK must not block core app imports."""
    result = _run_clean_import(
        "import sys; "
        "import services.stripe_service; "
        "assert 'stripe' not in sys.modules"
    )

    assert result.returncode == 0, result.stderr
