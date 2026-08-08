from pathlib import Path
import socket
import ssl
import sys
import urllib.error

import pytest

from scripts import login_diagnostic


def _result(status, body=None, category="PASS"):
    return login_diagnostic.HttpResult(
        status=status,
        body=body,
        category=category,
        elapsed_ms=1,
    )


def test_normalize_api_base_requires_explicit_non_local_https():
    with pytest.raises(login_diagnostic.DiagnosticInputError):
        login_diagnostic.normalize_api_base("")
    with pytest.raises(login_diagnostic.DiagnosticInputError):
        login_diagnostic.normalize_api_base("http://staging.example.test/api")
    with pytest.raises(login_diagnostic.DiagnosticInputError):
        login_diagnostic.normalize_api_base("https://localhost/api")
    with pytest.raises(login_diagnostic.DiagnosticInputError):
        login_diagnostic.normalize_api_base("https://api.securewaveapp.com/api")
    with pytest.raises(login_diagnostic.DiagnosticInputError):
        login_diagnostic.normalize_api_base("https://api.your-domain.com/api")


def test_run_diagnostic_rejects_missing_account_credentials(tmp_path: Path):
    with pytest.raises(login_diagnostic.DiagnosticInputError):
        login_diagnostic.run_diagnostic(
            api_base_url="https://staging.example.test/api",
            email="",
            password="",
            environment="staging",
            target_ref="staging-fleet-01",
            evidence_dir=tmp_path,
        )


def test_direct_production_diagnostic_requires_controller(monkeypatch, tmp_path: Path):
    monkeypatch.setattr(
        sys,
        "argv",
        [
            "login_diagnostic.py",
            "--environment",
            "production",
            "--target-ref",
            "production-fleet-01",
            "--evidence-dir",
            str(tmp_path),
        ],
    )
    assert login_diagnostic.main() == 2


@pytest.mark.parametrize(
    ("status", "body", "expected"),
    [
        (401, {"detail": "Invalid credentials"}, "FAIL_INVALID_CREDENTIALS"),
        (403, {"detail": "Please verify your email before logging in"}, "BLOCKED_EMAIL_VERIFICATION_REQUIRED"),
        (423, {"detail": "locked"}, "BLOCKED_ACCOUNT_LOCKED"),
        (429, {"detail": "rate limit"}, "BLOCKED_RATE_LIMITED"),
        (200, {"requires_2fa": True}, "BLOCKED_2FA_REQUIRED"),
        (403, {"detail": "Two-factor authentication required"}, "BLOCKED_2FA_REQUIRED"),
        (500, {"detail": "backend failure"}, "FAIL_REMOTE_SERVICE"),
        (404, {"detail": "Not found"}, "FAIL_ENDPOINT_CONTRACT"),
        (422, {"detail": [{"loc": ["body"], "msg": "field required"}]}, "FAIL_REQUEST_CONTRACT"),
    ],
)
def test_login_classification_is_fail_closed(status, body, expected):
    assert login_diagnostic.classify_response(status, body, operation="login") == expected


def test_run_diagnostic_writes_redacted_evidence(monkeypatch, tmp_path: Path):
    responses = {
        "/health": _result(200, {"status": "ok"}),
        "/ready": _result(200, {"status": "ready"}),
        "/health/email": _result(503, {"status": "not_configured", "email": {"smtp_host": "smtp.example.test"}}),
        "/auth/login": _result(200, {"access_token": "access-token-that-must-not-be-written", "refresh_token": "refresh-token"}),
        "/auth/me": _result(200, {"email": "user@example.test", "email_verified": True, "has_2fa": False}),
        "/user/plan": _result(200, {"plan": "basic"}),
    }

    def fake_request(api_base, path, **_kwargs):
        return responses[path]

    monkeypatch.setattr(login_diagnostic, "request_json", fake_request)
    result, evidence_path = login_diagnostic.run_diagnostic(
        api_base_url="https://staging.example.test/api",
        email="user@example.test",
        password="password-that-must-not-be-written",
        environment="staging",
        target_ref="staging-fleet-01",
        evidence_dir=tmp_path,
    )

    assert result == "PASS_LOGIN"
    evidence = evidence_path.read_text(encoding="utf-8")
    assert "password-that-must-not-be-written" not in evidence
    assert "access-token-that-must-not-be-written" not in evidence
    assert "user@example.test" not in evidence
    assert "staging.example.test" not in evidence
    assert '"access_token_observed": true' in evidence


def test_malformed_success_body_is_unknown_response_contract(monkeypatch):
    class Response:
        status = 200

        def __enter__(self):
            return self

        def __exit__(self, *_args):
            return False

        def read(self):
            return b"not-json"

    monkeypatch.setattr(login_diagnostic.urllib.request, "urlopen", lambda *_args, **_kwargs: Response())
    result = login_diagnostic.request_json("https://staging.example.test/api", "/health")
    assert result.status == 200
    assert result.category == "UNKNOWN_RESPONSE_CONTRACT"


def test_dns_or_tls_failure_is_redacted_and_blocked(monkeypatch):
    def fail(*_args, **_kwargs):
        raise urllib.error.URLError(socket.gaierror("private-hostname-and-secret-details"))

    monkeypatch.setattr(login_diagnostic.urllib.request, "urlopen", fail)
    result = login_diagnostic.request_json("https://staging.example.test/api", "/health")
    assert result.status is None
    assert result.category == "BLOCKED_DNS_OR_TLS"


def test_tls_certificate_failure_is_redacted_and_blocked(monkeypatch):
    def fail(*_args, **_kwargs):
        raise ssl.SSLError("certificate details must not be reported")

    monkeypatch.setattr(login_diagnostic.urllib.request, "urlopen", fail)
    result = login_diagnostic.request_json("https://staging.example.test/api", "/health")
    assert result.status is None
    assert result.category == "BLOCKED_DNS_OR_TLS"


def test_timeout_is_classified_as_external_connectivity(monkeypatch):
    def fail(*_args, **_kwargs):
        raise TimeoutError("timeout details must not be reported")

    monkeypatch.setattr(login_diagnostic.urllib.request, "urlopen", fail)
    result = login_diagnostic.request_json("https://staging.example.test/api", "/health")
    assert result.status is None
    assert result.category == "BLOCKED_EXTERNAL_CONNECTIVITY"


def test_authenticated_failure_is_remote_failure(monkeypatch, tmp_path: Path):
    responses = {
        "/health": _result(200, {"status": "ok"}),
        "/ready": _result(200, {"status": "ready"}),
        "/health/email": _result(200, {"status": "configured"}),
        "/auth/login": _result(200, {"access_token": "token"}),
        "/auth/me": _result(503, {"detail": "backend failure"}),
    }

    monkeypatch.setattr(
        login_diagnostic,
        "request_json",
        lambda _api_base, path, **_kwargs: responses[path],
    )
    result, evidence_path = login_diagnostic.run_diagnostic(
        api_base_url="https://staging.example.test/api",
        email="user@example.test",
        password="password",
        environment="staging",
        target_ref="staging-fleet-01",
        evidence_dir=tmp_path,
    )
    assert result == "FAIL_REMOTE_SERVICE"
    assert '"category": "FAIL_REMOTE_SERVICE"' in evidence_path.read_text(encoding="utf-8")
