#!/usr/bin/env python3
"""
SecureWave Stripe Integration Test Harness
Tests the billing API endpoints against a running backend using Stripe TEST keys.

Usage:
    python sandbox/payments/test_stripe_flow.py [--base-url http://localhost:8000]
"""

import argparse
import json
import sys
import requests

PASS = "\033[92mPASS\033[0m"
FAIL = "\033[91mFAIL\033[0m"
SKIP = "\033[93mSKIP\033[0m"


def _print(label: str, msg: str):
    print(f"  [{label}] {msg}")


def test_plans(base: str) -> bool:
    """GET /api/billing/plans — should return plan list."""
    r = requests.get(f"{base}/api/billing/plans", timeout=10)
    if r.status_code != 200:
        _print(FAIL, f"GET /plans returned {r.status_code}")
        return False
    data = r.json()
    plans = data.get("plans", [])
    if len(plans) < 3:
        _print(FAIL, f"Expected >=3 plans, got {len(plans)}")
        return False
    for p in plans:
        if not p.get("pricing", {}).get("monthly") and p["id"] != "free":
            _print(FAIL, f"Plan {p['id']} missing monthly price")
            return False
    _print(PASS, f"GET /plans — {len(plans)} plans returned")
    return True


def test_stripe_status(base: str) -> dict:
    """GET /api/billing/stripe-status — check Stripe configuration."""
    r = requests.get(f"{base}/api/billing/stripe-status", timeout=10)
    if r.status_code != 200:
        _print(FAIL, f"GET /stripe-status returned {r.status_code}")
        return {}
    data = r.json()
    mode = data.get("mode", "unconfigured")
    configured = data.get("configured", False)
    webhook = data.get("webhook_configured", False)
    if not configured:
        _print(SKIP, "Stripe not configured — skipping payment tests")
    elif mode == "test":
        _print(PASS, f"Stripe in TEST mode, webhook_configured={webhook}")
    elif mode == "live":
        _print(FAIL, "Stripe in LIVE mode — do NOT run test harness against live keys!")
        sys.exit(1)
    return data


def test_checkout_session_requires_auth(base: str) -> bool:
    """POST /api/billing/checkout-session without auth should 401/403."""
    r = requests.post(
        f"{base}/api/billing/checkout-session",
        json={"plan_id": "basic", "billing_cycle": "monthly"},
        timeout=10,
    )
    if r.status_code in (401, 403, 422):
        _print(PASS, f"POST /checkout-session without auth returned {r.status_code}")
        return True
    _print(FAIL, f"POST /checkout-session without auth returned {r.status_code} (expected 401/403)")
    return False


def test_webhook_rejects_bad_signature(base: str) -> bool:
    """POST /api/billing/webhooks/stripe with bad signature should 400."""
    r = requests.post(
        f"{base}/api/billing/webhooks/stripe",
        data=b'{"type":"test"}',
        headers={
            "Content-Type": "application/json",
            "Stripe-Signature": "t=0,v1=bad_signature",
        },
        timeout=10,
    )
    if r.status_code == 400:
        _print(PASS, "Webhook rejects bad signature (400)")
        return True
    _print(FAIL, f"Webhook with bad signature returned {r.status_code} (expected 400)")
    return False


def main():
    parser = argparse.ArgumentParser(description="SecureWave Stripe test harness")
    parser.add_argument("--base-url", default="http://localhost:8000", help="Backend base URL")
    args = parser.parse_args()
    base = args.base_url.rstrip("/")

    print(f"\n=== SecureWave Stripe Test Harness ===")
    print(f"Target: {base}\n")

    results = []

    # 1. Check backend is up
    try:
        r = requests.get(f"{base}/api/health", timeout=5)
        if r.status_code != 200:
            r = requests.get(f"{base}/", timeout=5)
    except requests.ConnectionError:
        _print(FAIL, f"Cannot connect to {base}")
        print("\nStart the backend first: uvicorn main:app --port 8000")
        sys.exit(1)

    # 2. Plans
    results.append(test_plans(base))

    # 3. Stripe status
    stripe_data = test_stripe_status(base)

    # 4. Auth check on checkout
    results.append(test_checkout_session_requires_auth(base))

    # 5. Webhook signature verification
    results.append(test_webhook_rejects_bad_signature(base))

    # Summary
    passed = sum(1 for r in results if r)
    total = len(results)
    print(f"\n{'='*40}")
    print(f"Results: {passed}/{total} passed")
    if stripe_data.get("mode") == "unconfigured":
        print("Note: Stripe not configured — set STRIPE_SECRET_KEY for full tests")
    print()
    sys.exit(0 if passed == total else 1)


if __name__ == "__main__":
    main()
