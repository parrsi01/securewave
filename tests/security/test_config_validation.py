from __future__ import annotations

import os

import pytest
from cryptography.fernet import Fernet

from config.settings import ConfigurationError, collect_configuration_errors, get_settings


def _valid_production_env() -> dict[str, str]:
    key = Fernet.generate_key().decode()
    return {
        "ENVIRONMENT": "production",
        "TESTING": "false",
        "API_BASE_URL": "https://api.securewave.example/api",
        "APP_URL": "https://securewave.example",
        "DATABASE_URL": "postgresql://securewave:secret@localhost:5432/securewave",
        "REDIS_URL": "redis://127.0.0.1:6379/0",
        "JWT_SECRET": "x" * 64,
        "AUTH_ENCRYPTION_KEY": key,
        "WG_ENCRYPTION_KEY": key,
        "EMAIL_PROVIDER": "smtp",
        "SMTP_HOST": "smtp.example.com",
        "SMTP_PORT": "587",
        "SMTP_USER": "mailer@example.com",
        "SMTP_PASSWORD": "smtp-password",
        "FROM_EMAIL": "noreply@example.com",
        "STRIPE_SECRET_KEY": "stripe_secret_placeholder",
        "STRIPE_PUBLISHABLE_KEY": "stripe_publishable_placeholder",
        "STRIPE_WEBHOOK_SECRET": "stripe_webhook_placeholder",
        "STRIPE_PRICE_BASIC_MONTHLY": "price_basic",
        "STRIPE_PRICE_PREMIUM_MONTHLY": "price_premium",
        "STRIPE_PRICE_ULTRA_MONTHLY": "price_ultra",
        "VPN_SERVER_ENDPOINT": "vpn.securewave.example:51820",
        "WG_API_KEY": "wg-api-placeholder",
    }


def test_production_validation_requires_redis_url():
    env = _valid_production_env()
    env.pop("REDIS_URL")
    errors = collect_configuration_errors(env)
    assert "REDIS_URL missing or unsafe in production" in errors


def test_get_settings_fails_fast_when_required_secrets_are_missing(monkeypatch):
    env = _valid_production_env()
    env.pop("JWT_SECRET")
    env.pop("AUTH_ENCRYPTION_KEY")
    with monkeypatch.context() as mp:
        for key in list(os.environ):
            mp.delenv(key, raising=False)
        for key, value in env.items():
            mp.setenv(key, value)
        with pytest.raises(ConfigurationError) as exc:
            get_settings(refresh=True)
        assert "JWT_SECRET missing" in str(exc.value)
        assert "AUTH_ENCRYPTION_KEY missing" in str(exc.value)
