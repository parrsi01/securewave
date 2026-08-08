from pathlib import Path
import sys
import types

import pytest

from scripts import sendgrid_canary


class FakeEmailService:
    send_count = 0

    def __init__(self):
        self.config = {
            "provider": "sendgrid",
            "enabled": True,
            "missing": [],
        }

    def config_status(self):
        return self.config

    def send_email(self, **kwargs):
        FakeEmailService.send_count += 1
        assert kwargs["subject"] == sendgrid_canary.CANARY_SUBJECT
        assert kwargs["to_email"] == "canary@example.test"
        return True


class MissingEmailService(FakeEmailService):
    def config_status(self):
        return {
            "provider": "sendgrid",
            "enabled": False,
            "missing": ["SENDGRID_API_KEY"],
        }


class WrongProviderEmailService(FakeEmailService):
    def config_status(self):
        return {
            "provider": "smtp",
            "enabled": False,
            "missing": ["SMTP_PASSWORD"],
        }


class FailingEmailService(FakeEmailService):
    def send_email(self, **_kwargs):
        FakeEmailService.send_count += 1
        return False


class RaisingEmailService(FakeEmailService):
    def send_email(self, **_kwargs):
        FakeEmailService.send_count += 1
        raise RuntimeError("SENDGRID_API_KEY=must-not-leak")


def _patch_fake_service(monkeypatch, service):
    monkeypatch.setattr(sendgrid_canary, "_sendgrid_dependency_available", lambda: True)
    monkeypatch.setattr(sendgrid_canary, "_load_email_service", lambda: service)
    monkeypatch.setenv("EMAIL_PROVIDER", "sendgrid")
    monkeypatch.setenv("SENDGRID_API_KEY", "SG.test-key")
    monkeypatch.setenv("FROM_EMAIL", "sender@example.test")


def test_check_only_never_sends_without_smtp(monkeypatch, tmp_path: Path):
    FakeEmailService.send_count = 0
    _patch_fake_service(monkeypatch, FakeEmailService)
    monkeypatch.delenv("SMTP_HOST", raising=False)
    monkeypatch.delenv("SMTP_PASSWORD", raising=False)

    result, evidence = sendgrid_canary.check_configuration(evidence_dir=tmp_path)

    assert result == "PASS_SENDGRID_CONFIGURATION_ONLY"
    assert FakeEmailService.send_count == 0
    contents = evidence.read_text(encoding="utf-8")
    assert '"send_attempted": false' in contents
    assert "canary@example.test" not in contents


def test_missing_sendgrid_configuration_is_blocked(monkeypatch, tmp_path: Path):
    FakeEmailService.send_count = 0
    _patch_fake_service(monkeypatch, MissingEmailService)

    result, evidence = sendgrid_canary.check_configuration(evidence_dir=tmp_path)

    assert result == "BLOCKED_SENDGRID_CONFIGURATION_MISSING"
    assert FakeEmailService.send_count == 0
    assert "SENDGRID_API_KEY" in evidence.read_text(encoding="utf-8")


def test_wrong_provider_is_blocked(monkeypatch, tmp_path: Path):
    _patch_fake_service(monkeypatch, WrongProviderEmailService)

    result, _evidence = sendgrid_canary.check_configuration(evidence_dir=tmp_path)

    assert result == "BLOCKED_SENDGRID_PROVIDER_NOT_SELECTED"


def test_missing_sendgrid_dependency_is_blocked(monkeypatch, tmp_path: Path):
    monkeypatch.setenv("EMAIL_PROVIDER", "sendgrid")
    monkeypatch.setenv("SENDGRID_API_KEY", "SG.test-key")
    monkeypatch.setenv("FROM_EMAIL", "sender@example.test")
    monkeypatch.setattr(sendgrid_canary, "_sendgrid_dependency_available", lambda: False)

    result, evidence = sendgrid_canary.check_configuration(evidence_dir=tmp_path)

    assert result == "BLOCKED_SENDGRID_DEPENDENCY_MISSING"
    assert '"send_attempted": false' in evidence.read_text(encoding="utf-8")


def test_sendgrid_requires_explicit_from_email(monkeypatch, tmp_path: Path):
    _patch_fake_service(monkeypatch, FakeEmailService)
    monkeypatch.delenv("FROM_EMAIL", raising=False)
    monkeypatch.setenv("SMTP_FROM_EMAIL", "legacy@example.test")

    result, evidence = sendgrid_canary.check_configuration(evidence_dir=tmp_path)

    assert result == "BLOCKED_SENDGRID_CONFIGURATION_MISSING"
    assert "FROM_EMAIL" in evidence.read_text(encoding="utf-8")


