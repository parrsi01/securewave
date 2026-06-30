"""
Tests for email service configuration.

Validates that EmailService correctly reports configuration status
without actually sending emails.
"""

import os
import pytest
from unittest.mock import patch

from models.email_log import EmailLog


class TestEmailServiceConfigStatus:
    """Test EmailService.config_status() method."""

    def test_smtp_disabled_when_not_configured(self):
        env = {
            "EMAIL_PROVIDER": "smtp",
            "TESTING": "true",
        }
        with patch.dict(os.environ, env, clear=False):
            os.environ.pop("SMTP_USER", None)
            os.environ.pop("SMTP_PASSWORD", None)
            os.environ.pop("FROM_EMAIL", None)

            import importlib
            import services.email_service as email_module
            importlib.reload(email_module)

            service = email_module.EmailService()
            status = service.config_status()

            assert status["provider"] == "smtp"
            # Should have missing fields
            assert len(status["missing"]) > 0

    def test_smtp_enabled_when_configured(self):
        env = {
            "EMAIL_PROVIDER": "smtp",
            "SMTP_HOST": "smtp.example.com",
            "SMTP_PORT": "587",
            "SMTP_USER": "user@example.com",
            "SMTP_PASSWORD": "password",
            "FROM_EMAIL": "noreply@example.com",
            "FROM_NAME": "SecureWave",
            "APP_URL": "https://securewave.app",
        }
        with patch.dict(os.environ, env):
            # Need to reload the module to pick up new env vars
            import importlib
            import services.email_service as email_module
            importlib.reload(email_module)

            service = email_module.EmailService()
            status = service.config_status()

            assert status["provider"] == "smtp"
            assert status["missing"] == []
            assert status["from_email"] == "noreply@example.com"

    def test_config_status_does_not_send_email(self):
        """config_status must never trigger actual email sending."""
        env = {
            "EMAIL_PROVIDER": "smtp",
            "SMTP_HOST": "smtp.example.com",
            "SMTP_PORT": "587",
            "SMTP_USER": "user@example.com",
            "SMTP_PASSWORD": "password",
            "FROM_EMAIL": "noreply@example.com",
            "APP_URL": "https://securewave.app",
        }
        with patch.dict(os.environ, env):
            import importlib
            import services.email_service as email_module
            importlib.reload(email_module)

            with patch.object(email_module.smtplib, "SMTP") as mock_smtp:
                service = email_module.EmailService()
                status = service.config_status()

                # SMTP should NOT have been called
                mock_smtp.assert_not_called()

    def test_sendgrid_config_status(self):
        env = {
            "EMAIL_PROVIDER": "sendgrid",
            "SENDGRID_API_KEY": "SG.test-key",
            "FROM_EMAIL": "noreply@example.com",
            "APP_URL": "https://securewave.app",
        }
        with patch.dict(os.environ, env):
            import importlib
            import services.email_service as email_module
            importlib.reload(email_module)

            service = email_module.EmailService()
            status = service.config_status()

            assert status["provider"] == "sendgrid"
            # SendGrid should be enabled with API key + FROM_EMAIL
            assert status["enabled"] is True

    def test_ses_config_status(self):
        env = {
            "EMAIL_PROVIDER": "ses",
            "FROM_EMAIL": "noreply@example.com",
            "AWS_SES_REGION": "us-east-1",
            "APP_URL": "https://securewave.app",
        }
        with patch.dict(os.environ, env):
            import importlib
            import services.email_service as email_module
            importlib.reload(email_module)

            service = email_module.EmailService()
            status = service.config_status()

            assert status["provider"] == "ses"


class TestEmailServiceProviderReady:
    """Test _provider_ready() method."""

    def test_smtp_not_ready_without_password(self):
        env = {
            "EMAIL_PROVIDER": "smtp",
            "SMTP_HOST": "smtp.example.com",
            "SMTP_PORT": "587",
            "SMTP_USER": "user@example.com",
            "FROM_EMAIL": "noreply@example.com",
            "APP_URL": "https://securewave.app",
        }
        with patch.dict(os.environ, env, clear=True):
            os.environ.pop("SMTP_PASSWORD", None)

            import importlib
            import services.email_service as email_module
            importlib.reload(email_module)

            service = email_module.EmailService()
            assert service.enabled is False

    def test_unknown_provider_not_ready(self):
        env = {"EMAIL_PROVIDER": "unknown_provider"}
        with patch.dict(os.environ, env, clear=True):
            import importlib
            import services.email_service as email_module
            importlib.reload(email_module)

            service = email_module.EmailService()
            assert service.enabled is False

    def test_smtp_not_ready_without_app_url(self):
        env = {
            "EMAIL_PROVIDER": "smtp",
            "SMTP_HOST": "smtp.example.com",
            "SMTP_PORT": "587",
            "SMTP_USER": "user@example.com",
            "SMTP_PASSWORD": "password",
            "FROM_EMAIL": "noreply@example.com",
        }
        with patch.dict(os.environ, env, clear=True):
            import importlib
            import services.email_service as email_module
            importlib.reload(email_module)

            service = email_module.EmailService()
            status = service.config_status()

            assert service.enabled is False
            assert "APP_URL" in status["missing"]


class TestEmailServiceDisabledBehavior:
    """Test behavior when email is disabled."""

    def test_send_email_returns_false_when_disabled(self):
        env = {"EMAIL_PROVIDER": "smtp"}
        with patch.dict(os.environ, env, clear=True):
            os.environ.pop("SMTP_USER", None)
            os.environ.pop("SMTP_PASSWORD", None)

            import importlib
            import services.email_service as email_module
            importlib.reload(email_module)

            service = email_module.EmailService()
            result = service.send_email(
                to_email="test@example.com",
                subject="Test",
                html_content="<p>Test</p>"
            )

            assert result is False

    def test_send_verification_email_returns_false_when_disabled(self):
        env = {"EMAIL_PROVIDER": "smtp"}
        with patch.dict(os.environ, env, clear=True):
            os.environ.pop("SMTP_USER", None)
            os.environ.pop("SMTP_PASSWORD", None)

            import importlib
            import services.email_service as email_module
            importlib.reload(email_module)

            service = email_module.EmailService()
            result = service.send_verification_email(
                to_email="test@example.com",
                verification_token="abc123"
            )

            assert result is False

    def test_disabled_send_logs_redacted_recipient(self, caplog):
        env = {"EMAIL_PROVIDER": "smtp"}
        with patch.dict(os.environ, env, clear=True):
            import importlib
            import services.email_service as email_module
            importlib.reload(email_module)

            service = email_module.EmailService()
            service.send_email(
                to_email="test@example.com",
                subject="Test",
                html_content="<p>Test</p>",
            )

            assert "test@example.com" not in caplog.text
            assert "t***@example.com" in caplog.text


def test_enhanced_email_log_uses_model_extra_data_mapping(db, monkeypatch):
    import services.enhanced_email_service as enhanced_email_module

    monkeypatch.setattr(enhanced_email_module, "FROM_EMAIL", "noreply@example.com")
    service = enhanced_email_module.EnhancedEmailService(db)

    service._log_email(
        to_email="recipient@example.com",
        subject="Billing notice",
        status="sent",
        template_name="billing_notice",
        category="billing",
        metadata={"invoice_id": "inv_test"},
    )

    log = db.query(EmailLog).first()
    assert log is not None
    assert log.extra_data == {"invoice_id": "inv_test"}
    assert "metadata" in EmailLog.__table__.c
