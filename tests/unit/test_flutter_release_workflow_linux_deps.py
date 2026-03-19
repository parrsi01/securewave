from __future__ import annotations

from pathlib import Path
import re


def test_flutter_release_workflow_installs_linux_packaging_prereqs():
    workflow = Path(".github/workflows/flutter-release.yml").read_text(
        encoding="utf-8"
    )
    build_deb = Path("securewave_app/scripts/build_deb.sh").read_text(
        encoding="utf-8"
    )
    build_appimage = Path("securewave_app/scripts/build_appimage.sh").read_text(
        encoding="utf-8"
    )

    required_commands = set(
        re.findall(r"command -v ([A-Za-z0-9._+-]+)", build_deb + "\n" + build_appimage)
    )
    assert "wg-quick" in required_commands

    match = re.search(
        r"- name: Install Linux deps\n\s*run: \|\n(.*?)(?:\n\s*- name:|\Z)",
        workflow,
        re.S,
    )
    assert match is not None, "Linux dependency install step not found"
    install_block = match.group(1)

    assert "wireguard-tools" in install_block
