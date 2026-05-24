#!/usr/bin/env python3
"""
Live SecureWave app-control-plane smoke test.

This checks the backend paths the Flutter app depends on: health, registration,
login, account, usage plan, server inventory, and per-protocol profile issuance.
It does not start a local VPN tunnel and never prints bearer tokens.
"""

from __future__ import annotations

import argparse
import json
import secrets
import sys
import time
import urllib.error
import urllib.request


DEFAULT_API_BASE = "https://api.securewaveapp.com/api"
PROTOCOLS = ("wireguard", "openvpn", "ikev2")


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
            return response.status, json.loads(body) if body else {}
    except urllib.error.HTTPError as error:
        body = error.read().decode("utf-8")
        try:
            parsed = json.loads(body) if body else {}
        except json.JSONDecodeError:
            parsed = {"detail": body}
        return error.code, parsed


def _require(status: int, expected: set[int], label: str, body: dict) -> None:
    if status not in expected:
        raise RuntimeError(f"{label} failed: HTTP {status} {body}")


def _default_email() -> str:
    stamp = time.strftime("%Y%m%d%H%M%S", time.gmtime())
    suffix = secrets.token_hex(3)
    return f"securewave.qa.{stamp}.{suffix}@gmail.com"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--api-base", default=DEFAULT_API_BASE)
    parser.add_argument("--email", default=_default_email())
    parser.add_argument("--password", default=f"SwSmoke{secrets.token_hex(4)}!A1")
    parser.add_argument("--profile-repeats", type=int, default=1)
    args = parser.parse_args()

    api_base = args.api_base.rstrip("/")

    status, body = _json_request("GET", f"{api_base}/health")
    _require(status, {200}, "health", body)

    register_payload = {
        "email": args.email,
        "password": args.password,
        "password_confirm": args.password,
    }
    status, body = _json_request(
        "POST", f"{api_base}/auth/register", payload=register_payload
    )
    _require(status, {201, 400}, "registration", body)
    if status == 400 and "registered" not in str(body).lower():
        raise RuntimeError(f"registration failed: HTTP {status} {body}")

    status, body = _json_request(
        "POST",
        f"{api_base}/auth/login",
        payload={"email": args.email, "password": args.password},
    )
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

    profile_results: dict[str, list[int]] = {protocol: [] for protocol in PROTOCOLS}
    for repeat in range(args.profile_repeats):
        for protocol in PROTOCOLS:
            status, body = _json_request(
                "POST",
                f"{api_base}/vpn/profile",
                token=token,
                payload={
                    "device_name": "Codex Linux live smoke",
                    "device_type": "linux",
                    "protocol": protocol,
                    "server_id": server_items[0].get("id")
                    or server_items[0].get("server_id"),
                },
            )
            profile_results[protocol].append(status)
            if protocol in {"wireguard", "openvpn"}:
                _require(status, {200}, f"{protocol} profile", body)

    summary = {
        "api_base": api_base,
        "email": args.email,
        "password": args.password,
        "account_email": account.get("email"),
        "plan": plan.get("plan_name") or plan.get("plan"),
        "usage": {
            "used_gb": plan.get("used_gb"),
            "limit_gb": plan.get("data_cap_gb")
            or plan.get("data_limit_gb")
            or plan.get("limit_gb"),
        },
        "server_count": len(server_items),
        "server_ids": [
            item.get("id") or item.get("server_id") for item in server_items
        ],
        "profile_statuses": profile_results,
        "note": "IKEv2 may return a typed non-200 until Linux strongSwan issuance is live.",
    }
    print(json.dumps(summary, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
