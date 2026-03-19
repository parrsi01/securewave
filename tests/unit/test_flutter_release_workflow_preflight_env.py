from __future__ import annotations

from pathlib import Path
import re


def test_flutter_release_workflow_passes_required_preflight_env():
    script = Path("scripts/release_preflight.sh").read_text(encoding="utf-8")
    workflow = Path(".github/workflows/flutter-release.yml").read_text(
        encoding="utf-8"
    )

    required = set(re.findall(r'require_var\s+"([A-Z0-9_]+)"', script))
    expected_extra = {"FROM_EMAIL", "AUTH_ENCRYPTION_KEY", "WG_ENCRYPTION_KEY"}

    match = re.search(
        r"- name: Release preflight checks.*?env:\n(.*?)\n\s*run: bash scripts/release_preflight.sh",
        workflow,
        re.S,
    )
    assert match is not None, "release-preflight env block not found in workflow"

    env_block = match.group(1)
    provided = set(re.findall(r"^\s+([A-Z0-9_]+):", env_block, re.M))

    assert required.issubset(provided)
    assert expected_extra.issubset(provided)
