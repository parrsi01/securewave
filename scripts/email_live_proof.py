#!/usr/bin/env python3
"""API-driven live proof for SecureWave verification and reset email flows.

The script never reads an inbox or prints secrets. It drives the live API and
prompts for the verification/reset URLs or tokens delivered by the real email
provider.
"""

from __future__ import annotations

import argparse
import getpass
import json
import os
import secrets
import string
import sys
import time
from dataclasses import dataclass
from typing import Any, Optional
from urllib.error import HTTPError, URLError
from urllib.parse import parse_qs, urlparse
from urllib.request import Request, urlopen


DEFAULT_API_BASE = os.getenv("SECUREWAVE_API_BASE_URL", "http://127.0.0.1:8000/api")


class ApiError(RuntimeError):
    def __init__(self, status: int, body: str):
        self.status = status
        self.body = body
        super().__init__(f"HTTP {status}: {body}")


@dataclass
class StepResult:
    name: str
    status: str
    detail: str


def api_url(api_base: str, path: str) -> str:
    url = f"{api_base.rstrip('/')}/{path.lstrip('/')}"
    parsed = urlparse(url)
    if parsed.scheme not in {"http", "https"}:
        raise ValueError("API base URL must use http or https")
    return url


def extract_token(value: str) -> str:
    """Return token from a raw token or a URL containing ?token=..."""
    candidate = value.strip()
    parsed = urlparse(candidate)
    if parsed.query:
        token_values = parse_qs(parsed.query).get("token")
        if token_values and token_values[0]:
            return token_values[0]
    return candidate


def request_json(
    api_base: str,
    method: str,
    path: str,
    payload: Optional[dict[str, Any]] = None,
    token: Optional[str] = None,
    timeout: int = 20,
) -> dict[str, Any]:
    data = None
    headers = {"Accept": "application/json"}
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
        headers["Content-Type"] = "application/json"
    if token:
        headers["Authorization"] = f"Bearer {token}"

    request = Request(api_url(api_base, path), data=data, headers=headers, method=method)
    try:
        # api_url permits only http(s) before this network call is made.
        with urlopen(request, timeout=timeout) as response:  # nosec B310
            body = response.read().decode("utf-8")
    except HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise ApiError(exc.code, body) from exc
    except URLError as exc:
        raise RuntimeError(f"Failed to reach {api_url(api_base, path)}: {exc}") from exc

    if not body:
        return {}
    try:
        return json.loads(body)
    except json.JSONDecodeError:
        return {"raw": body}


def prompt_hidden(label: str) -> str:
    try:
        value = getpass.getpass(label)
    except (EOFError, KeyboardInterrupt) as exc:
        raise RuntimeError("interactive token/password input was not provided") from exc
    value = value.strip()
    if not value:
        raise RuntimeError("empty input is not valid")
    return value


def generated_password() -> str:
    alphabet = string.ascii_letters + string.digits
    suffix = "".join(secrets.choice(alphabet) for _ in range(18))
    return f"SecureWaveProof1!{suffix}"


def redacted_email(email: str) -> str:
    local, _, domain = email.partition("@")
    if not domain:
        return "<invalid-email>"
    return f"{local[:1]}***@{domain}"


def append_result(results: list[StepResult], name: str, status: str, detail: str) -> None:
    results.append(StepResult(name=name, status=status, detail=detail))
    print(f"[{status.upper()}] {name}: {detail}")


