from __future__ import annotations

import os
import stat
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def test_run_release_ops_from_env_sources_file_and_forwards_args(tmp_path: Path) -> None:
    env_file = tmp_path / "release.env"
    env_file.write_text(
        "export EMAIL_PROVIDER=smtp\nexport DATABASE_URL=postgresql://db\n",
        encoding="utf-8",
    )
    env_file.chmod(0o600)

    runner = tmp_path / "runner.sh"
    log_file = tmp_path / "runner.log"
    runner.write_text(
        f"""#!/usr/bin/env bash
set -euo pipefail
echo "EMAIL_PROVIDER=${{EMAIL_PROVIDER:-}}" >> "{log_file}"
echo "DATABASE_URL=${{DATABASE_URL:-}}" >> "{log_file}"
echo "ARGS=$*" >> "{log_file}"
""",
        encoding="utf-8",
    )
    runner.chmod(0o755)

    result = subprocess.run(
        [
            "/bin/bash",
            "scripts/run_release_ops_from_env.sh",
            "--env-file",
            str(env_file),
            "--dry-run",
            "--dispatch",
        ],
        cwd=ROOT,
        env={**os.environ, "RUN_RELEASE_OPS_SCRIPT": str(runner)},
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0, result.stderr
    logged = log_file.read_text(encoding="utf-8")
    assert "EMAIL_PROVIDER=smtp" in logged
    assert "DATABASE_URL=postgresql://db" in logged
    assert "ARGS=--dry-run --dispatch" in logged


def test_run_release_ops_from_env_rejects_loose_permissions(tmp_path: Path) -> None:
    env_file = tmp_path / "release.env"
    env_file.write_text("export EMAIL_PROVIDER=smtp\n", encoding="utf-8")
    env_file.chmod(0o644)

    result = subprocess.run(
        [
            "/bin/bash",
            "scripts/run_release_ops_from_env.sh",
            "--env-file",
            str(env_file),
        ],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 1
    assert "must not be readable by group/other" in result.stderr
    assert stat.S_IMODE(env_file.stat().st_mode) == 0o644