def test_send_canary_submits_exactly_one_message(monkeypatch, tmp_path: Path):
    FakeEmailService.send_count = 0
    _patch_fake_service(monkeypatch, FakeEmailService)

    result, evidence = sendgrid_canary.send_canary(
        recipient="canary@example.test",
        evidence_dir=tmp_path,
    )

    assert result == "PASS_SENDGRID_SUBMISSION_ACCEPTED"
    assert FakeEmailService.send_count == 1
    contents = evidence.read_text(encoding="utf-8")
    assert '"send_attempted": true' in contents
    assert '"submission_accepted": true' in contents
    assert "canary@example.test" not in contents


def test_sendgrid_provider_failure_is_not_reported_as_delivery(monkeypatch, tmp_path: Path):
    FakeEmailService.send_count = 0
    _patch_fake_service(monkeypatch, FailingEmailService)

    result, evidence = sendgrid_canary.send_canary(
        recipient="canary@example.test",
        evidence_dir=tmp_path,
    )

    assert result == "FAIL_SENDGRID_SUBMISSION"
    assert FakeEmailService.send_count == 1
    assert '"submission_accepted": false' in evidence.read_text(encoding="utf-8")


def test_sendgrid_provider_exception_is_redacted(monkeypatch, tmp_path: Path):
    FakeEmailService.send_count = 0
    _patch_fake_service(monkeypatch, RaisingEmailService)

    result, evidence = sendgrid_canary.send_canary(
        recipient="canary@example.test",
        evidence_dir=tmp_path,
    )

    assert result == "FAIL_SENDGRID_SUBMISSION"
    assert FakeEmailService.send_count == 1
    contents = evidence.read_text(encoding="utf-8")
    assert "SENDGRID_API_KEY" not in contents
    assert "must-not-leak" not in contents
    assert "canary@example.test" not in contents


def test_recipient_validation_rejects_multiple_recipients(tmp_path: Path):
    with pytest.raises(sendgrid_canary.SendGridCanaryError):
        sendgrid_canary.send_canary(
            recipient="canary@example.test,other@example.test",
            evidence_dir=tmp_path,
        )


def test_direct_send_mode_is_refused(monkeypatch, tmp_path: Path):
    monkeypatch.setattr(
        sys,
        "argv",
        [
            "sendgrid_canary.py",
            "--mode",
            "send",
            "--recipient",
            "canary@example.test",
            "--evidence-dir",
            str(tmp_path),
        ],
    )

    assert sendgrid_canary.main() == 2


def _install_fake_sendgrid(monkeypatch, status_code: int):
    sendgrid_module = types.ModuleType("sendgrid")
    helpers_module = types.ModuleType("sendgrid.helpers")
    mail_module = types.ModuleType("sendgrid.helpers.mail")

    class FakeClient:
        def __init__(self, api_key):
            assert api_key == "SG.runtime-only-key"

        def send(self, _mail):
            return types.SimpleNamespace(status_code=status_code)

    class FakeMail:
        def __init__(self, **_kwargs):
            pass

        def add_content(self, _content):
            pass

    class FakeValue:
        def __init__(self, *_args):
            pass

    sendgrid_module.SendGridAPIClient = FakeClient
    mail_module.Mail = FakeMail
    mail_module.Email = FakeValue
    mail_module.To = FakeValue
    mail_module.Content = FakeValue
    monkeypatch.setitem(sys.modules, "sendgrid", sendgrid_module)
    monkeypatch.setitem(sys.modules, "sendgrid.helpers", helpers_module)
    monkeypatch.setitem(sys.modules, "sendgrid.helpers.mail", mail_module)


@pytest.mark.parametrize(("status_code", "expected"), [(202, True), (500, False)])
def test_existing_email_service_uses_sendgrid_api_response(
    monkeypatch, status_code: int, expected: bool
):
    _install_fake_sendgrid(monkeypatch, status_code)
    monkeypatch.setenv("EMAIL_PROVIDER", "sendgrid")
    monkeypatch.setenv("SENDGRID_API_KEY", "SG.runtime-only-key")
    monkeypatch.setenv("FROM_EMAIL", "sender@example.test")

    import importlib
    import services.email_service as email_module

    email_module = importlib.reload(email_module)
    service = email_module.EmailService()

    assert service.send_email(
        to_email="recipient@example.test",
        subject="Subject",
        html_content="<p>Body</p>",
        text_content="Body",
    ) is expected


def test_production_runtime_declares_sendgrid_dependency_and_workflow_secret():
    root = Path(__file__).resolve().parents[2]
    production_requirements = (root / "requirements_production.txt").read_text(
        encoding="utf-8"
    )
    workflow = (root / ".github/workflows/flutter-release.yml").read_text(
        encoding="utf-8"
    )
    setup_script = (root / "scripts/setup_production_env.sh").read_text(
        encoding="utf-8"
    )

    assert "sendgrid==6.11.0" in production_requirements
    assert "EMAIL_PROVIDER: sendgrid" in workflow
    assert "SENDGRID_API_KEY: ${{ secrets.SENDGRID_API_KEY }}" in workflow
    assert "SMTP_PASSWORD: ${{ secrets.SMTP_PASSWORD }}" not in workflow
    assert 'print_export "SENDGRID_API_KEY"' in setup_script