def run(args: argparse.Namespace) -> int:
    api_base = args.api_base.rstrip("/")
    email = args.email or os.getenv("SECUREWAVE_EMAIL_PROOF_EMAIL")
    password = args.password or os.getenv("SECUREWAVE_EMAIL_PROOF_PASSWORD")
    new_password = args.new_password or os.getenv("SECUREWAVE_EMAIL_PROOF_NEW_PASSWORD")
    results: list[StepResult] = []

    if not email:
        raise RuntimeError("set --email or SECUREWAVE_EMAIL_PROOF_EMAIL")
    if not password:
        password = prompt_hidden("Proof account password: ")
    if not new_password:
        if args.generate_new_password:
            new_password = generated_password()
        else:
            new_password = prompt_hidden("New password for reset proof: ")

    health = request_json(api_base, "GET", "/health/email", timeout=args.timeout)
    if health.get("status") != "ok":
        append_result(
            results,
            "email_health",
            "blocked",
            f"/health/email returned {health.get('status') or health}",
        )
        print(json.dumps({"status": "blocked", "steps": [r.__dict__ for r in results]}, indent=2))
        return 2
    append_result(results, "email_health", "passed", "email provider health is ok")

    registered = False
    if not args.skip_register:
        try:
            request_json(api_base, "POST", "/auth/register", {
                "email": email,
                "password": password,
                "password_confirm": password,
            }, timeout=args.timeout)
            registered = True
            append_result(results, "register", "passed", f"registered {redacted_email(email)}")
        except ApiError as exc:
            if exc.status == 400 and "already" in exc.body.lower():
                append_result(results, "register", "skipped", "account already exists")
            else:
                raise

    if registered and not args.skip_verify:
        verification_value = (
            args.verification_token
            or os.getenv("SECUREWAVE_EMAIL_PROOF_VERIFICATION_TOKEN")
            or prompt_hidden("Paste verification URL/token from email: ")
        )
        request_json(api_base, "POST", "/auth/verify-email", {
            "token": extract_token(verification_value),
        }, timeout=args.timeout)
        append_result(results, "verify_email", "passed", "verification token consumed")
    elif args.skip_verify:
        append_result(results, "verify_email", "skipped", "skipped by flag")
    else:
        append_result(
            results,
            "verify_email",
            "skipped",
            "no fresh registration token; use a new proof address to verify this step",
        )

    if not args.skip_reset:
        request_json(api_base, "POST", "/auth/password-reset/request", {
            "email": email,
        }, timeout=args.timeout)
        append_result(results, "password_reset_request", "passed", "reset request accepted")

        reset_value = (
            args.reset_token
            or os.getenv("SECUREWAVE_EMAIL_PROOF_RESET_TOKEN")
            or prompt_hidden("Paste password reset URL/token from email: ")
        )
        request_json(api_base, "POST", "/auth/password-reset/confirm", {
            "token": extract_token(reset_value),
            "new_password": new_password,
        }, timeout=args.timeout)
        append_result(results, "password_reset_confirm", "passed", "reset token consumed")

        login = request_json(api_base, "POST", "/auth/login", {
            "email": email,
            "password": new_password,
        }, timeout=args.timeout)
        access_token = login.get("access_token")
        if not access_token:
            raise RuntimeError("login after password reset did not return an access token")
        me = request_json(api_base, "GET", "/auth/me", token=access_token, timeout=args.timeout)
        if me.get("email", "").lower() != email.lower():
            raise RuntimeError("post-reset /auth/me did not return the proof account")
        append_result(results, "login_after_reset", "passed", "new password login succeeded")
    else:
        append_result(results, "password_reset", "skipped", "skipped by flag")

    print(json.dumps({
        "status": "passed",
        "api_base": api_base,
        "email": redacted_email(email),
        "timestamp": int(time.time()),
        "steps": [result.__dict__ for result in results],
    }, indent=2))
    return 0


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--api-base", default=DEFAULT_API_BASE)
    parser.add_argument("--email")
    parser.add_argument("--password")
    parser.add_argument("--new-password")
    parser.add_argument("--verification-token")
    parser.add_argument("--reset-token")
    parser.add_argument("--timeout", type=int, default=20)
    parser.add_argument("--skip-register", action="store_true")
    parser.add_argument("--skip-verify", action="store_true")
    parser.add_argument("--skip-reset", action="store_true")
    parser.add_argument("--generate-new-password", action="store_true")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    try:
        return run(parse_args(argv))
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
