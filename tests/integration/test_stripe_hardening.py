"""
SecureWave - Stripe Hardening Integration Tests
==============================================
Covers:
- Strict webhook signature verification
- Webhook replay protection
- Customer/user mismatch protection
- Checkout session idempotency (double-submit protection)
- Subscription state transitions driven by webhook events
"""

from __future__ import annotations

import hashlib
import hmac
import json
import time
from types import SimpleNamespace

import pytest


def _stripe_signature_header(*, payload: bytes, secret: str, timestamp: int | None = None) -> str:
    ts = int(timestamp or time.time())
    signed_payload = f"{ts}.".encode("utf-8") + payload
    sig = hmac.new(secret.encode("utf-8"), signed_payload, hashlib.sha256).hexdigest()
    return f"t={ts},v1={sig}"


def _configure_stripe_env(monkeypatch, *, webhook_secret: str = "whsec_test_secret"):
    monkeypatch.setenv("STRIPE_SECRET_KEY", "sk_test_dummy")
    monkeypatch.setenv("STRIPE_WEBHOOK_SECRET", webhook_secret)
    monkeypatch.setenv("STRIPE_PRICE_BASIC_MONTHLY", "price_basic_monthly")
    monkeypatch.setenv("STRIPE_PRICE_BASIC_YEARLY", "price_basic_yearly")


def _patch_stripe_api(monkeypatch, *, session_id: str = "cs_test_123", session_url: str = "https://checkout.stripe.test/cs_test_123"):
    import stripe  # local import so the dependency is optional outside tests

    calls = {"customer_create": 0, "session_create": 0, "portal_create": 0}

    def fake_customer_create(**_kwargs):
        calls["customer_create"] += 1
        return SimpleNamespace(id="cus_test_123")

    def fake_session_create(**_kwargs):
        calls["session_create"] += 1
        return SimpleNamespace(id=session_id, url=session_url)

    def fake_portal_create(**_kwargs):
        calls["portal_create"] += 1
        return SimpleNamespace(url="https://billing.stripe.test/portal")

    monkeypatch.setattr(stripe.Customer, "create", staticmethod(fake_customer_create))
    monkeypatch.setattr(stripe.checkout.Session, "create", staticmethod(fake_session_create))
    monkeypatch.setattr(stripe.billing_portal.Session, "create", staticmethod(fake_portal_create))

    return calls


class TestStripeCheckoutIdempotency:
    def test_double_submit_checkout_is_idempotent(self, client, auth_headers, monkeypatch, test_user, db):
        _configure_stripe_env(monkeypatch)
        calls = _patch_stripe_api(monkeypatch)

        # First request should create the Stripe customer + checkout session.
        first = client.post(
            "/api/payments/stripe/create-checkout-session",
            json={"plan_id": "basic", "billing_cycle": "monthly"},
            headers=auth_headers,
        )
        assert first.status_code == 200, first.text
        first_data = first.json()
        assert first_data.get("checkout_url")
        assert first_data.get("session_id")
        assert first_data.get("replayed") in (False, None)

        # Second request with the same payload in the idempotency window should replay.
        second = client.post(
            "/api/payments/stripe/create-checkout-session",
            json={"plan_id": "basic", "billing_cycle": "monthly"},
            headers=auth_headers,
        )
        assert second.status_code == 200, second.text
        second_data = second.json()
        assert second_data.get("session_id") == first_data.get("session_id")
        assert second_data.get("checkout_url") == first_data.get("checkout_url")
        assert second_data.get("replayed") is True

        assert calls["customer_create"] == 1
        assert calls["session_create"] == 1

    def test_cookie_auth_requires_csrf_header(self, client, monkeypatch):
        _configure_stripe_env(monkeypatch)
        _patch_stripe_api(monkeypatch)

        email = "csrfpay@example.com"
        password = "SecurePass123"
        reg = client.post(
            "/api/auth/register",
            json={"email": email, "password": password, "password_confirm": password},
        )
        assert reg.status_code in (200, 201), reg.text

        # Cookie-auth POST without CSRF should be rejected.
        no_csrf = client.post(
            "/api/payments/stripe/create-checkout-session",
            json={"plan_id": "basic", "billing_cycle": "monthly"},
        )
        assert no_csrf.status_code == 403, no_csrf.text
        body = no_csrf.json()
        assert body["error"]["code"] == "csrf_failed"

        csrf_cookie = client.cookies.get("csrf_token")
        assert csrf_cookie

        ok = client.post(
            "/api/payments/stripe/create-checkout-session",
            json={"plan_id": "basic", "billing_cycle": "monthly"},
            headers={"X-CSRF-Token": csrf_cookie},
        )
        assert ok.status_code == 200, ok.text


