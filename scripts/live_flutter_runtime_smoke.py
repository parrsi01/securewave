#!/usr/bin/env python3
"""Run a redacted WireGuard-only control-plane smoke with an existing account."""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

try:
    from scripts import linux_app_vpn_tunnel_proof as certification
except ModuleNotFoundError:  # Direct execution from scripts/.
    import linux_app_vpn_tunnel_proof as certification


PROTOCOL = "wireguard"


def _redact_error_text(value: str, payload: dict | None) -> str:
    """Keep diagnostics useful without echoing credentials from a response."""
    redacted = value
    if payload:
        for key in ("email", "password"):
            secret = payload.get(key)
            if isinstance(secret, str) and secret:
                redacted = redacted.replace(secret, "[redacted]")
    return redacted[:240]


def _safe_error_body(error: urllib.error.HTTPError, payload: dict | None) -> dict[str, str]:
    """Extract only bounded, non-secret fields from an HTTP error response."""
    safe: dict[str, str] = {}
    try:
        raw_body = error.read().decode("utf-8", errors="replace")
        decoded: Any = json.loads(raw_body) if raw_body else {}
    except (OSError, UnicodeDecodeError, json.JSONDecodeError):
        decoded = {}

    if isinstance(decoded, dict):
        for key in ("detail", "code", "message"):
            value = decoded.get(key)
            if isinstance(value, str) and value.strip():
                safe[f"_error_{key}"] = _redact_error_text(value.strip(), payload)

    request_id = error.headers.get("X-Request-ID") or error.headers.get("X-Request-Id")
    if request_id:
        safe["_request_id"] = _redact_error_text(str(request_id), None)
    return safe


def _json_request(
    method: str,
    url: str,
    *,
    token: str | None = None,
    payload: dict | None = None,
    timeout: int = 20,
) -> tuple[int, dict]:
    headers = {"Accept": "application/json"}
    data = None
    if payload is not None:
        headers["Content-Type"] = "application/json"
        data = json.dumps(payload).encode("utf-8")
    if token:
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        with opener.open(request, timeout=timeout) as response:
            body = response.read().decode("utf-8")
            return response.status, json.loads(body) if body else {}
    except urllib.error.HTTPError as error:
        return error.code, _safe_error_body(error, payload)


def _require(status: int, expected: set[int], label: str, body: dict | None = None) -> None:
    if status not in expected:
        context: list[str] = []
        if body:
            for key, label_name in (
                ("_error_detail", "detail"),
                ("_error_code", "code"),
                ("_error_message", "message"),
                ("_request_id", "request_id"),
            ):
                value = body.get(key)
                if isinstance(value, str) and value:
                    context.append(f"{label_name}={value}")
        suffix = f" ({', '.join(context)})" if context else ""
        raise RuntimeError(f"{label} failed with HTTP {status}{suffix}")


def _load_credentials(auth_file: str | None) -> tuple[str, str]:
    path = certification._credential_file_path(auth_file)
    if path is None or not path.is_file():
        raise ValueError("a protected stable-account auth file is required")
    security_error = certification._credential_file_security_error(path)
    if security_error:
        raise ValueError(security_error)
    values = certification._parse_env_file(path)
    email = certification._file_default(
        values,
        "SECUREWAVE_RUNTIME_PROBE_EMAIL",
        "SECUREWAVE_TEST_EMAIL",
        "DEMO_EMAIL",
    )
    password = certification._file_default(
        values,
        "SECUREWAVE_RUNTIME_PROBE_PASSWORD",
        "SECUREWAVE_TEST_PASSWORD",
        "DEMO_PASSWORD",
    )
    error = certification._credential_error(email, password)
    if error:
        raise ValueError(error)
    return email.strip(), password.strip()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--api-base",
        default=os.environ.get("SECUREWAVE_API_BASE_URL"),
        help="Explicit authorized staging API base.",
    )
    parser.add_argument(
        "--auth-file",
        default=os.environ.get("SECUREWAVE_CERT_AUTH_FILE"),
        help="Protected key-value file for one existing stable account.",
    )
    parser.add_argument(
        "--allow-production",
        action="store_true",
        help="Explicitly authorize the repository's production API guard.",
    )
    parser.add_argument("--profile-repeats", type=int, default=1)
    args = parser.parse_args(argv)

    try:
        api_base = certification._canonical_api_base(
            args.api_base or "", allow_production=args.allow_production
        )
        email, password = _load_credentials(args.auth_file)
    except (argparse.ArgumentTypeError, ValueError) as error:
        parser.error(str(error))
    if args.profile_repeats < 1:
        parser.error("--profile-repeats must be positive")

    status, body = _json_request("GET", f"{api_base}/health")
    _require(status, {200}, "health", body)

    status, body = _json_request(
        "POST",
        f"{api_base}/auth/login",
        payload={"email": email, "password": password},
    )
    _require(status, {200}, "login", body)
    token = body.get("access_token")
    if not isinstance(token, str) or not token:
        raise RuntimeError("login succeeded without an access token")

    status, body = _json_request("GET", f"{api_base}/auth/me", token=token)
    _require(status, {200}, "account", body)
    status, plan = _json_request("GET", f"{api_base}/user/plan", token=token)
    _require(status, {200}, "usage plan", plan)
    status, servers = _json_request(
        "GET", f"{api_base}/vpn/servers?device_type=linux", token=token
    )
    _require(status, {200}, "server inventory", servers)
    server_items = servers.get("servers") or []
    if not server_items:
        raise RuntimeError("server inventory returned zero servers")

    profile_statuses: list[int] = []
    for _ in range(args.profile_repeats):
        status, body = _json_request(
            "POST",
            f"{api_base}/vpn/profile",
            token=token,
            payload={
                "device_name": "SecureWave Linux certification",
                "device_type": "linux",
                "protocol": PROTOCOL,
                "server_id": server_items[0].get("id")
                or server_items[0].get("server_id"),
            },
        )
        _require(status, {200}, "WireGuard profile", body)
        profile_statuses.append(status)

    print(
        json.dumps(
            {
                "ok": True,
                "account": "authenticated-existing-account",
                "plan_available": bool(plan),
                "server_count": len(server_items),
                "protocol": PROTOCOL,
                "profile_statuses": profile_statuses,
            },
            indent=2,
            sort_keys=True,
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
