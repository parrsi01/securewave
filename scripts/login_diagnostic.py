#!/usr/bin/env python3
"""Run one redacted SecureWave real-account login diagnostic.

The diagnostic deliberately uses the existing-account login contract.  It does
not register accounts, verify email, disable 2FA, send email, or retry a
password.  All evidence is written outside the repository and contains only
status classifications.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import socket
import ssl
import sys
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Mapping
from urllib.parse import urlsplit, urlunsplit

try:  # Support both direct CLI execution and package-based tests.
    from cli_operation_common import (
        PacketValidationError,
        ensure_external_path,
        fingerprint_api_base,
        is_placeholder,
        validate_target_reference,
        write_json_evidence,
    )
except ModuleNotFoundError:  # pragma: no cover - import mode depends on invocation
    from scripts.cli_operation_common import (
        PacketValidationError,
        ensure_external_path,
        fingerprint_api_base,
        is_placeholder,
        validate_target_reference,
        write_json_evidence,
    )


ROOT = Path(__file__).resolve().parents[1]
_APP_CONSTANTS_PATH = ROOT / "securewave_app/lib/core/constants/app_constants.dart"
_FLUTTER_ENV_TEMPLATE_PATH = ROOT / ".env.example.flutter"


class DiagnosticInputError(ValueError):
    """Raised when a required diagnostic input is missing or unsafe."""


def _repository_default_api_fingerprints() -> set[str]:
    """Return repository-defined non-target API fingerprints only."""

    try:
        source = _APP_CONSTANTS_PATH.read_text(encoding="utf-8")
    except OSError as exc:
        raise DiagnosticInputError(
            "repository API fallback could not be inspected"
        ) from exc
    marker = re.search(
        r"baseUrlFallback\s*=\s*['\"]([^'\"]+)['\"]",
        source,
    )
    if not marker:
        raise DiagnosticInputError("repository API fallback is not defined")
    fingerprints = {fingerprint_api_base(marker.group(1))}
    try:
        template = _FLUTTER_ENV_TEMPLATE_PATH.read_text(encoding="utf-8")
    except OSError:
        template = ""
    template_match = re.search(
        r"^SECUREWAVE_API_BASE_URL=(\S+)$",
        template,
        flags=re.MULTILINE,
    )
    if template_match:
        fingerprints.add(fingerprint_api_base(template_match.group(1)))
    return fingerprints


@dataclass
class HttpResult:
    status: int | None
    body: Mapping[str, Any] | None
    category: str
    elapsed_ms: int


def normalize_api_base(value: str) -> str:
    if not value or is_placeholder(value):
        raise DiagnosticInputError("SECUREWAVE_API_BASE_URL is required")
    parsed = urlsplit(value.strip())
    if parsed.scheme.lower() != "https":
        raise DiagnosticInputError("SECUREWAVE_API_BASE_URL must use HTTPS")
    if not parsed.hostname or parsed.username or parsed.password:
        raise DiagnosticInputError("SECUREWAVE_API_BASE_URL must contain a host without credentials")
    if parsed.query or parsed.fragment:
        raise DiagnosticInputError("SECUREWAVE_API_BASE_URL must not contain query or fragment data")
    host = parsed.hostname.lower()
    if host in {"localhost", "::1", "0.0.0.0", "127.0.0.1"} or host.startswith("127."):
        raise DiagnosticInputError("SECUREWAVE_API_BASE_URL must identify a non-local target")
    path = parsed.path.rstrip("/") or "/api"
    if path != "/api" and not path.endswith("/api"):
        raise DiagnosticInputError("SECUREWAVE_API_BASE_URL must identify the backend /api path")
    normalized = urlunsplit(("https", parsed.netloc, path, "", ""))
    if fingerprint_api_base(normalized) in _repository_default_api_fingerprints():
        raise DiagnosticInputError(
            "SECUREWAVE_API_BASE_URL must be an explicitly authorized non-default target"
        )
    return normalized


def _body_mapping(raw: bytes) -> Mapping[str, Any] | None:
    if not raw:
        return {}
    try:
        value = json.loads(raw.decode("utf-8", errors="replace"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        return None
    return value if isinstance(value, dict) else None


def _body_text(body: Mapping[str, Any] | None) -> str:
    if not body:
        return ""
    values: list[str] = []
    for key in ("detail", "message", "error"):
        value = body.get(key)
        if isinstance(value, Mapping):
            values.extend(str(item) for item in value.values())
        elif value is not None:
            values.append(str(value))
    return " ".join(values).lower()


def classify_response(status: int | None, body: Mapping[str, Any] | None, *, operation: str) -> str:
    if status is None:
        return "BLOCKED_EXTERNAL_CONNECTIVITY"
    if 200 <= status < 300 and body is None:
        return "UNKNOWN_RESPONSE_CONTRACT"
    if status == 404:
        return "FAIL_ENDPOINT_CONTRACT"
    if status == 422:
        return "FAIL_REQUEST_CONTRACT"
    text = _body_text(body)
    if operation == "email_health" and status == 503:
        return "BLOCKED_SMTP_CONFIGURATION_MISSING"
    if operation == "login":
        if isinstance(body, Mapping) and body.get("requires_2fa") is True:
            return "BLOCKED_2FA_REQUIRED"
        if status == 403 and ("verify" in text or "email" in text):
            return "BLOCKED_EMAIL_VERIFICATION_REQUIRED"
        if status == 423:
            return "BLOCKED_ACCOUNT_LOCKED"
        if status == 429:
            return "BLOCKED_RATE_LIMITED"
        if status == 403 and any(
            marker in text for marker in ("2fa", "two-factor", "two factor", "totp")
        ):
            return "BLOCKED_2FA_REQUIRED"
        if status == 401 and any(
            marker in text for marker in ("2fa", "two-factor", "two factor", "totp")
        ):
            return "BLOCKED_2FA_REQUIRED"
        if status == 401:
            return "FAIL_INVALID_CREDENTIALS"
    if status >= 500:
        return "FAIL_REMOTE_SERVICE"
    if status == 429:
        return "BLOCKED_RATE_LIMITED"
    if status == 423:
        return "BLOCKED_ACCOUNT_LOCKED"
    if status == 401:
        return "FAIL_INVALID_CREDENTIALS"
    if status < 200 or status >= 300:
        return "UNKNOWN_RESPONSE_CONTRACT"
    return "PASS"


def _network_failure_category(error: BaseException) -> str:
    """Classify transport failures without exposing exception details."""

    if isinstance(error, (TimeoutError, socket.timeout)):
        return "BLOCKED_EXTERNAL_CONNECTIVITY"
    if isinstance(error, ssl.SSLError):
        return "BLOCKED_DNS_OR_TLS"
    if isinstance(error, urllib.error.URLError):
        reason = error.reason
        if isinstance(reason, (socket.gaierror, ssl.SSLError)):
            return "BLOCKED_DNS_OR_TLS"
        return "BLOCKED_EXTERNAL_CONNECTIVITY"
    return "BLOCKED_EXTERNAL_CONNECTIVITY"


def request_json(
    api_base: str,
    path: str,
    *,
    method: str = "GET",
    payload: Mapping[str, Any] | None = None,
    access_token: str | None = None,
    timeout: int = 20,
) -> HttpResult:
    url = f"{api_base.rstrip('/')}/{path.lstrip('/')}"
    headers = {"Accept": "application/json"}
    data: bytes | None = None
    if payload is not None:
        headers["Content-Type"] = "application/json"
        data = json.dumps(payload, separators=(",", ":")).encode("utf-8")
    if access_token:
        headers["Authorization"] = f"Bearer {access_token}"

    request = urllib.request.Request(url, data=data, headers=headers, method=method)
    started = time.monotonic()
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            body = _body_mapping(response.read())
            status = int(response.status)
            return HttpResult(
                status=status,
                body=body,
                category=classify_response(status, body, operation="request"),
                elapsed_ms=int((time.monotonic() - started) * 1000),
            )
    except urllib.error.HTTPError as error:
        body = _body_mapping(error.read())
        return HttpResult(
            status=int(error.code),
            body=body,
            category=classify_response(int(error.code), body, operation="request"),
            elapsed_ms=int((time.monotonic() - started) * 1000),
        )
    except (urllib.error.URLError, TimeoutError, socket.timeout, ssl.SSLError, OSError) as error:
        return HttpResult(
            status=None,
            body=None,
            category=_network_failure_category(error),
            elapsed_ms=int((time.monotonic() - started) * 1000),
        )


def _check_record(name: str, result: HttpResult, *, operation: str = "request") -> dict[str, Any]:
    return {
        "name": name,
        "http_status": result.status,
        "category": classify_response(result.status, result.body, operation=operation),
        "elapsed_ms": result.elapsed_ms,
    }


def run_diagnostic(
    *,
    api_base_url: str,
    email: str,
    password: str,
    environment: str,
    target_ref: str,
    evidence_dir: Path,
) -> tuple[str, Path]:
    api_base = normalize_api_base(api_base_url)
    if not email or is_placeholder(email) or not password:
        raise DiagnosticInputError("diagnostic account credentials are required")
    environment = environment.strip().lower()
    if environment not in {"staging", "production"}:
        raise DiagnosticInputError("environment must be staging or production")
    try:
        validate_target_reference(target_ref)
        evidence_dir = ensure_external_path(str(evidence_dir), ROOT, "evidence_dir")
    except PacketValidationError as exc:
        raise DiagnosticInputError(str(exc)) from exc

    checks: list[dict[str, Any]] = []
    overall = "PASS_LOGIN"
    token = ""

    health = request_json(api_base, "/health")
    checks.append(_check_record("health", health))
    ready = request_json(api_base, "/ready")
    checks.append(_check_record("ready", ready))
    email_health = request_json(api_base, "/health/email")
    checks.append(_check_record("email_health_config_only", email_health, operation="email_health"))

    login = request_json(
        api_base,
        "/auth/login",
        method="POST",
        payload={"email": email, "password": password},
    )
    # The request has returned; do not deliberately retain the supplied
    # account values while the authenticated checks run.
    email = ""
    password = ""
    login_category = classify_response(login.status, login.body, operation="login")
    checks.append(
        {
            "name": "login",
            "http_status": login.status,
            "category": login_category,
            "elapsed_ms": login.elapsed_ms,
        }
    )

    authenticated_user: dict[str, Any] | None = None
    access_token_observed = False
    authenticated_result: HttpResult | None = None
    plan_result: HttpResult | None = None
    try:
        if login.status == 200 and isinstance(login.body, Mapping):
            if login.body.get("requires_2fa") is True:
                overall = "BLOCKED_2FA_REQUIRED"
            else:
                candidate = login.body.get("access_token")
                if isinstance(candidate, str) and candidate:
                    access_token_observed = True
                    token = candidate
                    me = request_json(api_base, "/auth/me", access_token=token)
                    authenticated_result = me
                    checks.append(_check_record("authenticated_user", me))
                    if me.status == 200 and isinstance(me.body, Mapping):
                        authenticated_user = {
                            "response_received": True,
                            "email_verified": bool(me.body.get("email_verified")),
                            "has_2fa": bool(me.body.get("has_2fa")),
                        }
                        plan = request_json(api_base, "/user/plan", access_token=token)
                        plan_result = plan
                        checks.append(_check_record("authenticated_plan_optional", plan))
                        if plan.status not in {200, 404}:
                            checks.append(
                                {
                                    "name": "authenticated_plan_optional_contract",
                                    "http_status": plan.status,
                                    "category": "UNKNOWN_RESPONSE_CONTRACT",
                                    "elapsed_ms": plan.elapsed_ms,
                                }
                            )
                        overall = "PASS_LOGIN"
                    else:
                        overall = "FAIL_REMOTE_SERVICE" if me.status and me.status >= 500 else "UNKNOWN_RESPONSE_CONTRACT"
                else:
                    overall = "UNKNOWN_RESPONSE_CONTRACT"
        else:
            overall = login_category
    finally:
        # Python cannot guarantee memory zeroization, but dropping these
        # references prevents the diagnostic from retaining them deliberately.
        token = ""
        email = ""
        password = ""
        for result in (login, authenticated_result, plan_result):
            if result is not None and isinstance(result.body, dict):
                result.body.clear()

    # Health responses are not written to evidence beyond their status and
    # category.  Drop their parsed bodies as well so provider/target details
    # are not retained by the diagnostic after classification.
    for result in (health, ready, email_health):
        if isinstance(result.body, dict):
            result.body.clear()

    evidence = {
        "schema_version": 1,
        "result": overall,
        "environment": environment,
        "target_reference_present": True,
        "api_base_fingerprint": fingerprint_api_base(api_base),
        "account_present": True,
        "checks": checks,
        "access_token_observed": access_token_observed,
        "authenticated_user": authenticated_user,
        "email_health_note": "configuration status only; no SMTP send was attempted",
        "secrets_note": "password and tokens were not written to evidence",
    }
    destination = write_json_evidence(evidence_dir, "login-diagnostic.json", evidence)
    return overall, destination


def _exit_code(result: str) -> int:
    if result == "PASS_LOGIN":
        return 0
    if result.startswith("BLOCKED_"):
        return 2
    if result.startswith("FAIL_"):
        return 3
    return 4


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--environment", required=True)
    parser.add_argument("--target-ref", required=True)
    parser.add_argument("--evidence-dir", required=True, type=Path)
    args = parser.parse_args()

    if args.environment.strip().lower() == "production":
        print(
            "LOGIN_DIAGNOSTIC_RESULT=BLOCKED_PRODUCTION_REQUIRES_CONTROLLER_APPROVAL",
            file=sys.stderr,
        )
        print("AUTOMATION_RESULT=BLOCKED_BEFORE_SMTP", file=sys.stderr)
        return 2

    api_base = os.environ.get("SECUREWAVE_API_BASE_URL", "")
    email = os.environ.get("SECUREWAVE_DIAGNOSTIC_EMAIL", "")
    password = os.environ.get("SECUREWAVE_DIAGNOSTIC_PASSWORD", "")
    try:
        result, destination = run_diagnostic(
            api_base_url=api_base,
            email=email,
            password=password,
            environment=args.environment,
            target_ref=args.target_ref,
            evidence_dir=args.evidence_dir,
        )
    except DiagnosticInputError as exc:
        print(f"LOGIN_DIAGNOSTIC_RESULT=BLOCKED_INPUT_MISSING:{exc}", file=sys.stderr)
        print("AUTOMATION_RESULT=BLOCKED_BEFORE_SMTP", file=sys.stderr)
        return 2
    except Exception as exc:  # pragma: no cover - defensive CLI boundary
        print(f"LOGIN_DIAGNOSTIC_RESULT=UNKNOWN:{type(exc).__name__}", file=sys.stderr)
        print("AUTOMATION_RESULT=UNKNOWN", file=sys.stderr)
        return 4

    print(f"LOGIN_DIAGNOSTIC_RESULT={result}")
    print(f"LOGIN_DIAGNOSTIC_EVIDENCE={destination}")
    print(f"AUTOMATION_RESULT={'READY_FOR_PHASE_0_REVIEW' if result == 'PASS_LOGIN' else 'BLOCKED_BEFORE_SMTP' if result.startswith('BLOCKED_') else 'FAIL' if result.startswith('FAIL_') else 'UNKNOWN'}")
    return _exit_code(result)


if __name__ == "__main__":
    sys.exit(main())
