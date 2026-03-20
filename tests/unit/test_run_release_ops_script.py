from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def _write_exec(path: Path, body: str) -> None:
    path.write_text(body, encoding="utf-8")
    path.chmod(0o755)


def test_run_release_ops_dry_run_executes_verify_sync_audit_only(
    tmp_path: Path,
) -> None:
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    log_file = tmp_path / "ops.log"

    _write_exec(
        bin_dir / "gh",
        f"""#!/usr/bin/env bash
set -euo pipefail
echo "GH:$*" >> "{log_file}"
if [[ "$1" == "repo" && "$2" == "view" ]]; then
  echo "parrsi01/securewave"
  exit 0
fi
exit 0
""",
    )

    verify = tmp_path / "verify.sh"
    sync = tmp_path / "sync.sh"
    audit = tmp_path / "audit.sh"
    _write_exec(verify, f"#!/usr/bin/env bash\nset -euo pipefail\necho verify >> \"{log_file}\"\n")
    _write_exec(sync, f"#!/usr/bin/env bash\nset -euo pipefail\necho sync:$* >> \"{log_file}\"\n")
    _write_exec(audit, f"#!/usr/bin/env bash\nset -euo pipefail\necho audit:$* >> \"{log_file}\"\n")

    env = os.environ.copy()
    env["PATH"] = f"{bin_dir}:{env['PATH']}"
    env["VERIFY_PRODUCTION_ENV_SCRIPT"] = str(verify)
    env["SYNC_GITHUB_RELEASE_SECRETS_SCRIPT"] = str(sync)
    env["AUDIT_GITHUB_RELEASE_SECRETS_SCRIPT"] = str(audit)

    result = subprocess.run(
        ["/bin/bash", "scripts/run_release_ops.sh", "--dry-run", "--dispatch"],
        cwd=ROOT,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0, result.stderr
    logged = log_file.read_text(encoding="utf-8")
    assert "verify" in logged
    assert "sync:--env production --repo parrsi01/securewave --dry-run" in logged
    assert "audit:production" in logged
    assert "GH:workflow run" not in logged
    assert "SKIP: dry-run mode does not dispatch GitHub Actions." in result.stdout


def test_run_release_ops_dispatches_workflow_when_requested(tmp_path: Path) -> None:
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    log_file = tmp_path / "ops.log"

    _write_exec(
        bin_dir / "gh",
        f"""#!/usr/bin/env bash
set -euo pipefail
echo "GH:$*" >> "{log_file}"
if [[ "$1" == "repo" && "$2" == "view" ]]; then
  echo "parrsi01/securewave"
  exit 0
fi
exit 0
""",
    )

    verify = tmp_path / "verify.sh"
    sync = tmp_path / "sync.sh"
    audit = tmp_path / "audit.sh"
    _write_exec(verify, f"#!/usr/bin/env bash\nset -euo pipefail\necho verify >> \"{log_file}\"\n")
    _write_exec(sync, f"#!/usr/bin/env bash\nset -euo pipefail\necho sync:$* >> \"{log_file}\"\n")
    _write_exec(audit, f"#!/usr/bin/env bash\nset -euo pipefail\necho audit:$* >> \"{log_file}\"\n")

    env = os.environ.copy()
    env["PATH"] = f"{bin_dir}:{env['PATH']}"
    env["VERIFY_PRODUCTION_ENV_SCRIPT"] = str(verify)
    env["SYNC_GITHUB_RELEASE_SECRETS_SCRIPT"] = str(sync)
    env["AUDIT_GITHUB_RELEASE_SECRETS_SCRIPT"] = str(audit)

    result = subprocess.run(
        ["/bin/bash", "scripts/run_release_ops.sh", "--dispatch", "--ref", "release-preflight-validation-20260319"],
        cwd=ROOT,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0, result.stderr
    logged = log_file.read_text(encoding="utf-8")
    assert "GH:workflow run .github/workflows/flutter-release.yml --ref release-preflight-validation-20260319" in logged
    assert "OK: release workflow dispatched." in result.stdout


def test_run_release_ops_fails_fast_on_verify_error(tmp_path: Path) -> None:
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    log_file = tmp_path / "ops.log"

    _write_exec(
        bin_dir / "gh",
        f"""#!/usr/bin/env bash
set -euo pipefail
echo "GH:$*" >> "{log_file}"
if [[ "$1" == "repo" && "$2" == "view" ]]; then
  echo "parrsi01/securewave"
  exit 0
fi
exit 0
""",
    )

    verify = tmp_path / "verify.sh"
    sync = tmp_path / "sync.sh"
    audit = tmp_path / "audit.sh"
    _write_exec(verify, f"#!/usr/bin/env bash\nset -euo pipefail\necho verify >> \"{log_file}\"\nexit 1\n")
    _write_exec(sync, f"#!/usr/bin/env bash\nset -euo pipefail\necho sync >> \"{log_file}\"\n")
    _write_exec(audit, f"#!/usr/bin/env bash\nset -euo pipefail\necho audit >> \"{log_file}\"\n")

    env = os.environ.copy()
    env["PATH"] = f"{bin_dir}:{env['PATH']}"
    env["VERIFY_PRODUCTION_ENV_SCRIPT"] = str(verify)
    env["SYNC_GITHUB_RELEASE_SECRETS_SCRIPT"] = str(sync)
    env["AUDIT_GITHUB_RELEASE_SECRETS_SCRIPT"] = str(audit)

    result = subprocess.run(
        ["/bin/bash", "scripts/run_release_ops.sh", "--dry-run"],
        cwd=ROOT,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode != 0
    logged = log_file.read_text(encoding="utf-8")
    assert "verify" in logged
    assert "sync" not in logged
    assert "audit" not in logged
