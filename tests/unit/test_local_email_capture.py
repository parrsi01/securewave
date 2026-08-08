import json
from pathlib import Path

import pytest

from services.local_email_capture import LocalEmailCaptureError, capture_email


def test_local_capture_requires_the_codex_local_environment(monkeypatch, tmp_path: Path):
    monkeypatch.setenv("ENVIRONMENT", "staging")
    monkeypatch.setenv("SECUREWAVE_LOCAL_EMAIL_EVIDENCE_DIR", str(tmp_path))

    with pytest.raises(LocalEmailCaptureError, match="codex-local"):
        capture_email(
            to_email="recipient@example.test",
            subject="Subject",
            html_content="<p>Body</p>",
        )


def test_local_capture_rejects_repository_evidence(monkeypatch, tmp_path: Path):
    repository_root = Path(__file__).resolve().parents[2]
    monkeypatch.setenv("ENVIRONMENT", "codex-local")
    monkeypatch.setenv(
        "SECUREWAVE_LOCAL_EMAIL_EVIDENCE_DIR",
        str(repository_root / "local-email-evidence-test"),
    )

    with pytest.raises(LocalEmailCaptureError, match="outside the repository"):
        capture_email(
            to_email="recipient@example.test",
            subject="Subject",
            html_content="<p>Body</p>",
        )


def test_local_capture_writes_only_redacted_evidence(monkeypatch, tmp_path: Path):
    monkeypatch.setenv("ENVIRONMENT", "codex-local")
    monkeypatch.setenv("SECUREWAVE_LOCAL_EMAIL_EVIDENCE_DIR", str(tmp_path))

    original_email = "recipient@example.test"
    original_url = "https://api.example.test/api/auth/verify-email?token=token-value"
    original_password = "password=secret-value"
    assert capture_email(
        to_email=original_email,
        subject="Verification",
        html_content=f'<a href="{original_url}">Verify</a>',
        text_content=f"{original_email} {original_url} {original_password}",
    )

    files = sorted(tmp_path.glob("email-*.json"))
    assert len(files) == 1
    payload = json.loads(files[0].read_text(encoding="utf-8"))
    evidence = json.dumps(payload, sort_keys=True)
    assert original_email not in evidence
    assert original_url not in evidence
    assert original_password not in evidence
    assert "[redacted-email]" in evidence
    assert "[redacted-url]" in evidence
    assert "token-value" not in evidence
