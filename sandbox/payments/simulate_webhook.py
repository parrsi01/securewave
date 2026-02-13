#!/usr/bin/env python3
"""
Simulate Stripe webhook events against local backend.

This sends mock webhook payloads WITHOUT valid signatures.
The backend will reject them (400) unless you disable signature
verification or use the Stripe CLI for real forwarding.

For real testing:
    stripe listen --forward-to localhost:8000/api/billing/webhooks/stripe
    stripe trigger checkout.session.completed

Usage:
    python sandbox/payments/simulate_webhook.py [--base-url http://localhost:8000] [--event checkout.session.completed]
"""

import argparse
import json
import time
import hmac
import hashlib
import requests

SAMPLE_EVENTS = {
    "checkout.session.completed": {
        "id": "evt_test_checkout_completed",
        "type": "checkout.session.completed",
        "data": {
            "object": {
                "id": "cs_test_123",
                "object": "checkout.session",
                "customer": "cus_test_123",
                "client_reference_id": "cus_test_123",
                "mode": "subscription",
                "subscription": "sub_test_123",
                "payment_status": "paid",
                "status": "complete",
                "metadata": {
                    "plan_id": "basic",
                    "billing_cycle": "monthly",
                    "stripe_mode": "test",
                },
            }
        },
    },
    "customer.subscription.created": {
        "id": "evt_test_sub_created",
        "type": "customer.subscription.created",
        "data": {
            "object": {
                "id": "sub_test_123",
                "object": "subscription",
                "customer": "cus_test_123",
                "status": "active",
                "current_period_start": int(time.time()),
                "current_period_end": int(time.time()) + 30 * 86400,
                "items": {
                    "data": [
                        {
                            "price": {
                                "id": "price_test_basic_monthly",
                                "unit_amount": 999,
                                "currency": "usd",
                            }
                        }
                    ]
                },
            }
        },
    },
    "invoice.payment_succeeded": {
        "id": "evt_test_invoice_paid",
        "type": "invoice.payment_succeeded",
        "data": {
            "object": {
                "id": "in_test_123",
                "object": "invoice",
                "customer": "cus_test_123",
                "subscription": "sub_test_123",
                "amount_paid": 999,
                "currency": "usd",
                "status": "paid",
            }
        },
    },
    "customer.subscription.deleted": {
        "id": "evt_test_sub_deleted",
        "type": "customer.subscription.deleted",
        "data": {
            "object": {
                "id": "sub_test_123",
                "object": "subscription",
                "customer": "cus_test_123",
                "status": "canceled",
            }
        },
    },
}


def generate_fake_signature(payload: bytes, secret: str = "whsec_test_secret") -> str:
    """Generate a fake Stripe webhook signature (for local testing only)."""
    timestamp = str(int(time.time()))
    signed_payload = f"{timestamp}.{payload.decode()}"
    sig = hmac.new(secret.encode(), signed_payload.encode(), hashlib.sha256).hexdigest()
    return f"t={timestamp},v1={sig}"


def main():
    parser = argparse.ArgumentParser(description="Simulate Stripe webhooks")
    parser.add_argument("--base-url", default="http://localhost:8000")
    parser.add_argument("--event", default="checkout.session.completed",
                        choices=list(SAMPLE_EVENTS.keys()))
    parser.add_argument("--webhook-secret", default="",
                        help="If set, generates a valid signature for this secret")
    args = parser.parse_args()

    base = args.base_url.rstrip("/")
    event_data = SAMPLE_EVENTS[args.event]
    payload = json.dumps(event_data).encode()

    sig = generate_fake_signature(payload, args.webhook_secret or "whsec_test")

    print(f"Sending {args.event} to {base}/api/billing/webhooks/stripe")
    r = requests.post(
        f"{base}/api/billing/webhooks/stripe",
        data=payload,
        headers={
            "Content-Type": "application/json",
            "Stripe-Signature": sig,
        },
        timeout=10,
    )
    print(f"Response: {r.status_code}")
    print(json.dumps(r.json(), indent=2) if r.headers.get("content-type", "").startswith("application/json") else r.text)

    if r.status_code == 400:
        print("\nExpected: 400 (signature mismatch). Use Stripe CLI for real webhook testing:")
        print("  stripe listen --forward-to localhost:8000/api/billing/webhooks/stripe")


if __name__ == "__main__":
    main()
