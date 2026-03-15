"""
Tests for utils/env_validation.py

Validates environment configuration parsing, Fernet key validation,
and production mode requirements.
"""

import os
import pytest
from unittest.mock import patch

from utils.env_validation import (
    get_environment,
    is_testing,
    is_production,
    validate_fernet_key,
    email_config_issues,
    stripe_config_issues,
    production_env_errors,
)


class TestGetEnvironment:
    def test_defaults_to_development(self):
        with patch.dict(os.environ, {}, clear=True):
            os.environ.pop("ENVIRONMENT", None)
            assert get_environment() == "development"

    def test_returns_lowercase(self):
        with patch.dict(os.environ, {"ENVIRONMENT": "Production"}):
            assert get_environment() == "production"

    def test_strips_whitespace(self):
        with patch.dict(os.environ, {"ENVIRONMENT": "  staging  "}):
            assert get_environment() == "staging"


class TestIsProduction:
    def test_true_when_production(self):
        with patch.dict(os.environ, {"ENVIRONMENT": "production"}):
            assert is_production() is True

    def test_false_when_development(self):
        with patch.dict(os.environ, {"ENVIRONMENT": "development"}):
            assert is_production() is False

    def test_false_when_staging(self):
        with patch.dict(os.environ, {"ENVIRONMENT": "staging"}):
            assert is_production() is False


class TestValidateFernetKey:
    def test_missing_key_returns_error(self):
        assert validate_fernet_key(None) == "missing"
        assert validate_fernet_key("") == "missing"

    def test_valid_key_returns_none(self):
        from cryptography.fernet import Fernet
        valid_key = Fernet.generate_key().decode()
        assert validate_fernet_key(valid_key) is None

    def test_invalid_key_returns_error(self):
        result = validate_fernet_key("not-a-valid-key")
        assert result is not None
        assert "invalid" in result


class TestIsTesting:
    def test_false_when_unset(self):
        with patch.dict(os.environ, {}, clear=True):
            assert is_testing() is False

    def test_true_when_enabled(self):
        with patch.dict(os.environ, {"TESTING": "true"}):
            assert is_testing() is True

    @pytest.mark.parametrize("value", ["1", "yes", "on", "TRUE"])
    def test_only_true_string_enables(self, value: str):
        with patch.dict(os.environ, {"TESTING": value}):
            # is_testing() is intentionally strict for safety.
            assert is_testing() is (value.strip().lower() == "true")


class TestEmailConfigIssues:
    def test_smtp_requires_all_fields(self):
        with patch.dict(os.environ, {"EMAIL_PROVIDER": "smtp"}, clear=True):
            os.environ.pop("SMTP_HOST", None)
            os.environ.pop("SMTP_PORT", None)
            os.environ.pop("SMTP_USER", None)
            os.environ.pop("SMTP_PASSWORD", None)
            os.environ.pop("FROM_EMAIL", None)
            provider, missing = email_config_issues()
            assert provider == "smtp"
            assert "SMTP_HOST" in missing
            assert "SMTP_PORT" in missing
            assert "SMTP_USER" in missing
            assert "SMTP_PASSWORD" in missing
            assert "FROM_EMAIL" in missing

    def test_smtp_no_issues_when_configured(self):
        env = {
            "EMAIL_PROVIDER": "smtp",
            "SMTP_HOST": "smtp.example.com",
            "SMTP_PORT": "587",
            "SMTP_USER": "user@example.com",
            "SMTP_PASSWORD": "password",
            "FROM_EMAIL": "noreply@example.com",
        }
        with patch.dict(os.environ, env):
            provider, missing = email_config_issues()
            assert provider == "smtp"
            assert missing == []

    def test_sendgrid_requires_api_key(self):
        with patch.dict(os.environ, {"EMAIL_PROVIDER": "sendgrid"}, clear=True):
            os.environ.pop("SENDGRID_API_KEY", None)
            os.environ.pop("FROM_EMAIL", None)
            provider, missing = email_config_issues()
            assert provider == "sendgrid"
            assert "SENDGRID_API_KEY" in missing
            assert "FROM_EMAIL" in missing

    def test_ses_requires_region_and_from(self):
        with patch.dict(os.environ, {"EMAIL_PROVIDER": "ses"}, clear=True):
            os.environ.pop("AWS_SES_REGION", None)
            os.environ.pop("FROM_EMAIL", None)
            provider, missing = email_config_issues()
            assert provider == "ses"
            assert "FROM_EMAIL" in missing

    def test_unknown_provider_reported(self):
        with patch.dict(os.environ, {"EMAIL_PROVIDER": "unknown_provider"}, clear=True):
            provider, missing = email_config_issues()
            assert provider == "unknown_provider"
            assert "EMAIL_PROVIDER(unknown_provider)" in missing

    def test_from_email_fallback_to_smtp_user(self):
        env = {
            "EMAIL_PROVIDER": "smtp",
            "SMTP_HOST": "smtp.example.com",
            "SMTP_PORT": "587",
            "SMTP_USER": "user@example.com",
            "SMTP_PASSWORD": "password",
        }
        with patch.dict(os.environ, env, clear=True):
            os.environ.pop("FROM_EMAIL", None)
            os.environ.pop("SMTP_FROM_EMAIL", None)
            provider, missing = email_config_issues()
            # FROM_EMAIL should NOT be in missing because SMTP_USER is set
            assert "FROM_EMAIL" not in missing


