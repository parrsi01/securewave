#!/usr/bin/env python3
import sys
import os

# Re-exec under venv python if not already inside it
_project_root = os.path.dirname(os.path.abspath(__file__))
_venv_python = os.path.join(_project_root, ".venv", "bin", "python3")
if not _venv_python.startswith(sys.prefix) and os.path.exists(_venv_python):
    os.execv(_venv_python, [_venv_python] + sys.argv)

import requests

# Ensure project root is on path
sys.path.insert(0, _project_root)

BASE_URL = "http://138.199.204.139/api"
TEST_EMAIL = "test@securewaveapp.com"
TEST_PASSWORD = "Test123Secure!"

PASS = "\033[32mPASS\033[0m"
FAIL = "\033[31mFAIL\033[0m"

results = []

def step(label, ok, detail=""):
    status = PASS if ok else FAIL
    msg = f"[{status}] {label}"
    if detail:
        msg += f" — {detail}"
    print(msg)
    results.append(ok)


# ── 1. User bootstrap via registration endpoint ───────────────────────────────
try:
    r = requests.post(
        f"{BASE_URL}/auth/register",
        json={"email": TEST_EMAIL, "password": TEST_PASSWORD, "password_confirm": TEST_PASSWORD},
        timeout=15,
    )
    if r.status_code == 201:
        uid = r.json().get("user_id", "?")
        step("HTTP: POST /auth/register (user created)", True, f"user_id={uid}")
    elif r.status_code in (400, 409, 422):
        body = r.json()
        # Already exists or duplicate email → treat as success
        msg = str(body)
        if "already" in msg.lower() or "exist" in msg.lower() or "duplicate" in msg.lower() or "registered" in msg.lower():
            step("HTTP: POST /auth/register (user exists, reusing)", True)
        else:
            step("HTTP: POST /auth/register", False, f"status={r.status_code} body={body}")
    else:
        step("HTTP: POST /auth/register", False, f"status={r.status_code} body={r.json()}")
except Exception as e:
    step("HTTP: POST /auth/register", False, str(e))


# ── 2. Login ─────────────────────────────────────────────────────────────────
token = None
try:
    resp = requests.post(
        f"{BASE_URL}/auth/login",
        json={"email": TEST_EMAIL, "password": TEST_PASSWORD},
        timeout=15,
    )
    data = resp.json()
    if resp.status_code == 200 and "access_token" in data:
        token = data["access_token"]
        step("HTTP: POST /auth/login", True, f"status={resp.status_code}")
    else:
        step("HTTP: POST /auth/login", False, f"status={resp.status_code} body={data}")
except Exception as e:
    step("HTTP: POST /auth/login", False, str(e))

if not token:
    print("\nFATAL: no token — aborting remaining checks")
    sys.exit(1)


# ── 3. GET /vpn/servers ───────────────────────────────────────────────────────
try:
    resp = requests.get(
        f"{BASE_URL}/vpn/servers",
        headers={"Authorization": f"Bearer {token}"},
        timeout=15,
    )
    ok = resp.status_code == 200
    step("HTTP: GET /vpn/servers", ok, f"status={resp.status_code}")
    if not ok:
        print(f"       response: {resp.text[:300]}")
except Exception as e:
    step("HTTP: GET /vpn/servers", False, str(e))


# ── Summary ───────────────────────────────────────────────────────────────────
print()
total = len(results)
passed = sum(results)
print(f"{'='*40}")
print(f"Result: {passed}/{total} checks passed")
print(f"{'='*40}")

if not all(results):
    sys.exit(1)
