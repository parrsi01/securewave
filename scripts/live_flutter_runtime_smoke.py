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

try:
    from scripts import linux_app_vpn_tunnel_proof as certification
except ModuleNotFoundError:  # Direct execution from scripts/.
    import linux_app_vpn_tunnel_proof as certification


PROTOCOL = "wireguard"


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
        return error.code, {}


def _require(status: int, expected: set[int], label: str) -> None:
    if status not in expected:
        raise RuntimeError(f"{label} failed with HTTP {status}")


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

    status, _ = _json_request("GET", f"{api_base}/health")
    _require(status, {200}, "health")

    status, body = _json_request(
        "POST",
        f"{api_base}/auth/login",
        payload={"email": email, "password": password},
    )
    _require(status, {200}, "login")
    token = body.get("access_token")
    if not isinstance(token, str) or not token:
        raise RuntimeError("login succeeded without an access token")

    status, _ = _json_request("GET", f"{api_base}/auth/me", token=token)
    _require(status, {200}, "account")
    status, plan = _json_request("GET", f"{api_base}/user/plan", token=token)
    _require(status, {200}, "usage plan")
    status, servers = _json_request(
        "GET", f"{api_base}/vpn/servers?device_type=linux", token=token
    )
    _require(status, {200}, "server inventory")
    server_items = servers.get("servers") or []
    if not server_items:
        raise RuntimeError("server inventory returned zero servers")

    profile_statuses: list[int] = []
    for _ in range(args.profile_repeats):
        status, _ = _json_request(
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
        _require(status, {200}, "WireGuard profile")
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
