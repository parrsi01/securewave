from __future__ import annotations

import os
import subprocess
from pathlib import Path


def _valid_release_env() -> dict[str, str]:
    return {
        **os.environ,
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
        "GITHUB_REF": "refs/tags/v4.0.0",
    }


def test_release_preflight_rejects_securewave_mock_vpn_flag():
    script = Path("scripts/release_preflight.sh")
    result = subprocess.run(
        ["/bin/bash", str(script)],
        capture_output=True,
        text=True,
        env={**_valid_release_env(), "SECUREWAVE_MOCK_VPN": "true"},
        check=False,
    )

    assert result.returncode != 0
    assert "SECUREWAVE_MOCK_VPN must be false for release." in result.stderr


def test_release_preflight_rejects_non_default_mock_latency():
    script = Path("scripts/release_preflight.sh")
    result = subprocess.run(
        ["/bin/bash", str(script)],
        capture_output=True,
        text=True,
        env={**_valid_release_env(), "SECUREWAVE_MOCK_VPN_LATENCY_MS": "450"},
        check=False,
    )

    assert result.returncode != 0
    assert "SECUREWAVE_MOCK_VPN_LATENCY_MS must be unset or 300 for release." in result.stderr


def test_release_preflight_allows_manual_non_tag_validation_when_opted_in():
    script = Path("scripts/release_preflight.sh")
    env = _valid_release_env()
    env["GITHUB_REF"] = "refs/heads/release-preflight-validation-20260319"
    env["RELEASE_PREFLIGHT_ALLOW_NON_TAG"] = "true"
    for flag in (
        "TESTING",
        "PAYMENTS_MOCK",
        "DEMO_MODE",
        "WG_MOCK_MODE",
        "SECUREWAVE_SIM_MODE",
        "SECUREWAVE_MOCK_VPN",
        "SECUREWAVE_MOCK_VPN_FORCE_FAILURE",
        "SECUREWAVE_MOCK_VPN_UNSTABLE",
        "SECUREWAVE_MOCK_VPN_LATENCY_MS",
    ):
        env.pop(flag, None)

    result = subprocess.run(
        ["/bin/bash", str(script)],
        capture_output=True,
        text=True,
        env=env,
        check=False,
    )

    assert result.returncode == 0, result.stderr
    assert "skipping v* tag enforcement" in result.stdout


def test_release_preflight_missing_fernet_key_prints_generation_command_only():
    script = Path("scripts/release_preflight.sh")
    env = _valid_release_env()
    env.pop("AUTH_ENCRYPTION_KEY", None)

    result = subprocess.run(
        ["/bin/bash", str(script)],
        capture_output=True,
        text=True,
        env=env,
        check=False,
    )

    assert result.returncode != 0
    assert "AUTH_ENCRYPTION_KEY is required for release." in result.stderr
    assert "Fernet.generate_key().decode()" in result.stderr
