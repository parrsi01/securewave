#!/usr/bin/env python3
"""
Live SecureWave app-control-plane smoke test.

This checks the backend paths the Flutter app depends on: health, login,
account, usage plan, server inventory, and per-protocol profile issuance. It
uses an existing account by default; account registration is an explicit opt-in
only. It does not start a local VPN tunnel and never prints bearer tokens.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
import urllib.error
import urllib.request

try:
    from login_diagnostic import normalize_api_base
    from cli_operation_common import PacketValidationError, validate_target_reference
except ModuleNotFoundError:  # pragma: no cover - package-based test invocation
    from scripts.login_diagnostic import normalize_api_base
    from scripts.cli_operation_common import PacketValidationError, validate_target_reference


PROTOCOLS = ("wireguard", "openvpn")


def _smoke_protocols(server: dict) -> tuple[str, ...]:
    """Select only protocols explicitly advertised as ready by the API.

    WireGuard remains the baseline Linux release path. OpenVPN is exercised
    only when the authenticated server response contains both the explicit
    protocol readiness marker and the server capability flag. IKEv2 is never
    inferred or added here.
    """

    protocols = ["wireguard"]
    advertised = {
        str(value).strip().lower()
        for value in (server.get("supported_protocols") or [])
        if str(value).strip()
    }
    if "openvpn" in advertised and server.get("supports_openvpn") is True:
        protocols.append("openvpn")
    return tuple(protocol for protocol in PROTOCOLS if protocol in protocols)


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
        with urllib.request.urlopen(request, timeout=timeout) as response:
            body = response.read().decode("utf-8")
            try:
                parsed = json.loads(body) if body else {}
            except json.JSONDecodeError:
                raise RuntimeError("backend returned malformed JSON") from None
            return response.status, parsed
    except urllib.error.HTTPError as error:
        body = error.read().decode("utf-8")
        try:
            parsed = json.loads(body) if body else {}
        except json.JSONDecodeError:
            parsed = {"detail": body}
        return error.code, parsed
    except (urllib.error.URLError, TimeoutError, OSError):
        raise RuntimeError("external connectivity or TLS failure") from None


def _require(status: int, expected: set[int], label: str, _body: dict) -> None:
    if status not in expected:
        raise RuntimeError(f"{label} failed: HTTP {status}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--api-base",
        default=os.environ.get("SECUREWAVE_API_BASE_URL", ""),
        help="explicit HTTPS API base; no public default is used",
    )
    parser.add_argument(
        "--target-ref",
        default=os.environ.get("SECUREWAVE_TARGET_REF", ""),
        help="exact approved inventory reference; no target is inferred",
    )
    parser.add_argument(
        "--register",
        action="store_true",
        help="explicitly allow the legacy registration smoke step",
    )
    parser.add_argument("--profile-repeats", type=int, default=1)
    args = parser.parse_args()

    try:
        api_base = normalize_api_base(args.api_base)
    except Exception as exc:
        parser.error(str(exc))

    try:
        validate_target_reference(args.target_ref)
    except PacketValidationError as exc:
        parser.error(str(exc))

    email = os.environ.get("SECUREWAVE_DIAGNOSTIC_EMAIL", "")
    password = os.environ.get("SECUREWAVE_DIAGNOSTIC_PASSWORD", "")
    if not email or not password:
        parser.error(
            "SECUREWAVE_DIAGNOSTIC_EMAIL and SECUREWAVE_DIAGNOSTIC_PASSWORD are required"
        )

    status, body = _json_request("GET", f"{api_base}/health")
    _require(status, {200}, "health", body)

    if args.register:
        register_payload = {
            "email": email,
            "password": password,
            "password_confirm": password,
        }
        status, body = _json_request(
            "POST", f"{api_base}/auth/register", payload=register_payload
        )
        _require(status, {201, 400, 429}, "registration", body)
        if status == 429:
            # Registration is explicitly opt-in and is never required for the
            # existing-account login check.
            print("registration skipped: live rate limit active; continuing to login")

    status, body = _json_request(
        "POST",
        f"{api_base}/auth/login",
        payload={"email": email, "password": password},
    )
    # Do not deliberately retain the password after the one login request.
    email = ""
    password = ""
    _require(status, {200}, "login", body)
    token = body.get("access_token")
    if not token:
        raise RuntimeError("login succeeded without access_token")

    status, account = _json_request("GET", f"{api_base}/auth/me", token=token)
    _require(status, {200}, "account", account)

    status, plan = _json_request("GET", f"{api_base}/user/plan", token=token)
    _require(status, {200}, "usage plan", plan)

    status, servers = _json_request("GET", f"{api_base}/vpn/servers", token=token)
    _require(status, {200}, "server inventory", servers)
    server_items = servers.get("servers") or []
    if not server_items:
        raise RuntimeError("server inventory returned zero servers")

    selected_server = server_items[0]
    smoke_protocols = _smoke_protocols(selected_server)
    profile_results: dict[str, list[int]] = {protocol: [] for protocol in smoke_protocols}
    for repeat in range(args.profile_repeats):
        for protocol in smoke_protocols:
            status, body = _json_request(
                "POST",
                f"{api_base}/vpn/profile",
                token=token,
                payload={
                    "device_name": "Codex Linux live smoke",
                    "device_type": "linux",
                    "protocol": protocol,
                    "server_id": selected_server.get("id")
                    or selected_server.get("server_id"),
                },
            )
            profile_results[protocol].append(status)
            if protocol in {"wireguard", "openvpn"}:
                _require(status, {200}, f"{protocol} profile", body)

    summary = {
        "api_base_fingerprint": hashlib.sha256(api_base.encode("utf-8")).hexdigest(),
        "target_reference_fingerprint": hashlib.sha256(
            args.target_ref.encode("utf-8")
        ).hexdigest(),
        "account_present": bool(account),
        "plan": plan.get("plan_name") or plan.get("plan"),
        "usage": {
            "used_gb": plan.get("used_gb"),
            "limit_gb": plan.get("data_cap_gb")
            or plan.get("data_limit_gb")
            or plan.get("limit_gb"),
        },
        "server_count": len(server_items),
        "profile_statuses": profile_results,
        "protocols_skipped_without_authenticated_readiness": [
            protocol for protocol in PROTOCOLS if protocol not in smoke_protocols
        ],
        "note": "Only protocols with current smoke-contract evidence are exercised.",
    }
    token = ""
    print(json.dumps(summary, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
