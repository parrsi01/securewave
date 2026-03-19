from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]

REQUIRED_ENV = {
    "SMTP_HOST": "smtp.example.com",
    "SMTP_PORT": "587",
    "SMTP_USER": "mailer",
    "SMTP_PASSWORD": "password",
    "FROM_EMAIL": "noreply@securewave.app",
    "AUTH_ENCRYPTION_KEY": "7jD1VRkjC3w69CxKkhj4ZmVn4-mp3ce6sUj7nXf9CBk=",
    "WG_ENCRYPTION_KEY": "K2yI29Q6aGmGVQ7Y4Y8CK7tt4FhTnms6yr7kyO4lVG4=",
    "DATABASE_URL": "postgresql+psycopg2://securewave:password@localhost:5432/securewave",
    "STRIPE_SECRET_KEY": "sk_live_test",
    "STRIPE_PUBLISHABLE_KEY": "pk_live_test",
    "STRIPE_WEBHOOK_SECRET": "whsec_test",
    "STRIPE_PRICE_BASIC_MONTHLY": "price_basic",
    "STRIPE_PRICE_PREMIUM_MONTHLY": "price_premium",
    "STRIPE_PRICE_ULTRA_MONTHLY": "price_ultra",
}


def _write_fake_gh(bin_dir: Path, log_file: Path) -> None:
    script = f"""#!/usr/bin/env bash
set -euo pipefail
if [[ "$1" == "repo" && "$2" == "view" ]]; then
  echo "parrsi01/securewave"
  exit 0
fi
if [[ "$1" == "secret" && "$2" == "set" ]]; then
  echo "$3|$*" >> "{log_file}"
  exit 0
fi
echo "unsupported gh invocation: $*" >&2
exit 1
"""
    path = bin_dir / "gh"
    path.write_text(script, encoding="utf-8")
    path.chmod(0o755)


def test_sync_github_release_secrets_dry_run_succeeds_when_env_complete(
    tmp_path: Path,
) -> None:
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    log_file = tmp_path / "gh.log"
    _write_fake_gh(bin_dir, log_file)

    python3 = shutil.which("python3")
    assert python3
    (bin_dir / "python3").symlink_to(python3)

    env = {**os.environ, **REQUIRED_ENV}
    env["PATH"] = f"{bin_dir}:{env['PATH']}"

    result = subprocess.run(
        ["/bin/bash", "scripts/sync_github_release_secrets.sh", "--dry-run"],
        cwd=ROOT,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0, result.stderr
    assert "OK: dry-run completed." in result.stdout
    assert not log_file.exists()


def test_sync_github_release_secrets_apply_writes_all_required_names(
    tmp_path: Path,
) -> None:
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    log_file = tmp_path / "gh.log"
    _write_fake_gh(bin_dir, log_file)

    python3 = shutil.which("python3")
    assert python3
    (bin_dir / "python3").symlink_to(python3)

    env = {**os.environ, **REQUIRED_ENV}
    env["PATH"] = f"{bin_dir}:{env['PATH']}"

    result = subprocess.run(
        ["/bin/bash", "scripts/sync_github_release_secrets.sh"],
        cwd=ROOT,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0, result.stderr
    logged = log_file.read_text(encoding="utf-8")
    for name in REQUIRED_ENV:
        assert f"{name}|" in logged
    assert "OK: GitHub production secrets synced." in result.stdout


def test_sync_github_release_secrets_fails_when_local_env_incomplete(
    tmp_path: Path,
) -> None:
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    log_file = tmp_path / "gh.log"
    _write_fake_gh(bin_dir, log_file)

    python3 = shutil.which("python3")
    assert python3
    (bin_dir / "python3").symlink_to(python3)

    env = os.environ.copy()
    env["PATH"] = f"{bin_dir}:{env['PATH']}"

    result = subprocess.run(
        ["/bin/bash", "scripts/sync_github_release_secrets.sh", "--dry-run"],
        cwd=ROOT,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 1
    assert "Local environment is missing required values for:" in result.stdout
    assert "SMTP_HOST" in result.stdout
