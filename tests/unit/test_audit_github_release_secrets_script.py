from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def _write_fake_gh(bin_dir: Path) -> None:
    script = """#!/usr/bin/env bash
set -euo pipefail
if [[ "$1" == "repo" && "$2" == "view" ]]; then
  echo "parrsi01/securewave"
  exit 0
fi
if [[ "$1" == "secret" && "$2" == "list" ]]; then
  if [[ "${*: -2:1}" == "--env" ]]; then
    cat <<'EOF'
SMTP_HOST\t2026-03-19T00:00:00Z
SMTP_PORT\t2026-03-19T00:00:00Z
SMTP_USER\t2026-03-19T00:00:00Z
SMTP_PASSWORD\t2026-03-19T00:00:00Z
FROM_EMAIL\t2026-03-19T00:00:00Z
AUTH_ENCRYPTION_KEY\t2026-03-19T00:00:00Z
WG_ENCRYPTION_KEY\t2026-03-19T00:00:00Z
DATABASE_URL\t2026-03-19T00:00:00Z
STRIPE_SECRET_KEY\t2026-03-19T00:00:00Z
STRIPE_PUBLISHABLE_KEY\t2026-03-19T00:00:00Z
STRIPE_WEBHOOK_SECRET\t2026-03-19T00:00:00Z
STRIPE_PRICE_BASIC_MONTHLY\t2026-03-19T00:00:00Z
STRIPE_PRICE_PREMIUM_MONTHLY\t2026-03-19T00:00:00Z
STRIPE_PRICE_ULTRA_MONTHLY\t2026-03-19T00:00:00Z
EOF
  fi
  exit 0
fi
echo "unsupported gh invocation: $*" >&2
exit 1
"""
    path = bin_dir / "gh"
    path.write_text(script, encoding="utf-8")
    path.chmod(0o755)


def test_audit_github_release_secrets_script_reports_green_when_inventory_complete(
    tmp_path: Path,
) -> None:
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    _write_fake_gh(bin_dir)

    python3 = shutil.which("python3")
    assert python3
    (bin_dir / "python3").symlink_to(python3)

    env = os.environ.copy()
    env["PATH"] = f"{bin_dir}:{env['PATH']}"

    result = subprocess.run(
        ["/bin/bash", "scripts/audit_github_release_secrets.sh"],
        cwd=ROOT,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0, result.stderr
    assert "OK: all required release secrets are present." in result.stdout


def test_audit_github_release_secrets_script_reports_missing_inventory(
    tmp_path: Path,
) -> None:
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    script = """#!/usr/bin/env bash
set -euo pipefail
if [[ "$1" == "repo" && "$2" == "view" ]]; then
  echo "parrsi01/securewave"
  exit 0
fi
if [[ "$1" == "secret" && "$2" == "list" ]]; then
  exit 0
fi
exit 1
"""
    gh_path = bin_dir / "gh"
    gh_path.write_text(script, encoding="utf-8")
    gh_path.chmod(0o755)

    python3 = shutil.which("python3")
    assert python3
    (bin_dir / "python3").symlink_to(python3)

    env = os.environ.copy()
    env["PATH"] = f"{bin_dir}:{env['PATH']}"

    result = subprocess.run(
        ["/bin/bash", "scripts/audit_github_release_secrets.sh"],
        cwd=ROOT,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 1
    assert "Missing required release secrets:" in result.stdout
    assert "SMTP_HOST" in result.stdout
