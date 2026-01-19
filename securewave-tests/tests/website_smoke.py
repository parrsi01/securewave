#!/usr/bin/env python3
"""
SecureWave VPN Test Suite - Website Smoke Tests
Validates core API flows against a running SecureWave instance.
"""

import json
import time
import uuid
from dataclasses import dataclass, asdict
from typing import Dict, Any, Optional, List
from urllib import request, error


@dataclass
class SmokeStepResult:
    name: str
    success: bool
    status_code: Optional[int]
    error: Optional[str]


@dataclass
class WebsiteSmokeResult:
    base_url: str
    success: bool
    steps: List[Dict[str, Any]]
    timestamp: float


def _request_json(
    method: str,
    url: str,
    payload: Optional[Dict[str, Any]] = None,
    token: Optional[str] = None,
    timeout: int = 10,
) -> tuple[int, str]:
    data = None
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
    req = request.Request(url, data=data, method=method)
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    try:
        with request.urlopen(req, timeout=timeout) as resp:
            return resp.status, resp.read().decode("utf-8")
    except error.HTTPError as exc:
        return exc.code, exc.read().decode("utf-8")
    except Exception as exc:
        return 0, str(exc)


def run_website_smoke_test(
    base_url: str,
    email: Optional[str] = None,
    password: Optional[str] = None,
    trigger_test_run: bool = True,
) -> WebsiteSmokeResult:
    """
    Run a smoke test against the SecureWave API.

    Validates:
    - /health
    - Register/Login
    - /api/vpn/servers
    - /api/vpn/devices
    - /api/vpn/allocate
    - /api/vpn/tests/run
    """
    steps: List[SmokeStepResult] = []
    timestamp = time.time()

    def record(name: str, status_code: Optional[int], error_msg: Optional[str] = None):
        steps.append(
            SmokeStepResult(
                name=name,
                success=bool(status_code) and 200 <= status_code < 400,
                status_code=status_code,
                error=error_msg,
            )
        )

    base_url = base_url.rstrip("/")
    unique = uuid.uuid4().hex[:8]
    if not email:
        email = f"securewave.test+{int(timestamp)}-{unique}@example.com"
    if not password:
        password = "TestPass!234"

    status, body = _request_json("GET", f"{base_url}/health")
    record("health", status, None if status else body)

    status, body = _request_json("GET", f"{base_url}/api/health")
    record("api_health", status, None if status else body)

    status, body = _request_json("POST", f"{base_url}/api/auth/register", {
        "email": email,
        "password": password,
        "password_confirm": password,
    })
    # 201 expected, 409 acceptable if user exists
    if status == 409:
        steps.append(SmokeStepResult("register", True, status, "user already exists"))
    else:
        record("register", status, None if 200 <= status < 400 else body)

    status, body = _request_json("POST", f"{base_url}/api/auth/login", {
        "email": email,
        "password": password,
    })
    token = None
    if status == 200:
        try:
            token = json.loads(body).get("access_token")
        except Exception:
            token = None
    record("login", status, None if status else body)

    if token:
        status, body = _request_json(
            "POST",
            f"{base_url}/api/billing/subscriptions",
            payload={
                "plan_id": "basic",
                "billing_cycle": "monthly",
                "provider": "stripe",
            },
            token=token,
        )
        if status == 400 and "active subscription" in body.lower():
            steps.append(SmokeStepResult("billing_subscribe", True, status, "already active"))
        else:
            record("billing_subscribe", status, None if status else body)

    status, body = _request_json("GET", f"{base_url}/api/vpn/servers", token=token)
    record("vpn_servers", status, None if status else body)

    status, body = _request_json("GET", f"{base_url}/api/vpn/devices", token=token)
    record("vpn_devices", status, None if status else body)

    status, body = _request_json("POST", f"{base_url}/api/vpn/allocate", payload={}, token=token)
    record("vpn_allocate", status, None if status else body)

    if trigger_test_run:
        status, body = _request_json(
            "POST",
            f"{base_url}/api/vpn/tests/run",
            payload={"quick": True, "skip_baseline": True},
            token=token,
            timeout=15,
        )
        # 200 OK or 409 already running is acceptable
        if status == 409:
            steps.append(SmokeStepResult("vpn_tests_run", True, status, "test already running"))
        else:
            record("vpn_tests_run", status, None if status else body)

    success = all(step.success for step in steps)
    return WebsiteSmokeResult(
        base_url=base_url,
        success=success,
        steps=[asdict(step) for step in steps],
        timestamp=timestamp,
    )
