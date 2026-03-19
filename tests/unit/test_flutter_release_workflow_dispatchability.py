from __future__ import annotations

from pathlib import Path
import re


def test_flutter_release_workflow_avoids_secret_expressions_in_job_if():
    workflow = Path(".github/workflows/flutter-release.yml").read_text(
        encoding="utf-8"
    )
    job_ifs = re.findall(r"^\s+if:\s+(.+)$", workflow, re.M)
    for expression in job_ifs:
        assert re.search(r"\bsecrets\.", expression) is None


def test_flutter_release_preflight_job_is_pinned_and_hardened():
    workflow = Path(".github/workflows/flutter-release.yml").read_text(
        encoding="utf-8"
    )

    assert "timeout-minutes: 10" in workflow
    assert "actions/setup-python@v5.6.0" in workflow
    assert 'python-version: "3.11"' in workflow
    assert "sudo apt-get install -y build-essential libssl-dev libffi-dev python3-dev" in workflow
    assert 'echo "[CI] Python version:" && python3 --version' in workflow
    assert 'echo "[CI] Pip packages:" && pip list' in workflow
