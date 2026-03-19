import functools
import http.cookiejar
import json
import os
from pathlib import Path
import shutil
import subprocess
import urllib.error
import urllib.request
import uuid

import pytest

from tests.preview.conftest import preview_stack  # noqa: F401


RUNNER_PATH = Path(__file__).with_name("site_full_site_flow_runner.cjs")


def _request_json(
    opener: urllib.request.OpenerDirector,
    url: str,
    *,
    method: str = "GET",
    payload: dict | None = None,
    headers: dict[str, str] | None = None,
) -> tuple[int, dict]:
    body = None if payload is None else json.dumps(payload).encode("utf-8")
    request_headers = {"Content-Type": "application/json"}
    if headers:
        request_headers.update(headers)
    req = urllib.request.Request(
        url,
        data=body,
        method=method,
        headers=request_headers,
    )
    try:
        with opener.open(req, timeout=10) as resp:  # nosec - local preview stack
            raw = resp.read().decode("utf-8")
            return resp.status, json.loads(raw or "{}")
    except urllib.error.HTTPError as exc:
        raw = exc.read().decode("utf-8")
        return exc.code, json.loads(raw or "{}")


@functools.lru_cache(maxsize=1)
def _playwright_node_path() -> str:
    result = subprocess.run(
        ["bash", "-lc", "npx --yes -p playwright -c 'echo $PATH'"],
        cwd=str(Path(__file__).resolve().parents[2]),
        capture_output=True,
        text=True,
        check=True,
    )
    first_path = result.stdout.strip().split(":")[0]
    if not first_path.endswith("/.bin"):
        raise RuntimeError(f"Unable to resolve Playwright node_modules path from PATH={result.stdout.strip()!r}")
    node_path = first_path[: -len("/.bin")]
    if not Path(node_path, "playwright").exists():
        raise RuntimeError(f"Playwright package not found under {node_path}")
    return node_path


def _chromium_bin() -> str:
    for candidate in ("chromium", "chromium-browser", "/snap/bin/chromium"):
        resolved = shutil.which(candidate) if not candidate.startswith("/") else candidate
        if resolved and Path(resolved).exists():
            return resolved
    raise RuntimeError("Chromium executable not found; install chromium or set CHROMIUM_BIN.")


def _run_browser_flow(base_url: str, *, email: str, password: str) -> dict:
    env = os.environ.copy()
    env.update(
        {
            "BASE_URL": base_url,
            "TEST_EMAIL": email,
            "TEST_PASSWORD": password,
            "NODE_PATH": _playwright_node_path(),
            "CHROMIUM_BIN": _chromium_bin(),
        }
    )
    result = subprocess.run(
        ["node", str(RUNNER_PATH)],
        cwd=str(Path(__file__).resolve().parents[2]),
        env=env,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise AssertionError(
            "Browser E2E flow failed.\n"
            f"stdout:\n{result.stdout}\n"
            f"stderr:\n{result.stderr}"
        )
    try:
        return json.loads(result.stdout.strip())
    except json.JSONDecodeError as exc:
        raise AssertionError(f"Runner did not return JSON summary.\nstdout:\n{result.stdout}") from exc


def test_site_api_proxy_and_session_contract(preview_stack):
    proxy_url = preview_stack.base_url
    base_url = preview_stack.backend_url
    jar = http.cookiejar.CookieJar()
    opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))

    status, payload = _request_json(opener, f"{proxy_url}/api/health")
    assert status == 200
    assert isinstance(payload, dict)

    status, _ = _request_json(opener, f"{base_url}/api/auth/me")
    assert status in {401, 403}

    email = f"site-api-{uuid.uuid4().hex[:12]}@example.com"
    password = "SiteFlow123!"
    status, payload = _request_json(
        opener,
        f"{base_url}/api/auth/register",
        method="POST",
        payload={
            "email": email,
            "password": password,
            "password_confirm": password,
        },
    )
    assert status == 201, payload

    status, payload = _request_json(opener, f"{base_url}/api/auth/me")
    assert status == 200, payload
    assert payload["email"] == email

    status, payload = _request_json(opener, f"{base_url}/api/dashboard/user")
    assert status == 200, payload

    status, payload = _request_json(opener, f"{base_url}/api/billing/plans")
    assert status == 200, payload
    assert isinstance(payload.get("plans"), list)
    assert any(plan.get("id") for plan in payload["plans"])

    csrf_token = next((cookie.value for cookie in jar if cookie.name == "csrf_token"), "")
    assert csrf_token
    status, payload = _request_json(
        opener,
        f"{base_url}/api/auth/logout",
        method="POST",
        payload={},
        headers={"X-CSRF-Token": csrf_token},
    )
    assert status == 200, payload

    status, _ = _request_json(opener, f"{base_url}/api/auth/me")
    assert status in {401, 403}

    status, _ = _request_json(opener, f"{base_url}/api/dashboard/user")
    assert status in {401, 403}


def test_full_site_browser_flow(preview_stack):
    email = f"site-browser-{uuid.uuid4().hex[:12]}@example.com"
    password = "SiteFlow123!"

    summary = _run_browser_flow(preview_stack.backend_url, email=email, password=password)

    assert summary["assistant"]["openStatePersisted"] is True
    assert summary["assistant"]["minimizeStatePersisted"] is True
    assert summary["assistant"]["historyPersisted"] is True
    assert summary["auth"]["registrationRedirectedToDashboard"] is True
    assert summary["auth"]["logoutRedirectedToLogin"] is True
    assert summary["auth"]["validLoginRedirectedToDashboard"] is True
    assert summary["auth"]["dashboardProtectedAfterLogout"] is True
    assert summary["payment"]["successRedirectUrl"].endswith(
        "/billing?mock_checkout=success&session_id=sw_test_checkout"
    )
    assert "Stripe checkout unavailable in test mode." in summary["payment"]["failureAlertMessage"]

    assert {
        "/",
        "/services",
        "/subscription",
        "/login",
        "/register",
        "/dashboard",
        "/settings",
        "/diagnostics",
        "/billing",
    }.issubset(set(summary["pagesCovered"]))
