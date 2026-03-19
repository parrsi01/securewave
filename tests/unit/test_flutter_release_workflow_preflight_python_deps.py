from __future__ import annotations

from pathlib import Path
import re


def test_flutter_release_workflow_installs_preflight_python_dependencies():
    workflow = Path(".github/workflows/flutter-release.yml").read_text(
        encoding="utf-8"
    )
    script = Path("scripts/release_preflight.sh").read_text(encoding="utf-8")

    assert "cryptography" in script

    preflight_job = re.search(
        r"release-preflight:.*?steps:\n(.*?)(?:\n\n  [A-Za-z0-9_-]+:|\Z)",
        workflow,
        re.S,
    )
    assert preflight_job is not None, "release-preflight job not found"
    job_text = preflight_job.group(1)

    assert "actions/setup-python" in job_text
    assert "python3 -m pip install cryptography" in job_text
