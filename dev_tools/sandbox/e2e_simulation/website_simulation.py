#!/usr/bin/env python3
"""
SecureWave local-only website/API simulation.

This intentionally avoids external cloud dependencies and runs against a local uvicorn
instance backed by sqlite.
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from dataclasses import dataclass, asdict
from typing import Any, Dict, Optional, Tuple
from urllib import error, request
from urllib.parse import urlparse


@dataclass
class StepResult:
    name: str
    success: bool
    status_code: Optional[int]
    detail: Optional[str] = None


def _assert_local_base_url(base_url: str) -> None:
    parsed = urlparse(base_url)
    host = parsed.hostname or ""
    if host not in ("127.0.0.1", "localhost"):
        raise ValueError(f"Cloud/remote base URLs are not allowed: {base_url}")


def _request(
    method: str,
    url: str,
    payload: Optional[Dict[str, Any]] = None,
    token: Optional[str] = None,
    timeout: int = 10,
) -> Tuple[int, str, Dict[str, str]]:
    data = None
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
    req = request.Request(url, data=data, method=method)
    if payload is not None:
        req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    try:
        with request.urlopen(req, timeout=timeout) as resp:
            body = resp.read().decode("utf-8", errors="replace")
            headers = {k.lower(): v for k, v in resp.headers.items()}
            return resp.status, body, headers
    except error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        headers = {k.lower(): v for k, v in exc.headers.items()}
        return exc.code, body, headers
    except Exception as exc:
        return 0, str(exc), {}


def _json(body: str) -> Dict[str, Any]:
    return json.loads(body)


def main() -> int:
    parser = argparse.ArgumentParser(description="SecureWave local-only website simulation")
    parser.add_argument("--base-url", required=True, help="Local base URL (http://127.0.0.1:PORT)")
    parser.add_argument("--out", default=None, help="Write JSON results to this path")
    args = parser.parse_args()

    base_url = args.base_url.rstrip("/")
    _assert_local_base_url(base_url)

    steps: list[StepResult] = []

    def record(name: str, ok: bool, status_code: Optional[int], detail: Optional[str] = None) -> None:
        steps.append(StepResult(name=name, success=ok, status_code=status_code, detail=detail))

    # Landing + core pages
    for path in ("/", "/home", "/download", "/contact", "/settings", "/diagnostics", "/dashboard"):
        status, body, headers = _request("GET", f"{base_url}{path}", timeout=10)
        ok = status == 200 and "text/html" in headers.get("content-type", "")
        record(f"page:{path}", ok, status, None if ok else body[:400])

    # Downloads must not expose config files.
    status, body, _ = _request("GET", f"{base_url}/download", timeout=10)
    forbidden_markers = (".conf", ".ovpn", "wg-quick.conf", "wireguard.conf")
    has_forbidden = any(marker in body.lower() for marker in forbidden_markers)
    record("downloads:no_manual_configs", status == 200 and not has_forbidden, status, "found forbidden marker" if has_forbidden else None)

    # Auth: register/login/logout
    email = f"sim+{int(time.time())}@example.com"
    password = "SimTestPass!234"
    status, body, _ = _request(
        "POST",
        f"{base_url}/api/auth/register",
        payload={"email": email, "password": password, "password_confirm": password},
        timeout=10,
    )
    token: Optional[str] = None
    if status in (200, 201):
        try:
            token = _json(body).get("access_token")
        except Exception:
            token = None
    record("auth:register", status in (200, 201), status, None if status in (200, 201) else body[:400])

    status, body, _ = _request(
        "POST",
        f"{base_url}/api/auth/login",
        payload={"email": email, "password": password},
        timeout=10,
    )
    if status == 200:
        try:
            token = token or _json(body).get("access_token")
        except Exception:
            token = token
    record("auth:login", status == 200 and bool(token), status, None if status == 200 else body[:400])

    # Auth errors
    status, body, _ = _request("GET", f"{base_url}/api/dashboard/user", timeout=10)
    record("auth:protected_requires_auth", status in (401, 403), status, None if status in (401, 403) else body[:200])

    if not token:
        record("auth:token_available", False, None, "no access_token returned")
        # Can't meaningfully continue API-authenticated checks
        success = all(s.success for s in steps)
        payload = {"base_url": base_url, "success": success, "steps": [asdict(s) for s in steps]}
        if args.out:
            with open(args.out, "w", encoding="utf-8") as handle:
                json.dump(payload, handle, indent=2, sort_keys=True)
        print(json.dumps(payload, indent=2, sort_keys=True))
        return 1

    # Account/session center APIs
    status, body, _ = _request("GET", f"{base_url}/api/auth/me", token=token, timeout=10)
    ok = status == 200
    record("account:me", ok, status, None if ok else body[:400])

    status, body, _ = _request("GET", f"{base_url}/api/dashboard/user", token=token, timeout=10)
    record("account:dashboard", status == 200, status, None if status == 200 else body[:400])

    status, body, _ = _request("GET", f"{base_url}/api/vpn/devices", token=token, timeout=10)
    record("account:devices", status == 200, status, None if status == 200 else body[:400])

    status, body, _ = _request("GET", f"{base_url}/api/vpn/servers", token=token, timeout=10)
    record("vpn:servers", status == 200, status, None if status == 200 else body[:400])

    # Device registration (app flow)
    status, body, _ = _request(
        "POST",
        f"{base_url}/api/vpn/devices",
        payload={"name": "Sim Device", "device_type": "android"},
        token=token,
        timeout=10,
    )
    device_id: Optional[int] = None
    if status in (200, 201):
        try:
            device_id = int(_json(body).get("id"))
        except Exception:
            device_id = None
    record("vpn:device_register", status in (200, 201) and bool(device_id), status, None if status in (200, 201) else body[:400])

    # VPN profile fetch (app flow)
    profile_payload: Dict[str, Any] = {"device_type": "android", "protocol": "wireguard"}
    if device_id:
        profile_payload["device_id"] = device_id
    else:
        profile_payload["device_name"] = "Sim Device"

    status, body, _ = _request(
        "POST",
        f"{base_url}/api/vpn/profile",
        payload=profile_payload,
        token=token,
        timeout=10,
    )
    endpoint_line = None
    if status == 200:
        try:
            cfg = _json(body).get("wireguard_config", "")
            endpoint_line = next((ln for ln in cfg.splitlines() if ln.strip().startswith("Endpoint =")), None)
        except Exception:
            endpoint_line = None
    record(
        "vpn:profile_fetch",
        status == 200 and bool(endpoint_line),
        status,
        None if (status == 200 and endpoint_line) else body[:400],
    )

    # VPN demo connect/disconnect flows (no real tunnel required)
    status, body, _ = _request("POST", f"{base_url}/api/vpn/connect", payload={"region": "us-east"}, token=token, timeout=10)
    ok = status == 200
    record("vpn:connect", ok, status, None if ok else body[:400])

    # Status should transition to CONNECTED in demo mode.
    time.sleep(1.2)
    status, body, _ = _request("GET", f"{base_url}/api/vpn/status", token=token, timeout=10)
    ok = status == 200 and _json(body).get("status") in ("CONNECTED", "CONNECTING")
    record("vpn:status", ok, status, None if ok else body[:400])

    status, body, _ = _request("GET", f"{base_url}/api/vpn/config", token=token, timeout=10)
    ok = status == 200 and "config" in _json(body)
    record("vpn:config", ok, status, None if ok else body[:400])

    status, body, _ = _request("POST", f"{base_url}/api/vpn/disconnect", token=token, timeout=10)
    record("vpn:disconnect", status == 200, status, None if status == 200 else body[:400])

    # Contact form must work without SMTP (fallback).
    status, body, _ = _request(
        "POST",
        f"{base_url}/api/contact/submit",
        payload={
            "name": "Sim User",
            "email": "sim.user@example.com",
            "subject": "Support request",
            "message": "Testing contact form in local-only simulation mode.",
        },
        timeout=10,
    )
    ok = status == 200 and _json(body).get("success") is True
    record("contact:submit", ok, status, None if ok else body[:400])

    # Error handling: custom 404 page for web routes
    status, body, headers = _request("GET", f"{base_url}/this-page-should-not-exist", timeout=10)
    ok = status == 404 and "text/html" in headers.get("content-type", "")
    record("errors:web_404", ok, status, None if ok else body[:200])

    # Error handling: API 404 returns structured JSON error
    status, body, headers = _request("GET", f"{base_url}/api/this-should-not-exist", timeout=10)
    ok = status == 404 and "application/json" in headers.get("content-type", "")
    try:
        ok = ok and _json(body).get("error", {}).get("code") == "not_found"
    except Exception:
        ok = False
    record("errors:api_404", ok, status, None if ok else body[:200])

    # Logout
    status, body, _ = _request("POST", f"{base_url}/api/auth/logout", token=token, timeout=10)
    ok = status == 200 and _json(body).get("status") == "ok"
    record("auth:logout", ok, status, None if ok else body[:200])

    success = all(step.success for step in steps)
    payload = {
        "base_url": base_url,
        "success": success,
        "steps": [asdict(step) for step in steps],
    }

    if args.out:
        with open(args.out, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, indent=2, sort_keys=True)

    print(json.dumps(payload, indent=2, sort_keys=True))
    return 0 if success else 1


if __name__ == "__main__":
    raise SystemExit(main())
