"""
Tests for utils/env_validation.py

Validates environment configuration parsing, Fernet key validation,
and production mode requirements.
"""

import os
from unittest.mock import patch

from utils.env_validation import (
    get_environment,
    is_production,
    validate_fernet_key,
    demo_mode_enabled,
    wg_mock_mode_enabled,
    email_config_issues,
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
        # Valid Fernet key (base64 encoded 32-byte key)
        valid_key = "VGhpc0lzQTMyQnl0ZUtleUZvclRlc3Rpbmc9MQ=="
        # Actually generate a proper key for testing
        from cryptography.fernet import Fernet
        valid_key = Fernet.generate_key().decode()
        assert validate_fernet_key(valid_key) is None

    def test_invalid_key_returns_error(self):
        result = validate_fernet_key("not-a-valid-key")
        assert result is not None
        assert "invalid" in result


class TestDemoModeEnabled:
    def test_explicit_true(self):
        with patch.dict(os.environ, {"DEMO_MODE": "true", "ENVIRONMENT": "development"}):
            assert demo_mode_enabled() is True

    def test_explicit_false(self):
        with patch.dict(os.environ, {"DEMO_MODE": "false", "ENVIRONMENT": "development"}):
            assert demo_mode_enabled() is False

    def test_defaults_true_in_development(self):
        env = {"ENVIRONMENT": "development"}
        with patch.dict(os.environ, env, clear=True):
            os.environ.pop("DEMO_MODE", None)
            assert demo_mode_enabled() is True

    def test_defaults_false_in_production(self):
        env = {"ENVIRONMENT": "production"}
        with patch.dict(os.environ, env, clear=True):
            os.environ.pop("DEMO_MODE", None)
            assert demo_mode_enabled() is False

    def test_defaults_false_in_staging(self):
        env = {"ENVIRONMENT": "staging"}
        with patch.dict(os.environ, env, clear=True):
            os.environ.pop("DEMO_MODE", None)
            assert demo_mode_enabled() is False


class TestWgMockModeEnabled:
    def test_explicit_true(self):
        with patch.dict(os.environ, {"WG_MOCK_MODE": "true", "ENVIRONMENT": "development"}):
            assert wg_mock_mode_enabled() is True

    def test_explicit_false(self):
        with patch.dict(os.environ, {"WG_MOCK_MODE": "false", "ENVIRONMENT": "development"}):
            assert wg_mock_mode_enabled() is False

    def test_defaults_true_in_development(self):
        env = {"ENVIRONMENT": "development"}
        with patch.dict(os.environ, env, clear=True):
            os.environ.pop("WG_MOCK_MODE", None)
            assert wg_mock_mode_enabled() is True

    def test_defaults_false_in_production(self):
        env = {"ENVIRONMENT": "production"}
        with patch.dict(os.environ, env, clear=True):
            os.environ.pop("WG_MOCK_MODE", None)
            assert wg_mock_mode_enabled() is False


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
            "DEMO_MODE": "false",
            "WG_MOCK_MODE": "false",
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

    def test_demo_mode_must_be_false_in_production(self):
        from cryptography.fernet import Fernet
        valid_key = Fernet.generate_key().decode()
        env = {
            "ENVIRONMENT": "production",
            "AUTH_ENCRYPTION_KEY": valid_key,
            "WG_ENCRYPTION_KEY": valid_key,
            "DEMO_MODE": "true",
            "WG_MOCK_MODE": "false",
            "EMAIL_PROVIDER": "smtp",
            "SMTP_HOST": "smtp.example.com",
            "SMTP_PORT": "587",
            "SMTP_USER": "user@example.com",
            "SMTP_PASSWORD": "password",
            "FROM_EMAIL": "noreply@example.com",
        }
        with patch.dict(os.environ, env):
            errors = production_env_errors()
            assert any("DEMO_MODE" in e for e in errors)

    def test_wg_mock_mode_must_be_false_in_production(self):
        from cryptography.fernet import Fernet
        valid_key = Fernet.generate_key().decode()
        env = {
            "ENVIRONMENT": "production",
            "AUTH_ENCRYPTION_KEY": valid_key,
            "WG_ENCRYPTION_KEY": valid_key,
            "DEMO_MODE": "false",
            "WG_MOCK_MODE": "true",
            "EMAIL_PROVIDER": "smtp",
            "SMTP_HOST": "smtp.example.com",
            "SMTP_PORT": "587",
            "SMTP_USER": "user@example.com",
            "SMTP_PASSWORD": "password",
            "FROM_EMAIL": "noreply@example.com",
        }
        with patch.dict(os.environ, env):
            errors = production_env_errors()
            assert any("WG_MOCK_MODE" in e for e in errors)

    def test_no_errors_when_fully_configured(self):
        from cryptography.fernet import Fernet
        valid_key = Fernet.generate_key().decode()
        env = {
            "ENVIRONMENT": "production",
            "AUTH_ENCRYPTION_KEY": valid_key,
            "WG_ENCRYPTION_KEY": valid_key,
            "DEMO_MODE": "false",
            "WG_MOCK_MODE": "false",
            "EMAIL_PROVIDER": "smtp",
            "SMTP_HOST": "smtp.example.com",
            "SMTP_PORT": "587",
            "SMTP_USER": "user@example.com",
            "SMTP_PASSWORD": "password",
            "FROM_EMAIL": "noreply@example.com",
        }
        with patch.dict(os.environ, env):
            errors = production_env_errors()
            assert errors == []