class TestProductionEnvErrors:
    def test_no_errors_in_development(self):
        with patch.dict(os.environ, {"ENVIRONMENT": "development"}):
            errors = production_env_errors()
            assert errors == []

    def test_missing_encryption_keys_in_production(self):
        env = {
            "ENVIRONMENT": "production",
            "EMAIL_PROVIDER": "smtp",
            "SMTP_HOST": "smtp.example.com",
            "SMTP_PORT": "587",
            "SMTP_USER": "user@example.com",
            "SMTP_PASSWORD": "password",
            "FROM_EMAIL": "noreply@example.com",
        }
        with patch.dict(os.environ, env, clear=True):
            os.environ.pop("AUTH_ENCRYPTION_KEY", None)
            os.environ.pop("WG_ENCRYPTION_KEY", None)
            errors = production_env_errors()
            assert any("AUTH_ENCRYPTION_KEY" in e for e in errors)
            assert any("WG_ENCRYPTION_KEY" in e for e in errors)

    def test_testing_must_not_be_true_in_production(self):
        from cryptography.fernet import Fernet
        valid_key = Fernet.generate_key().decode()
        env = {
            "ENVIRONMENT": "production",
            "AUTH_ENCRYPTION_KEY": valid_key,
            "WG_ENCRYPTION_KEY": valid_key,
            "TESTING": "true",
            "EMAIL_PROVIDER": "smtp",
            "SMTP_HOST": "smtp.example.com",
            "SMTP_PORT": "587",
            "SMTP_USER": "user@example.com",
            "SMTP_PASSWORD": "password",
            "FROM_EMAIL": "noreply@example.com",
        }
        with patch.dict(os.environ, env):
            errors = production_env_errors()
            assert any("TESTING" in e for e in errors)

    def test_no_errors_when_fully_configured(self):
        from cryptography.fernet import Fernet
        valid_key = Fernet.generate_key().decode()
        env = {
            "ENVIRONMENT": "production",
            "API_BASE_URL": "https://api.securewave.example/api",
            "VPN_SERVER_ENDPOINT": "vpn.securewave.example:51820",
            "WG_SSH_KEY_PATH": "/tmp/securewave_test_wg_key",
            "WG_API_KEY": "test-api-key",
            "JWT_SECRET": "x" * 64,
            "DATABASE_URL": "postgresql://securewave:secret@localhost:5432/securewave",
            "AUTH_ENCRYPTION_KEY": valid_key,
            "WG_ENCRYPTION_KEY": valid_key,
            "TESTING": "false",
            "EMAIL_PROVIDER": "smtp",
            "SMTP_HOST": "smtp.example.com",
            "SMTP_PORT": "587",
            "SMTP_USER": "user@example.com",
            "SMTP_PASSWORD": "password",
            "FROM_EMAIL": "noreply@example.com",
            "STRIPE_SECRET_KEY": "sk_live_test",
            "STRIPE_PUBLISHABLE_KEY": "pk_live_test",
            "STRIPE_WEBHOOK_SECRET": "whsec_test",
            "STRIPE_PRICE_BASIC_MONTHLY": "price_basic",
            "STRIPE_PRICE_PREMIUM_MONTHLY": "price_premium",
            "STRIPE_PRICE_ULTRA_MONTHLY": "price_ultra",
            "PAYMENTS_MOCK": "false",
            "DEMO_MODE": "false",
            "WG_MOCK_MODE": "false",
        }
        with patch.dict(os.environ, env):
            errors = production_env_errors()
            assert errors == []

    def test_sqlite_requires_explicit_override(self):
        from cryptography.fernet import Fernet
        valid_key = Fernet.generate_key().decode()
        env = {
            "ENVIRONMENT": "production",
            "DATABASE_URL": "sqlite:///./securewave.db",
            "API_BASE_URL": "https://api.securewave.example/api",
            "VPN_SERVER_ENDPOINT": "vpn.securewave.example:51820",
            "WG_SSH_KEY_PATH": "/tmp/securewave_test_wg_key",
            "WG_API_KEY": "test-api-key",
            "JWT_SECRET": "x" * 64,
            "AUTH_ENCRYPTION_KEY": valid_key,
            "WG_ENCRYPTION_KEY": valid_key,
            "EMAIL_PROVIDER": "smtp",
            "SMTP_HOST": "smtp.example.com",
            "SMTP_PORT": "587",
            "SMTP_USER": "user@example.com",
            "SMTP_PASSWORD": "password",
            "FROM_EMAIL": "noreply@example.com",
            "STRIPE_SECRET_KEY": "sk_live_test",
            "STRIPE_PUBLISHABLE_KEY": "pk_live_test",
            "STRIPE_WEBHOOK_SECRET": "whsec_test",
            "STRIPE_PRICE_BASIC_MONTHLY": "price_basic",
            "STRIPE_PRICE_PREMIUM_MONTHLY": "price_premium",
            "STRIPE_PRICE_ULTRA_MONTHLY": "price_ultra",
        }
        with patch.dict(os.environ, env, clear=True):
            errors = production_env_errors()
            assert any("ALLOW_SQLITE_PRODUCTION" in e for e in errors)

    def test_mock_flags_are_rejected_in_production(self):
        from cryptography.fernet import Fernet
        valid_key = Fernet.generate_key().decode()
        env = {
            "ENVIRONMENT": "production",
            "API_BASE_URL": "https://api.securewave.example/api",
            "VPN_SERVER_ENDPOINT": "vpn.securewave.example:51820",
            "WG_SSH_KEY_PATH": "/tmp/securewave_test_wg_key",
            "WG_API_KEY": "test-api-key",
            "JWT_SECRET": "x" * 64,
            "DATABASE_URL": "postgresql://securewave:secret@localhost:5432/securewave",
            "AUTH_ENCRYPTION_KEY": valid_key,
            "WG_ENCRYPTION_KEY": valid_key,
            "EMAIL_PROVIDER": "smtp",
            "SMTP_HOST": "smtp.example.com",
            "SMTP_PORT": "587",
            "SMTP_USER": "user@example.com",
            "SMTP_PASSWORD": "password",
            "FROM_EMAIL": "noreply@example.com",
            "STRIPE_SECRET_KEY": "sk_live_test",
            "STRIPE_PUBLISHABLE_KEY": "pk_live_test",
            "STRIPE_WEBHOOK_SECRET": "whsec_test",
            "STRIPE_PRICE_BASIC_MONTHLY": "price_basic",
            "STRIPE_PRICE_PREMIUM_MONTHLY": "price_premium",
            "STRIPE_PRICE_ULTRA_MONTHLY": "price_ultra",
            "PAYMENTS_MOCK": "true",
            "DEMO_MODE": "true",
            "WG_MOCK_MODE": "true",
        }
        with patch.dict(os.environ, env, clear=True):
            errors = production_env_errors()
            assert any("PAYMENTS_MOCK" in e for e in errors)
            assert any("DEMO_MODE" in e for e in errors)
            assert any("WG_MOCK_MODE" in e for e in errors)

    def test_invalid_wireguard_endpoint_is_reported(self):
        from cryptography.fernet import Fernet
        valid_key = Fernet.generate_key().decode()
        env = {
            "ENVIRONMENT": "production",
            "API_BASE_URL": "https://api.securewave.example/api",
            "VPN_SERVER_ENDPOINT": "https://vpn.securewave.example:51820",
            "WG_SSH_KEY_PATH": "/tmp/securewave_test_wg_key",
            "WG_API_KEY": "test-api-key",
            "JWT_SECRET": "x" * 64,
            "DATABASE_URL": "postgresql://securewave:secret@localhost:5432/securewave",
            "AUTH_ENCRYPTION_KEY": valid_key,
            "WG_ENCRYPTION_KEY": valid_key,
            "EMAIL_PROVIDER": "smtp",
            "SMTP_HOST": "smtp.example.com",
            "SMTP_PORT": "587",
            "SMTP_USER": "user@example.com",
            "SMTP_PASSWORD": "password",
            "FROM_EMAIL": "noreply@example.com",
            "STRIPE_SECRET_KEY": "sk_live_test",
            "STRIPE_PUBLISHABLE_KEY": "pk_live_test",
            "STRIPE_WEBHOOK_SECRET": "whsec_test",
            "STRIPE_PRICE_BASIC_MONTHLY": "price_basic",
            "STRIPE_PRICE_PREMIUM_MONTHLY": "price_premium",
            "STRIPE_PRICE_ULTRA_MONTHLY": "price_ultra",
        }
        with patch.dict(os.environ, env, clear=True):
            errors = production_env_errors()
            assert any("VPN_SERVER_ENDPOINT" in e for e in errors)


class TestStripeConfigIssues:
    def test_requires_checkout_fields(self):
        with patch.dict(os.environ, {}, clear=True):
            missing = stripe_config_issues()
            assert "STRIPE_SECRET_KEY" in missing
            assert "STRIPE_WEBHOOK_SECRET" in missing
            assert "STRIPE_PRICE_BASIC_MONTHLY" in missing
