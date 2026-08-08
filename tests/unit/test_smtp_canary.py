from pathlib import Path
import sys

import pytest

from scripts import smtp_canary


class FakeEmailService:
    send_count = 0

    def __init__(self):
        self.config = {
            "provider": "smtp",
            "enabled": True,
            "missing": [],
            "smtp_host": "smtp.example.test",
            "from_email": "sender@example.test",
        }

    def config_status(self):
        return self.config

    def send_email(self, **kwargs):
        FakeEmailService.send_count += 1
        assert kwargs["subject"] == smtp_canary.CANARY_SUBJECT
        assert kwargs["to_email"] == "canary@example.test"
        return True


class MissingEmailService(FakeEmailService):
    def config_status(self):
        return {
            "provider": "smtp",
            "enabled": False,
            "missing": ["SMTP_PASSWORD"],
            "smtp_host": "smtp.example.test",
            "from_email": "sender@example.test",
        }


class WrongProviderEmailService(FakeEmailService):
    def config_status(self):
        return {
            "provider": "sendgrid",
            "enabled": False,
            "missing": ["SENDGRID_API_KEY"],
        }


class FailingEmailService(FakeEmailService):
    def send_email(self, **_kwargs):
        FakeEmailService.send_count += 1
        return False


class RaisingEmailService(FakeEmailService):
    def send_email(self, **_kwargs):
        FakeEmailService.send_count += 1
        raise RuntimeError("SMTP password and provider response must not leak")


def test_check_only_never_sends(monkeypatch, tmp_path: Path):
    FakeEmailService.send_count = 0
    monkeypatch.setattr(smtp_canary, "_load_email_service", lambda: FakeEmailService)
    result, evidence = smtp_canary.check_configuration(evidence_dir=tmp_path)
    assert result == "PASS_SMTP_CONFIGURATION_ONLY"
    assert FakeEmailService.send_count == 0
    assert evidence.exists()
    assert "smtp.example.test" not in evidence.read_text(encoding="utf-8")


def test_send_canary_sends_exactly_one_message(monkeypatch, tmp_path: Path):
    FakeEmailService.send_count = 0
    monkeypatch.setattr(smtp_canary, "_load_email_service", lambda: FakeEmailService)
    result, evidence = smtp_canary.send_canary(
        recipient="canary@example.test",
        evidence_dir=tmp_path,
    )
    assert result == "PASS_SMTP_SUBMISSION_ACCEPTED"
    assert FakeEmailService.send_count == 1
    contents = evidence.read_text(encoding="utf-8")
    assert '"send_attempted": true' in contents
    assert "canary@example.test" not in contents


def test_invalid_recipient_is_rejected(monkeypatch, tmp_path: Path):
    monkeypatch.setattr(smtp_canary, "_load_email_service", lambda: FakeEmailService)
    with pytest.raises(smtp_canary.SmtpCanaryError):
        smtp_canary.send_canary(
            recipient="canary@example.test,other@example.test",
            evidence_dir=tmp_path,
        )


def test_check_only_reports_missing_variable_names_without_sending(monkeypatch, tmp_path: Path):
    FakeEmailService.send_count = 0
    monkeypatch.setattr(smtp_canary, "_load_email_service", lambda: MissingEmailService)
    result, evidence = smtp_canary.check_configuration(evidence_dir=tmp_path)
    assert result == "BLOCKED_SMTP_CONFIGURATION_MISSING"
    assert FakeEmailService.send_count == 0
    assert evidence.read_text(encoding="utf-8").find("SMTP_PASSWORD") >= 0
    assert "smtp.example.test" not in evidence.read_text(encoding="utf-8")


def test_wrong_provider_is_blocked(monkeypatch, tmp_path: Path):
    monkeypatch.setattr(smtp_canary, "_load_email_service", lambda: WrongProviderEmailService)
    result, _evidence = smtp_canary.check_configuration(evidence_dir=tmp_path)
    assert result == "BLOCKED_SMTP_PROVIDER_NOT_SELECTED"


def test_missing_email_dependency_is_a_blocker_without_sending(monkeypatch, tmp_path: Path):
    def missing_dependency():
        raise ModuleNotFoundError("python-dotenv is not installed", name="dotenv")

    monkeypatch.setattr(smtp_canary, "_load_email_service", missing_dependency)
    result, evidence = smtp_canary.check_configuration(evidence_dir=tmp_path)
    assert result == "BLOCKED_SMTP_DEPENDENCY_MISSING"
    assert '"send_attempted": false' in evidence.read_text(encoding="utf-8")


def test_provider_failure_is_not_reported_as_delivery(monkeypatch, tmp_path: Path):
    monkeypatch.setattr(smtp_canary, "_load_email_service", lambda: FailingEmailService)
    result, evidence = smtp_canary.send_canary(
        recipient="canary@example.test",
        evidence_dir=tmp_path,
    )
    assert result == "FAIL_SMTP_SUBMISSION"
    contents = evidence.read_text(encoding="utf-8")
    assert '"submission_accepted": false' in contents
    assert '"send_attempted": true' in contents
    assert "canary@example.test" not in contents


def test_provider_exception_is_redacted_and_returns_failure(monkeypatch, tmp_path: Path):
    FakeEmailService.send_count = 0
    monkeypatch.setattr(smtp_canary, "_load_email_service", lambda: RaisingEmailService)
    result, evidence = smtp_canary.send_canary(
        recipient="canary@example.test",
        evidence_dir=tmp_path,
    )
    assert result == "FAIL_SMTP_SUBMISSION"
    assert FakeEmailService.send_count == 1
    contents = evidence.read_text(encoding="utf-8")
    assert "SMTP password" not in contents
    assert '"send_attempted": true' in contents
    assert "canary@example.test" not in contents


def test_direct_send_mode_is_refused(monkeypatch, tmp_path: Path):
    monkeypatch.setattr(
        sys,
        "argv",
        [
            "smtp_canary.py",
            "--mode",
            "send",
            "--recipient",
            "canary@example.test",
            "--evidence-dir",
            str(tmp_path),
        ],
    )
    assert smtp_canary.main() == 2