class TestStripeWebhookVerification:
    def test_missing_signature_rejected(self, client, monkeypatch):
        _configure_stripe_env(monkeypatch)
        payload = json.dumps({"id": "evt_1", "type": "customer.subscription.created", "data": {"object": {}}}).encode("utf-8")
        resp = client.post("/api/payments/stripe/webhook", data=payload)
        assert resp.status_code == 400
        body = resp.json()
        assert body["error"]["code"] in ("bad_request", "validation_error")

    def test_invalid_signature_rejected(self, client, monkeypatch):
        _configure_stripe_env(monkeypatch, webhook_secret="whsec_correct")
        payload = json.dumps({"id": "evt_1", "type": "customer.subscription.created", "data": {"object": {}}}).encode("utf-8")
        sig = _stripe_signature_header(payload=payload, secret="whsec_wrong")
        resp = client.post("/api/payments/stripe/webhook", data=payload, headers={"Stripe-Signature": sig})
        assert resp.status_code == 400
        body = resp.json()
        assert body["error"]["code"] in ("bad_request", "validation_error")


class TestStripeWebhookSecurityAndState:
    def test_webhook_creates_subscription_and_updates_user_status(self, client, monkeypatch, test_user, db):
        _configure_stripe_env(monkeypatch)

        # Ensure we can map the customer -> user safely.
        test_user.stripe_customer_id = "cus_test_123"
        db.add(test_user)
        db.commit()

        now = int(time.time())
        subscription_obj = {
            "id": "sub_test_123",
            "customer": "cus_test_123",
            "status": "active",
            "current_period_start": now,
            "current_period_end": now + 30 * 24 * 3600,
            "cancel_at_period_end": False,
            "items": {"data": [{"price": {"id": "price_basic_monthly"}}]},
            "metadata": {
                "securewave_user_id": str(test_user.id),
                "plan_id": "basic",
                "billing_cycle": "monthly",
            },
        }
        event = {"id": "evt_sub_create_1", "type": "customer.subscription.created", "data": {"object": subscription_obj}}
        payload = json.dumps(event, separators=(",", ":"), sort_keys=True).encode("utf-8")
        sig = _stripe_signature_header(payload=payload, secret="whsec_test_secret")

        resp = client.post("/api/payments/stripe/webhook", data=payload, headers={"Stripe-Signature": sig})
        assert resp.status_code == 200, resp.text

        from models.subscription import Subscription
        sub = db.query(Subscription).filter_by(stripe_subscription_id="sub_test_123").first()
        assert sub is not None
        assert sub.status == "active"
        assert sub.plan_id == "basic"

        db.refresh(test_user)
        assert test_user.subscription_status == "active"

    def test_replayed_webhook_is_deduped(self, client, monkeypatch, test_user, db):
        _configure_stripe_env(monkeypatch)
        test_user.stripe_customer_id = "cus_test_123"
        db.add(test_user)
        db.commit()

        now = int(time.time())
        subscription_obj = {
            "id": "sub_test_replay",
            "customer": "cus_test_123",
            "status": "active",
            "current_period_start": now,
            "current_period_end": now + 30 * 24 * 3600,
            "items": {"data": [{"price": {"id": "price_basic_monthly"}}]},
            "metadata": {"securewave_user_id": str(test_user.id), "plan_id": "basic", "billing_cycle": "monthly"},
        }
        event = {"id": "evt_replay_1", "type": "customer.subscription.created", "data": {"object": subscription_obj}}
        payload = json.dumps(event, separators=(",", ":"), sort_keys=True).encode("utf-8")
        sig = _stripe_signature_header(payload=payload, secret="whsec_test_secret")

        first = client.post("/api/payments/stripe/webhook", data=payload, headers={"Stripe-Signature": sig})
        assert first.status_code == 200
        second = client.post("/api/payments/stripe/webhook", data=payload, headers={"Stripe-Signature": sig})
        assert second.status_code == 200

        from models.subscription import Subscription
        assert db.query(Subscription).filter_by(stripe_subscription_id="sub_test_replay").count() == 1

        from models.webhook_event_receipt import WebhookEventReceipt
        receipt = db.query(WebhookEventReceipt).filter_by(provider="stripe", event_id="evt_replay_1").first()
        assert receipt is not None
        assert receipt.attempt_count >= 2
        assert receipt.status in ("processed", "ignored")

    def test_mismatched_customer_id_is_ignored(self, client, monkeypatch, test_user, db):
        _configure_stripe_env(monkeypatch)

        test_user.stripe_customer_id = "cus_expected"
        db.add(test_user)
        db.commit()

        now = int(time.time())
        subscription_obj = {
            "id": "sub_test_mismatch",
            "customer": "cus_other",
            "status": "active",
            "current_period_start": now,
            "current_period_end": now + 30 * 24 * 3600,
            "items": {"data": [{"price": {"id": "price_basic_monthly"}}]},
            "metadata": {"securewave_user_id": str(test_user.id), "plan_id": "basic", "billing_cycle": "monthly"},
        }
        event = {"id": "evt_mismatch_1", "type": "customer.subscription.created", "data": {"object": subscription_obj}}
        payload = json.dumps(event, separators=(",", ":"), sort_keys=True).encode("utf-8")
        sig = _stripe_signature_header(payload=payload, secret="whsec_test_secret")

        resp = client.post("/api/payments/stripe/webhook", data=payload, headers={"Stripe-Signature": sig})
        assert resp.status_code == 200

        from models.subscription import Subscription
        assert db.query(Subscription).filter_by(stripe_subscription_id="sub_test_mismatch").count() == 0

    def test_invalid_event_type_is_ignored(self, client, monkeypatch):
        _configure_stripe_env(monkeypatch)
        event = {"id": "evt_invalid_type_1", "type": "totally.invalid", "data": {"object": {}}}
        payload = json.dumps(event, separators=(",", ":"), sort_keys=True).encode("utf-8")
        sig = _stripe_signature_header(payload=payload, secret="whsec_test_secret")
        resp = client.post("/api/payments/stripe/webhook", data=payload, headers={"Stripe-Signature": sig})
        assert resp.status_code == 200

    def test_subscription_state_transitions(self, client, monkeypatch, test_user, db):
        _configure_stripe_env(monkeypatch)
        test_user.stripe_customer_id = "cus_test_123"
        db.add(test_user)
        db.commit()

        now = int(time.time())
        base_sub = {
            "id": "sub_transition_1",
            "customer": "cus_test_123",
            "status": "active",
            "current_period_start": now,
            "current_period_end": now + 30 * 24 * 3600,
            "items": {"data": [{"price": {"id": "price_basic_monthly"}}]},
            "metadata": {"securewave_user_id": str(test_user.id), "plan_id": "basic", "billing_cycle": "monthly"},
        }

        create_event = {"id": "evt_trans_create", "type": "customer.subscription.created", "data": {"object": base_sub}}
        create_payload = json.dumps(create_event, separators=(",", ":"), sort_keys=True).encode("utf-8")
        create_sig = _stripe_signature_header(payload=create_payload, secret="whsec_test_secret")
        assert client.post("/api/payments/stripe/webhook", data=create_payload, headers={"Stripe-Signature": create_sig}).status_code == 200

        # Past due
        updated = dict(base_sub)
        updated["status"] = "past_due"
        update_event = {"id": "evt_trans_update", "type": "customer.subscription.updated", "data": {"object": updated}}
        update_payload = json.dumps(update_event, separators=(",", ":"), sort_keys=True).encode("utf-8")
        update_sig = _stripe_signature_header(payload=update_payload, secret="whsec_test_secret")
        assert client.post("/api/payments/stripe/webhook", data=update_payload, headers={"Stripe-Signature": update_sig}).status_code == 200

        from models.subscription import Subscription
        sub = db.query(Subscription).filter_by(stripe_subscription_id="sub_transition_1").first()
        assert sub is not None
        assert sub.status == "past_due"

        db.refresh(test_user)
        assert test_user.subscription_status == "basic"

        # Deleted
        delete_event = {"id": "evt_trans_delete", "type": "customer.subscription.deleted", "data": {"object": {"id": "sub_transition_1"}}}
        delete_payload = json.dumps(delete_event, separators=(",", ":"), sort_keys=True).encode("utf-8")
        delete_sig = _stripe_signature_header(payload=delete_payload, secret="whsec_test_secret")
        assert client.post("/api/payments/stripe/webhook", data=delete_payload, headers={"Stripe-Signature": delete_sig}).status_code == 200

        sub = db.query(Subscription).filter_by(stripe_subscription_id="sub_transition_1").first()
        assert sub is not None
        assert sub.status == "canceled"
