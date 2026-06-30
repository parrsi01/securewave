import os
import subprocess
from pathlib import Path

from cryptography.fernet import Fernet


ROOT = Path(__file__).resolve().parents[2]


def _release_env(**overrides):
    key = Fernet.generate_key().decode()
    env = os.environ.copy()
    env.update({
        "GITHUB_REF": "refs/tags/v0.0.0",
        "DEMO_MODE": "false",
        "WG_MOCK_MODE": "false",
        "AUTH_ENCRYPTION_KEY": key,
        "WG_ENCRYPTION_KEY": key,
        "EMAIL_PROVIDER": "smtp",
        "SMTP_HOST": "smtp.example.com",
        "SMTP_PORT": "587",
        "SMTP_USER": "smtp-user",
        "SMTP_PASSWORD": "smtp-password",
        "FROM_EMAIL": "noreply@securewave.app",
        "APP_URL": "https://securewave.app",
    })
    env.update(overrides)
    return env


def _run_preflight(env):
    return subprocess.run(
        ["bash", "scripts/release_preflight.sh"],
        cwd=ROOT,
        env=env,
        text=True,
        capture_output=True,
        timeout=30,
        check=False,
    )


def test_release_preflight_accepts_complete_smtp_email_env():
    result = _run_preflight(_release_env())

    assert result.returncode == 0, result.stderr
    assert "OK: Release preflight checks passed." in result.stdout


def test_release_preflight_rejects_missing_app_url():
    env = _release_env(APP_URL="")
    env.pop("APP_BASE_URL", None)

    result = _run_preflight(env)

    assert result.returncode == 1
    assert "APP_URL or APP_BASE_URL is required for release" in result.stderr


def test_release_preflight_rejects_invalid_smtp_port():
    result = _run_preflight(_release_env(SMTP_PORT="not-a-port"))

    assert result.returncode == 1
    assert "SMTP_PORT must be a numeric TCP port" in result.stderr
