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
        "PAYMENTS_MOCK": "false",
        "DEMO_BILLING": "false",
        "PAYMENT_PROVIDER": "stripe",
        "STRIPE_SECRET_KEY": "sk_live_test",
        "STRIPE_WEBHOOK_SECRET": "whsec_test",
        "STRIPE_PUBLISHABLE_KEY": "pk_live_test",
        "STRIPE_PORTAL_CONFIG_ID": "bpc_test",
        "STRIPE_PRICE_BASIC_MONTHLY": "price_basic_monthly",
        "STRIPE_PRICE_BASIC_YEARLY": "price_basic_yearly",
        "STRIPE_PRICE_PREMIUM_MONTHLY": "price_premium_monthly",
        "STRIPE_PRICE_PREMIUM_YEARLY": "price_premium_yearly",
        "STRIPE_PRICE_ULTRA_MONTHLY": "price_ultra_monthly",
        "STRIPE_PRICE_ULTRA_YEARLY": "price_ultra_yearly",
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


def _write_env_file(path: Path, values: dict[str, str]) -> None:
    path.write_text("\n".join(f"{key}={value}" for key, value in values.items()) + "\n")


def _email_env_values(**overrides):
    key = Fernet.generate_key().decode()
    values = {
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
    }
    values.update(overrides)
    return values


def _billing_env_values(**overrides):
    values = {
        "PAYMENTS_MOCK": "false",
        "DEMO_BILLING": "false",
        "PAYMENT_PROVIDER": "stripe",
        "STRIPE_SECRET_KEY": "sk_live_test",
        "STRIPE_WEBHOOK_SECRET": "whsec_test",
        "STRIPE_PUBLISHABLE_KEY": "pk_live_test",
        "STRIPE_PORTAL_CONFIG_ID": "bpc_test",
        "STRIPE_PRICE_BASIC_MONTHLY": "price_basic_monthly",
        "STRIPE_PRICE_BASIC_YEARLY": "price_basic_yearly",
        "STRIPE_PRICE_PREMIUM_MONTHLY": "price_premium_monthly",
        "STRIPE_PRICE_PREMIUM_YEARLY": "price_premium_yearly",
        "STRIPE_PRICE_ULTRA_MONTHLY": "price_ultra_monthly",
        "STRIPE_PRICE_ULTRA_YEARLY": "price_ultra_yearly",
    }
    values.update(overrides)
    return values


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


def test_email_release_gate_loads_billing_env_for_full_preflight(tmp_path):
    email_env = tmp_path / "release_email.env"
    billing_env = tmp_path / "billing_release.env"
    _write_env_file(email_env, _email_env_values())
    _write_env_file(billing_env, _billing_env_values())

    result = subprocess.run(
        [
            "bash",
            "scripts/email_release_gate.sh",
            "--env-file",
            str(email_env),
            "--billing-env-file",
            str(billing_env),
            "--dry-run-tag",
        ],
        cwd=ROOT,
        text=True,
        capture_output=True,
        timeout=30,
        check=False,
    )

    assert result.returncode == 0, result.stderr
    assert "loaded private email env file" in result.stdout
    assert "loaded private billing env file" in result.stdout
    assert "OK: Release preflight checks passed." in result.stdout


def test_billing_release_gate_loads_release_env_for_full_preflight(tmp_path):
    email_env = tmp_path / "release_email.env"
    billing_env = tmp_path / "billing_release.env"
    _write_env_file(email_env, _email_env_values())
    _write_env_file(billing_env, _billing_env_values())

    result = subprocess.run(
        [
            "bash",
            "scripts/billing_release_gate.sh",
            "--env-file",
            str(billing_env),
            "--release-env-file",
            str(email_env),
            "--release-preflight",
            "--dry-run-tag",
        ],
        cwd=ROOT,
        text=True,
        capture_output=True,
        timeout=30,
        check=False,
    )

    assert result.returncode == 0, result.stderr
    assert "loaded private billing env file" in result.stdout
    assert "loaded private release env file" in result.stdout
    assert "OK: Release preflight checks passed." in result.stdout


def test_release_go_no_go_composes_private_env_files(tmp_path):
    email_env = tmp_path / "release_email.env"
    billing_env = tmp_path / "billing_release.env"
    _write_env_file(email_env, _email_env_values())
    _write_env_file(billing_env, _billing_env_values())

    result = subprocess.run(
        [
            "bash",
            "scripts/release_go_no_go.sh",
            "--email-env-file",
            str(email_env),
            "--billing-env-file",
            str(billing_env),
            "--dry-run-tag",
        ],
        cwd=ROOT,
        text=True,
        capture_output=True,
        timeout=30,
        check=False,
    )

    assert result.returncode == 0, result.stderr
    assert "[STEP] email configuration" in result.stdout
    assert "[STEP] billing configuration" in result.stdout
    assert "[STEP] full release preflight" in result.stdout
    assert "OK: composed release go/no-go checks passed." in result.stdout


def test_release_go_no_go_generates_missing_keys_for_current_run(tmp_path):
    email_env = tmp_path / "release_email.env"
    billing_env = tmp_path / "billing_release.env"
    email_values = _email_env_values()
    email_values["AUTH_ENCRYPTION_KEY"] = ""
    email_values["WG_ENCRYPTION_KEY"] = ""
    _write_env_file(email_env, email_values)
    _write_env_file(billing_env, _billing_env_values())

    result = subprocess.run(
        [
            "bash",
            "scripts/release_go_no_go.sh",
            "--email-env-file",
            str(email_env),
            "--billing-env-file",
            str(billing_env),
            "--generate-missing-keys",
            "--dry-run-tag",
        ],
        cwd=ROOT,
        text=True,
        capture_output=True,
        timeout=30,
        check=False,
    )

    assert result.returncode == 0, result.stderr
    assert "generated AUTH_ENCRYPTION_KEY for this run" in result.stdout
    assert "generated WG_ENCRYPTION_KEY for this run" in result.stdout
    assert "OK: composed release go/no-go checks passed." in result.stdout
