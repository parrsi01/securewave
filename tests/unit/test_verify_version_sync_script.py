from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def test_verify_version_sync_falls_back_without_ripgrep(tmp_path: Path) -> None:
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()

    required_bins = [
        "awk",
        "cat",
        "dirname",
        "echo",
        "grep",
        "head",
        "pwd",
        "tr",
        "xargs",
    ]
    for name in required_bins:
        source = shutil.which(name)
        assert source, f"missing required binary for test: {name}"
        (bin_dir / name).symlink_to(source)

    env = os.environ.copy()
    env["PATH"] = str(bin_dir)

    result = subprocess.run(
        ["/bin/bash", "scripts/verify_version_sync.sh"],
        cwd=ROOT,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0, result.stderr
    assert "OK: version sync verified" in result.stdout
    assert "rg: command not found" not in result.stderr
