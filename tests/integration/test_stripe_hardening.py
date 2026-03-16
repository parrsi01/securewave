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
    monkeypatch.setenv("STRIPE_PRICE_PREMIUM_MONTHLY", "price_premium_monthly")
    monkeypatch.setenv("STRIPE_PRICE_PREMIUM_YEARLY", "price_premium_yearly")


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
        password = "SecurePass123!"
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

    def test_replayed_timestamp_signature_rejected(self, client, monkeypatch):
        _configure_stripe_env(monkeypatch, webhook_secret="whsec_test_secret")
        # Tight tolerance so an old timestamp is rejected (webhook replay protection at the signing layer).
        monkeypatch.setenv("STRIPE_WEBHOOK_TOLERANCE_SECONDS", "5")

        payload = json.dumps({"id": "evt_old_ts", "type": "customer.subscription.created", "data": {"object": {}}}).encode("utf-8")
        sig = _stripe_signature_header(payload=payload, secret="whsec_test_secret", timestamp=int(time.time()) - 3600)
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

    def test_upgrade_downgrade_plan_transitions_follow_price_id(self, client, monkeypatch, test_user, db):
        _configure_stripe_env(monkeypatch)
        test_user.stripe_customer_id = "cus_test_123"
        db.add(test_user)
        db.commit()

        now = int(time.time())
        sub_id = "sub_upgrade_path_1"

        # Create subscription on basic/monthly.
        created = {
            "id": sub_id,
            "customer": "cus_test_123",
            "status": "active",
            "current_period_start": now,
            "current_period_end": now + 30 * 24 * 3600,
            "items": {"data": [{"price": {"id": "price_basic_monthly"}}]},
            "metadata": {"securewave_user_id": str(test_user.id), "plan_id": "basic", "billing_cycle": "monthly"},
        }
        create_event = {"id": "evt_upgrade_create", "type": "customer.subscription.created", "data": {"object": created}}
        create_payload = json.dumps(create_event, separators=(",", ":"), sort_keys=True).encode("utf-8")
        create_sig = _stripe_signature_header(payload=create_payload, secret="whsec_test_secret")
        assert client.post("/api/payments/stripe/webhook", data=create_payload, headers={"Stripe-Signature": create_sig}).status_code == 200

        from models.subscription import Subscription
        sub = db.query(Subscription).filter_by(stripe_subscription_id=sub_id).first()
        assert sub is not None
        assert sub.plan_id == "basic"

        # Upgrade via portal: Stripe price changes but custom metadata often does not.
        upgraded = dict(created)
        upgraded["items"] = {"data": [{"price": {"id": "price_premium_monthly"}}]}
        upgraded["metadata"] = dict(created["metadata"])
        upgraded["metadata"]["plan_id"] = "basic"  # stale on purpose; handler should follow price_id mapping.

        upgrade_event = {"id": "evt_upgrade_update", "type": "customer.subscription.updated", "data": {"object": upgraded}}
        upgrade_payload = json.dumps(upgrade_event, separators=(",", ":"), sort_keys=True).encode("utf-8")
        upgrade_sig = _stripe_signature_header(payload=upgrade_payload, secret="whsec_test_secret")
        assert client.post("/api/payments/stripe/webhook", data=upgrade_payload, headers={"Stripe-Signature": upgrade_sig}).status_code == 200

        sub = db.query(Subscription).filter_by(stripe_subscription_id=sub_id).first()
        assert sub is not None
        assert sub.plan_id == "premium"

        # Downgrade back to basic.
        downgraded = dict(upgraded)
        downgraded["items"] = {"data": [{"price": {"id": "price_basic_monthly"}}]}
        downgrade_event = {"id": "evt_upgrade_downgrade", "type": "customer.subscription.updated", "data": {"object": downgraded}}
        downgrade_payload = json.dumps(downgrade_event, separators=(",", ":"), sort_keys=True).encode("utf-8")
        downgrade_sig = _stripe_signature_header(payload=downgrade_payload, secret="whsec_test_secret")
        assert client.post("/api/payments/stripe/webhook", data=downgrade_payload, headers={"Stripe-Signature": downgrade_sig}).status_code == 200

        sub = db.query(Subscription).filter_by(stripe_subscription_id=sub_id).first()
        assert sub is not None
        assert sub.plan_id == "basic"

    def test_replayed_event_payload_mismatch_is_rejected(self, client, monkeypatch, test_user, db):
        _configure_stripe_env(monkeypatch)
        test_user.stripe_customer_id = "cus_test_123"
        db.add(test_user)
        db.commit()

        now = int(time.time())
        base_event = {
            "id": "evt_payload_mismatch",
            "type": "customer.subscription.created",
            "created": now,
            "data": {
                "object": {
                    "id": "sub_payload_mismatch",
                    "customer": "cus_test_123",
                    "status": "active",
                    "current_period_start": now,
                    "current_period_end": now + 30 * 24 * 3600,
                    "items": {"data": [{"price": {"id": "price_basic_monthly"}}]},
                    "metadata": {"securewave_user_id": str(test_user.id), "plan_id": "basic", "billing_cycle": "monthly"},
                }
            },
        }
        payload_1 = json.dumps(base_event, separators=(",", ":"), sort_keys=True).encode("utf-8")
        sig_1 = _stripe_signature_header(payload=payload_1, secret="whsec_test_secret")
        first = client.post("/api/payments/stripe/webhook", data=payload_1, headers={"Stripe-Signature": sig_1})
        assert first.status_code == 200, first.text

        # Replay same event_id with modified payload should be rejected.
        tampered_event = dict(base_event)
        tampered_obj = dict(base_event["data"]["object"])
        tampered_obj["status"] = "past_due"
        tampered_event["data"] = {"object": tampered_obj}
        payload_2 = json.dumps(tampered_event, separators=(",", ":"), sort_keys=True).encode("utf-8")
        sig_2 = _stripe_signature_header(payload=payload_2, secret="whsec_test_secret")
        second = client.post("/api/payments/stripe/webhook", data=payload_2, headers={"Stripe-Signature": sig_2})
        assert second.status_code == 400

    def test_out_of_order_subscription_update_is_ignored(self, client, monkeypatch, test_user, db):
        _configure_stripe_env(monkeypatch)
        test_user.stripe_customer_id = "cus_test_123"
        db.add(test_user)
        db.commit()

        t1 = int(time.time())
        t2 = t1 + 100
        t_stale = t1 + 50
        sub_id = "sub_ordering_1"
        base = {
            "id": sub_id,
            "customer": "cus_test_123",
            "status": "active",
            "current_period_start": t1,
            "current_period_end": t1 + 30 * 24 * 3600,
            "items": {"data": [{"price": {"id": "price_basic_monthly"}}]},
            "metadata": {"securewave_user_id": str(test_user.id), "plan_id": "basic", "billing_cycle": "monthly"},
        }

        create_evt = {"id": "evt_order_create", "type": "customer.subscription.created", "created": t1, "data": {"object": base}}
        create_payload = json.dumps(create_evt, separators=(",", ":"), sort_keys=True).encode("utf-8")
        create_sig = _stripe_signature_header(payload=create_payload, secret="whsec_test_secret")
        assert client.post("/api/payments/stripe/webhook", data=create_payload, headers={"Stripe-Signature": create_sig}).status_code == 200

        newer = dict(base)
        newer["status"] = "active"
        update_new_evt = {"id": "evt_order_new", "type": "customer.subscription.updated", "created": t2, "data": {"object": newer}}
        update_new_payload = json.dumps(update_new_evt, separators=(",", ":"), sort_keys=True).encode("utf-8")
        update_new_sig = _stripe_signature_header(payload=update_new_payload, secret="whsec_test_secret")
        assert client.post("/api/payments/stripe/webhook", data=update_new_payload, headers={"Stripe-Signature": update_new_sig}).status_code == 200

        # Stale event arrives after newer one; should be ignored by state machine.
        stale = dict(base)
        stale["status"] = "past_due"
        update_stale_evt = {"id": "evt_order_stale", "type": "customer.subscription.updated", "created": t_stale, "data": {"object": stale}}
        update_stale_payload = json.dumps(update_stale_evt, separators=(",", ":"), sort_keys=True).encode("utf-8")
        update_stale_sig = _stripe_signature_header(payload=update_stale_payload, secret="whsec_test_secret")
        assert client.post("/api/payments/stripe/webhook", data=update_stale_payload, headers={"Stripe-Signature": update_stale_sig}).status_code == 200

        from models.subscription import Subscription
        sub = db.query(Subscription).filter_by(stripe_subscription_id=sub_id).first()
        assert sub is not None
        assert sub.status == "active"

    def test_payment_intent_expired_card_marks_unpaid(self, client, monkeypatch, test_user, db):
        _configure_stripe_env(monkeypatch)
        test_user.stripe_customer_id = "cus_test_123"
        db.add(test_user)
        db.commit()

        from models.subscription import Subscription

        sub = Subscription(
            user_id=test_user.id,
            plan_id="basic",
            plan_name="Basic Plan",
            provider="stripe",
            status="active",
            stripe_customer_id="cus_test_123",
            stripe_subscription_id="sub_expired_card_1",
            amount=9.99,
            currency="USD",
            billing_cycle="monthly",
        )
        db.add(sub)
        db.commit()

        event = {
            "id": "evt_pi_expired",
            "type": "payment_intent.payment_failed",
            "created": int(time.time()),
            "data": {
                "object": {
                    "id": "pi_expired_1",
                    "metadata": {"stripe_subscription_id": "sub_expired_card_1"},
                    "last_payment_error": {"code": "expired_card", "decline_code": "expired_card"},
                }
            },
        }
        payload = json.dumps(event, separators=(",", ":"), sort_keys=True).encode("utf-8")
        sig = _stripe_signature_header(payload=payload, secret="whsec_test_secret")
        resp = client.post("/api/payments/stripe/webhook", data=payload, headers={"Stripe-Signature": sig})
        assert resp.status_code == 200, resp.text

        db.refresh(sub)
        assert sub.status == "unpaid"
        assert sub.last_payment_status == "failed"
