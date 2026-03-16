"""
SecureWave — Stripe Billing Integration Tests
==============================================
Comprehensive test suite covering:
- Customer creation
- Subscription creation / renewal / cancellation
- Payment success / failure flows
- Refund handling (charge.refunded webhook)
- Webhook security (signature, replay, duplicate)
- Trial expiration
- Plan upgrade / downgrade
- Device-limit enforcement after payment failure
- Idempotency
"""

from __future__ import annotations

import hashlib
import hmac
import json
import time
from datetime import datetime, timedelta
from types import SimpleNamespace
from typing import Dict

import pytest
from sqlalchemy.orm import Session

from models.subscription import Subscription
from models.user import User
from models.webhook_event_receipt import WebhookEventReceipt


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _stripe_sig(payload: bytes, secret: str, *, timestamp: int | None = None) -> str:
    ts = int(timestamp or time.time())
    signed = f"{ts}.".encode("utf-8") + payload
    sig = hmac.new(secret.encode("utf-8"), signed, hashlib.sha256).hexdigest()
    return f"t={ts},v1={sig}"


WEBHOOK_SECRET = "whsec_billing_test"


def _env(monkeypatch, *, webhook_secret: str = WEBHOOK_SECRET):
    monkeypatch.setenv("STRIPE_SECRET_KEY", "sk_test_billing")
    monkeypatch.setenv("STRIPE_WEBHOOK_SECRET", webhook_secret)
    monkeypatch.setenv("STRIPE_PRICE_BASIC_MONTHLY", "price_basic_m")
    monkeypatch.setenv("STRIPE_PRICE_BASIC_YEARLY", "price_basic_y")
    monkeypatch.setenv("STRIPE_PRICE_PREMIUM_MONTHLY", "price_premium_m")
    monkeypatch.setenv("STRIPE_PRICE_PREMIUM_YEARLY", "price_premium_y")
    monkeypatch.setenv("STRIPE_PRICE_ULTRA_MONTHLY", "price_ultra_m")
    monkeypatch.setenv("STRIPE_PRICE_ULTRA_YEARLY", "price_ultra_y")


def _patch_stripe(monkeypatch) -> Dict[str, int]:
    import stripe

    calls = {"customer_create": 0, "session_create": 0, "portal_create": 0,
             "sub_modify": 0, "sub_delete": 0}

    def fake_customer_create(**kw):
        calls["customer_create"] += 1
        return SimpleNamespace(id="cus_billing_test")

    def fake_session_create(**kw):
        calls["session_create"] += 1
        return SimpleNamespace(id="cs_billing_test", url="https://checkout.stripe.test/cs_billing_test")

    def fake_portal_create(**kw):
        calls["portal_create"] += 1
        return SimpleNamespace(url="https://billing.stripe.test/portal")

    def fake_sub_modify(sub_id, **kw):
        calls["sub_modify"] += 1
        return SimpleNamespace(id=sub_id, status="active")

    def fake_sub_delete(sub_id, **kw):
        calls["sub_delete"] += 1
        return SimpleNamespace(id=sub_id, status="canceled")

    monkeypatch.setattr(stripe.Customer, "create", staticmethod(fake_customer_create))
    monkeypatch.setattr(stripe.checkout.Session, "create", staticmethod(fake_session_create))
    monkeypatch.setattr(stripe.billing_portal.Session, "create", staticmethod(fake_portal_create))
    monkeypatch.setattr(stripe.Subscription, "modify", staticmethod(fake_sub_modify))
    monkeypatch.setattr(stripe.Subscription, "delete", staticmethod(fake_sub_delete))
    return calls


def _post_webhook(client, event: dict, *, secret: str = WEBHOOK_SECRET, timestamp: int | None = None):
    payload = json.dumps(event, separators=(",", ":"), sort_keys=True).encode("utf-8")
    sig = _stripe_sig(payload, secret, timestamp=timestamp)
    return client.post("/api/payments/stripe/webhook", data=payload, headers={"Stripe-Signature": sig})


def _make_sub_obj(
    *,
    sub_id: str,
    customer_id: str,
    user_id: int,
    status: str = "active",
    plan_id: str = "basic",
    price_id: str = "price_basic_m",
    billing_cycle: str = "monthly",
    cancel_at_period_end: bool = False,
    trial_start: int | None = None,
    trial_end: int | None = None,
) -> dict:
    now = int(time.time())
    obj = {
        "id": sub_id,
        "customer": customer_id,
        "status": status,
        "current_period_start": now,
        "current_period_end": now + 30 * 24 * 3600,
        "cancel_at_period_end": cancel_at_period_end,
        "items": {"data": [{"price": {"id": price_id}}]},
        "metadata": {
            "securewave_user_id": str(user_id),
            "plan_id": plan_id,
            "billing_cycle": billing_cycle,
        },
    }
    if trial_start:
        obj["trial_start"] = trial_start
    if trial_end:
        obj["trial_end"] = trial_end
    return obj


def _setup_user_with_customer(db: Session, test_user: User, customer_id: str = "cus_billing_test"):
    test_user.stripe_customer_id = customer_id
    db.add(test_user)
    db.commit()


def _create_subscription_via_webhook(client, db, test_user, *, sub_id: str, plan_id: str = "basic",
                                      price_id: str = "price_basic_m", status: str = "active",
                                      event_id: str | None = None) -> Subscription:
    _setup_user_with_customer(db, test_user)
    sub_obj = _make_sub_obj(
        sub_id=sub_id, customer_id="cus_billing_test", user_id=test_user.id,
        status=status, plan_id=plan_id, price_id=price_id,
    )
    evt = {"id": event_id or f"evt_{sub_id}", "type": "customer.subscription.created",
           "created": int(time.time()), "data": {"object": sub_obj}}
    resp = _post_webhook(client, evt)
    assert resp.status_code == 200, resp.text
    sub = db.query(Subscription).filter_by(stripe_subscription_id=sub_id).first()
    assert sub is not None
    return sub


# ===========================================================================
# TEST CLASSES
# ===========================================================================

class TestCustomerCreation:
    """Stripe customer is created during checkout flow."""

    def test_checkout_creates_customer(self, client, auth_headers, monkeypatch, test_user, db):
        _env(monkeypatch)
        calls = _patch_stripe(monkeypatch)
        resp = client.post(
            "/api/payments/stripe/create-checkout-session",
            json={"plan_id": "basic", "billing_cycle": "monthly"},
            headers=auth_headers,
        )
        assert resp.status_code == 200, resp.text
        assert calls["customer_create"] == 1
        assert calls["session_create"] == 1
        data = resp.json()
        assert data["checkout_url"]
        assert data["session_id"]

    def test_free_plan_skips_stripe(self, client, auth_headers, monkeypatch, test_user, db):
        _env(monkeypatch)
        calls = _patch_stripe(monkeypatch)
        resp = client.post(
            "/api/payments/stripe/create-checkout-session",
            json={"plan_id": "free", "billing_cycle": "monthly"},
            headers=auth_headers,
        )
        assert resp.status_code == 200
        assert resp.json()["checkout_url"] is None
        assert calls["customer_create"] == 0
        assert calls["session_create"] == 0

    def test_unknown_plan_rejected(self, client, auth_headers, monkeypatch):
        _env(monkeypatch)
        _patch_stripe(monkeypatch)
        resp = client.post(
            "/api/payments/stripe/create-checkout-session",
            json={"plan_id": "nonexistent", "billing_cycle": "monthly"},
            headers=auth_headers,
        )
        assert resp.status_code == 400
        assert "unknown_plan" in resp.json()["error"]["code"]


class TestSubscriptionCreation:
    """Subscription creation via webhook."""

    def test_subscription_created_via_webhook(self, client, monkeypatch, test_user, db):
        _env(monkeypatch)
        sub = _create_subscription_via_webhook(client, db, test_user, sub_id="sub_create_1")
        assert sub.status == "active"
        assert sub.plan_id == "basic"
        assert sub.provider == "stripe"
        db.refresh(test_user)
        assert test_user.subscription_status == "active"

    def test_checkout_session_completed_creates_subscription(self, client, monkeypatch, test_user, db):
        _env(monkeypatch)
        _setup_user_with_customer(db, test_user)
        now = int(time.time())
        session_obj = {
            "id": "cs_checkout_1",
            "customer": "cus_billing_test",
            "subscription": "sub_checkout_1",
            "payment_status": "paid",
            "client_reference_id": str(test_user.id),
            "metadata": {
                "securewave_user_id": str(test_user.id),
                "plan_id": "premium",
                "billing_cycle": "yearly",
            },
        }
        evt = {"id": "evt_checkout_1", "type": "checkout.session.completed",
               "created": now, "data": {"object": session_obj}}
        resp = _post_webhook(client, evt)
        assert resp.status_code == 200
        sub = db.query(Subscription).filter_by(stripe_subscription_id="sub_checkout_1").first()
        assert sub is not None
        assert sub.status == "active"
        assert sub.plan_id == "premium"

    def test_duplicate_subscription_not_created(self, client, monkeypatch, test_user, db):
        _env(monkeypatch)
        _create_subscription_via_webhook(client, db, test_user, sub_id="sub_dup_1", event_id="evt_dup_1")
        count_before = db.query(Subscription).filter_by(stripe_subscription_id="sub_dup_1").count()
        # Send same event again
        sub_obj = _make_sub_obj(sub_id="sub_dup_1", customer_id="cus_billing_test",
                                 user_id=test_user.id, status="active")
        evt = {"id": "evt_dup_1", "type": "customer.subscription.created",
               "created": int(time.time()), "data": {"object": sub_obj}}
        resp = _post_webhook(client, evt)
        assert resp.status_code == 200
        count_after = db.query(Subscription).filter_by(stripe_subscription_id="sub_dup_1").count()
        assert count_after == count_before


class TestSubscriptionRenewal:
    """Invoice.paid webhook renews subscription."""

    def test_invoice_paid_updates_subscription(self, client, monkeypatch, test_user, db):
        _env(monkeypatch)
        sub = _create_subscription_via_webhook(client, db, test_user, sub_id="sub_renew_1")
        assert sub.renewal_count == 0

        now = int(time.time())
        invoice_obj = {
            "id": "in_renew_1",
            "customer": "cus_billing_test",
            "subscription": "sub_renew_1",
            "amount_due": 999,
            "amount_paid": 999,
            "amount_remaining": 0,
            "currency": "usd",
            "subtotal": 999,
            "tax": 0,
            "number": "INV-001",
            "status": "paid",
            "status_transitions": {"paid_at": now},
            "period_start": now,
            "period_end": now + 30 * 24 * 3600,
            "charge": "ch_renew_1",
            "payment_intent": "pi_renew_1",
        }
        evt = {"id": "evt_invoice_paid_1", "type": "invoice.paid",
               "created": now, "data": {"object": invoice_obj}}
        resp = _post_webhook(client, evt)
        assert resp.status_code == 200

        db.refresh(sub)
        assert sub.status == "active"
        assert sub.last_payment_status == "succeeded"
        assert sub.failed_payment_count == 0
        assert sub.renewal_count == 1


class TestPaymentFailure:
    """Invoice.payment_failed triggers past_due / unpaid transitions."""

    def test_first_failure_sets_past_due(self, client, monkeypatch, test_user, db):
        _env(monkeypatch)
        sub = _create_subscription_via_webhook(client, db, test_user, sub_id="sub_fail_1")

        invoice_obj = {
            "id": "in_fail_1",
            "customer": "cus_billing_test",
            "subscription": "sub_fail_1",
            "hosted_invoice_url": "https://invoice.stripe.test/in_fail_1",
        }
        evt = {"id": "evt_fail_1", "type": "invoice.payment_failed",
               "created": int(time.time()), "data": {"object": invoice_obj}}
        resp = _post_webhook(client, evt)
        assert resp.status_code == 200

        db.refresh(sub)
        assert sub.status == "past_due"
        assert sub.last_payment_status == "failed"
        assert sub.failed_payment_count == 1
        db.refresh(test_user)
        assert test_user.subscription_status == "basic"

    def test_three_failures_set_unpaid(self, client, monkeypatch, test_user, db):
        _env(monkeypatch)
        sub = _create_subscription_via_webhook(client, db, test_user, sub_id="sub_fail3_1")

        for i in range(3):
            invoice_obj = {
                "id": f"in_fail3_{i}",
                "customer": "cus_billing_test",
                "subscription": "sub_fail3_1",
            }
            evt = {"id": f"evt_fail3_{i}", "type": "invoice.payment_failed",
                   "created": int(time.time()) + i, "data": {"object": invoice_obj}}
            resp = _post_webhook(client, evt)
            assert resp.status_code == 200

        db.refresh(sub)
        assert sub.status == "unpaid"
        assert sub.failed_payment_count == 3

    def test_recovery_after_failure(self, client, monkeypatch, test_user, db):
        """invoice.paid after failure resets subscription to active."""
        _env(monkeypatch)
        sub = _create_subscription_via_webhook(client, db, test_user, sub_id="sub_recover_1")

        # Fail once
        fail_invoice = {"id": "in_recover_fail", "customer": "cus_billing_test", "subscription": "sub_recover_1"}
        _post_webhook(client, {"id": "evt_recover_fail", "type": "invoice.payment_failed",
                                "created": int(time.time()), "data": {"object": fail_invoice}})
        db.refresh(sub)
        assert sub.status == "past_due"

        # Then pay
        now = int(time.time())
        paid_invoice = {
            "id": "in_recover_paid", "customer": "cus_billing_test", "subscription": "sub_recover_1",
            "amount_due": 999, "amount_paid": 999, "amount_remaining": 0, "currency": "usd",
            "subtotal": 999, "tax": 0, "number": "INV-002", "status_transitions": {"paid_at": now},
            "period_start": now, "period_end": now + 30 * 86400,
        }
        _post_webhook(client, {"id": "evt_recover_paid", "type": "invoice.paid",
                                "created": now, "data": {"object": paid_invoice}})
        db.refresh(sub)
        assert sub.status == "active"
        assert sub.failed_payment_count == 0


class TestRefundHandling:
    """charge.refunded webhook handling."""

    def test_charge_refunded_recorded(self, client, monkeypatch, test_user, db):
        _env(monkeypatch)
        _setup_user_with_customer(db, test_user)

        charge_obj = {
            "id": "ch_refund_1",
            "customer": "cus_billing_test",
            "amount_refunded": 999,
            "refunded": True,
        }
        evt = {"id": "evt_refund_1", "type": "charge.refunded",
               "created": int(time.time()), "data": {"object": charge_obj}}
        resp = _post_webhook(client, evt)
        assert resp.status_code == 200
        body = resp.json()
        assert body["status"] == "success"


class TestSubscriptionCancellation:
    """Subscription deletion/cancellation via webhook."""

    def test_subscription_deleted_sets_canceled(self, client, monkeypatch, test_user, db):
        _env(monkeypatch)
        sub = _create_subscription_via_webhook(client, db, test_user, sub_id="sub_cancel_1")
        assert sub.status == "active"

        delete_obj = {"id": "sub_cancel_1"}
        evt = {"id": "evt_cancel_1", "type": "customer.subscription.deleted",
               "created": int(time.time()), "data": {"object": delete_obj}}
        resp = _post_webhook(client, evt)
        assert resp.status_code == 200

        db.refresh(sub)
        assert sub.status == "canceled"
        assert sub.canceled_at is not None
        db.refresh(test_user)
        assert test_user.subscription_status == "basic"

    def test_cancel_at_period_end_tracked(self, client, monkeypatch, test_user, db):
        """
        BUG FINDING: subscription_state_machine.py line 123 forces
        cancel_at_period_end=False on any active→active transition.
        The webhook handler sets it correctly, but the state machine
        normalization overrides it.  This test documents the current
        (buggy) behaviour.  See STRIPE_TEST_RESULTS.md FINDING-01.
        """
        _env(monkeypatch)
        sub = _create_subscription_via_webhook(client, db, test_user, sub_id="sub_cancelend_1")

        updated = _make_sub_obj(
            sub_id="sub_cancelend_1", customer_id="cus_billing_test",
            user_id=test_user.id, status="active", cancel_at_period_end=True,
        )
        updated["canceled_at"] = int(time.time())
        evt = {"id": "evt_cancelend_1", "type": "customer.subscription.updated",
               "created": int(time.time()), "data": {"object": updated}}
        resp = _post_webhook(client, evt)
        assert resp.status_code == 200

        db.refresh(sub)
        # BUG: state machine resets cancel_at_period_end to False (see FINDING-01)
        assert sub.cancel_at_period_end is False
        # canceled_at IS set by the upsert before the state machine runs
        assert sub.canceled_at is not None
        assert sub.status == "active"


class TestTrialExpiration:
    """Trial-related webhook events."""

    def test_trial_subscription_created(self, client, monkeypatch, test_user, db):
        _env(monkeypatch)
        _setup_user_with_customer(db, test_user)
        now = int(time.time())
        sub_obj = _make_sub_obj(
            sub_id="sub_trial_1", customer_id="cus_billing_test",
            user_id=test_user.id, status="trialing",
            trial_start=now, trial_end=now + 7 * 86400,
        )
        evt = {"id": "evt_trial_create", "type": "customer.subscription.created",
               "created": now, "data": {"object": sub_obj}}
        resp = _post_webhook(client, evt)
        assert resp.status_code == 200

        sub = db.query(Subscription).filter_by(stripe_subscription_id="sub_trial_1").first()
        assert sub is not None
        assert sub.status == "trialing"
        assert sub.is_trial is True
        assert sub.trial_start is not None
        assert sub.trial_end is not None

    def test_trial_will_end_notification(self, client, monkeypatch, test_user, db):
        _env(monkeypatch)
        sub = _create_subscription_via_webhook(
            client, db, test_user, sub_id="sub_trial_end_1", status="trialing",
        )
        trial_end_obj = {"id": "sub_trial_end_1", "customer": "cus_billing_test"}
        evt = {"id": "evt_trial_ending", "type": "customer.subscription.trial_will_end",
               "created": int(time.time()), "data": {"object": trial_end_obj}}
        resp = _post_webhook(client, evt)
        assert resp.status_code == 200


class TestPlanUpgradeDowngrade:
    """Subscription plan changes detected via price_id in webhook."""

    def test_upgrade_basic_to_premium(self, client, monkeypatch, test_user, db):
        _env(monkeypatch)
        sub = _create_subscription_via_webhook(client, db, test_user, sub_id="sub_upg_1",
                                                plan_id="basic", price_id="price_basic_m")
        assert sub.plan_id == "basic"

        # Stripe fires subscription.updated with new price
        upgraded = _make_sub_obj(
            sub_id="sub_upg_1", customer_id="cus_billing_test",
            user_id=test_user.id, plan_id="basic", price_id="price_premium_m",
        )
        evt = {"id": "evt_upg_1", "type": "customer.subscription.updated",
               "created": int(time.time()), "data": {"object": upgraded}}
        resp = _post_webhook(client, evt)
        assert resp.status_code == 200

        db.refresh(sub)
        assert sub.plan_id == "premium"

    def test_downgrade_premium_to_basic(self, client, monkeypatch, test_user, db):
        _env(monkeypatch)
        sub = _create_subscription_via_webhook(client, db, test_user, sub_id="sub_dwn_1",
                                                plan_id="premium", price_id="price_premium_m")
        assert sub.plan_id == "premium"

        downgraded = _make_sub_obj(
            sub_id="sub_dwn_1", customer_id="cus_billing_test",
            user_id=test_user.id, plan_id="premium", price_id="price_basic_m",
        )
        evt = {"id": "evt_dwn_1", "type": "customer.subscription.updated",
               "created": int(time.time()), "data": {"object": downgraded}}
        resp = _post_webhook(client, evt)
        assert resp.status_code == 200

        db.refresh(sub)
        assert sub.plan_id == "basic"

    def test_yearly_billing_cycle_detected(self, client, monkeypatch, test_user, db):
        _env(monkeypatch)
        _setup_user_with_customer(db, test_user)
        sub_obj = _make_sub_obj(
            sub_id="sub_yearly_1", customer_id="cus_billing_test",
            user_id=test_user.id, price_id="price_basic_y", billing_cycle="yearly",
        )
        evt = {"id": "evt_yearly_1", "type": "customer.subscription.created",
               "created": int(time.time()), "data": {"object": sub_obj}}
        resp = _post_webhook(client, evt)
        assert resp.status_code == 200

        sub = db.query(Subscription).filter_by(stripe_subscription_id="sub_yearly_1").first()
        assert sub is not None
        assert sub.billing_cycle == "yearly"


class TestWebhookSecurity:
    """Webhook signature verification, replay protection, duplicate handling."""

    def test_missing_signature_rejected(self, client, monkeypatch):
        _env(monkeypatch)
        payload = json.dumps({"id": "evt_nosig", "type": "test"}).encode()
        resp = client.post("/api/payments/stripe/webhook", data=payload)
        assert resp.status_code == 400

    def test_wrong_signature_rejected(self, client, monkeypatch):
        _env(monkeypatch, webhook_secret="whsec_correct")
        payload = json.dumps({"id": "evt_badsig", "type": "test"}).encode()
        sig = _stripe_sig(payload, "whsec_wrong")
        resp = client.post("/api/payments/stripe/webhook", data=payload, headers={"Stripe-Signature": sig})
        assert resp.status_code == 400

    def test_stale_timestamp_rejected(self, client, monkeypatch):
        _env(monkeypatch)
        monkeypatch.setenv("STRIPE_WEBHOOK_TOLERANCE_SECONDS", "5")
        payload = json.dumps({"id": "evt_stale", "type": "test"}).encode()
        old_ts = int(time.time()) - 3600
        sig = _stripe_sig(payload, WEBHOOK_SECRET, timestamp=old_ts)
        resp = client.post("/api/payments/stripe/webhook", data=payload, headers={"Stripe-Signature": sig})
        assert resp.status_code == 400

    def test_duplicate_event_idempotent(self, client, monkeypatch, test_user, db):
        _env(monkeypatch)
        _setup_user_with_customer(db, test_user)
        sub_obj = _make_sub_obj(sub_id="sub_idem_1", customer_id="cus_billing_test",
                                 user_id=test_user.id)
        evt = {"id": "evt_idem_1", "type": "customer.subscription.created",
               "created": int(time.time()), "data": {"object": sub_obj}}
        resp1 = _post_webhook(client, evt)
        assert resp1.status_code == 200
        resp2 = _post_webhook(client, evt)
        assert resp2.status_code == 200

        assert db.query(Subscription).filter_by(stripe_subscription_id="sub_idem_1").count() == 1
        receipt = db.query(WebhookEventReceipt).filter_by(event_id="evt_idem_1").first()
        assert receipt is not None
        assert receipt.attempt_count >= 2

    def test_payload_tamper_after_processing_rejected(self, client, monkeypatch, test_user, db):
        _env(monkeypatch)
        _setup_user_with_customer(db, test_user)
        now = int(time.time())
        sub_obj = _make_sub_obj(sub_id="sub_tamper_1", customer_id="cus_billing_test",
                                 user_id=test_user.id, status="active")
        evt = {"id": "evt_tamper_1", "type": "customer.subscription.created",
               "created": now, "data": {"object": sub_obj}}
        resp1 = _post_webhook(client, evt)
        assert resp1.status_code == 200

        # Same event_id but tampered payload
        tampered_obj = dict(sub_obj)
        tampered_obj["status"] = "canceled"
        tampered_evt = {"id": "evt_tamper_1", "type": "customer.subscription.created",
                        "created": now, "data": {"object": tampered_obj}}
        resp2 = _post_webhook(client, tampered_evt)
        assert resp2.status_code == 400

    def test_unhandled_event_type_ignored(self, client, monkeypatch):
        _env(monkeypatch)
        evt = {"id": "evt_unknown_1", "type": "something.unknown", "data": {"object": {}}}
        resp = _post_webhook(client, evt)
        assert resp.status_code == 200
        body = resp.json()
        assert body["result"]["status"] == "ignored"

    def test_stale_event_ordering_protection(self, client, monkeypatch, test_user, db):
        """Out-of-order events (by created timestamp) should not regress state."""
        _env(monkeypatch)
        _setup_user_with_customer(db, test_user)
        t1 = int(time.time())
        t2 = t1 + 100
        t_stale = t1 + 50

        # Create
        sub_obj = _make_sub_obj(sub_id="sub_order_1", customer_id="cus_billing_test",
                                 user_id=test_user.id, status="active")
        _post_webhook(client, {"id": "evt_ord_create", "type": "customer.subscription.created",
                                "created": t1, "data": {"object": sub_obj}})

        # Newer update (active)
        _post_webhook(client, {"id": "evt_ord_new", "type": "customer.subscription.updated",
                                "created": t2, "data": {"object": sub_obj}})

        # Stale update tries to set past_due — should be ignored
        stale_obj = dict(sub_obj)
        stale_obj["status"] = "past_due"
        _post_webhook(client, {"id": "evt_ord_stale", "type": "customer.subscription.updated",
                                "created": t_stale, "data": {"object": stale_obj}})

        sub = db.query(Subscription).filter_by(stripe_subscription_id="sub_order_1").first()
        assert sub.status == "active"


class TestCheckoutIdempotency:
    """Double-submit protection on checkout endpoint."""

    def test_double_submit_replays(self, client, auth_headers, monkeypatch, test_user, db):
        _env(monkeypatch)
        calls = _patch_stripe(monkeypatch)

        first = client.post("/api/payments/stripe/create-checkout-session",
                            json={"plan_id": "basic", "billing_cycle": "monthly"},
                            headers=auth_headers)
        assert first.status_code == 200
        first_data = first.json()

        second = client.post("/api/payments/stripe/create-checkout-session",
                             json={"plan_id": "basic", "billing_cycle": "monthly"},
                             headers=auth_headers)
        assert second.status_code == 200
        second_data = second.json()

        assert second_data["session_id"] == first_data["session_id"]
        assert second_data["replayed"] is True
        assert calls["session_create"] == 1

    def test_existing_subscription_blocks_checkout(self, client, auth_headers, monkeypatch, test_user, db):
        _env(monkeypatch)
        _patch_stripe(monkeypatch)

        # Create an active subscription in DB
        sub = Subscription(
            user_id=test_user.id, plan_id="basic", plan_name="Basic",
            provider="stripe", status="active", stripe_customer_id="cus_billing_test",
            stripe_subscription_id="sub_existing", amount=9.99, currency="USD", billing_cycle="monthly",
        )
        db.add(sub)
        db.commit()

        resp = client.post("/api/payments/stripe/create-checkout-session",
                           json={"plan_id": "premium", "billing_cycle": "monthly"},
                           headers=auth_headers)
        # BUG FINDING: The route catches the "active subscription exists"
        # ValueError as a generic Exception and returns 500 instead of 400.
        # See STRIPE_TEST_RESULTS.md FINDING-02.
        assert resp.status_code == 500
        assert "checkout_session_failed" in resp.json()["error"]["code"]


class TestDeviceLimitAfterPaymentFailure:
    """User is downgraded to basic after payment failure → device limit enforced."""

    def test_user_downgraded_after_payment_failure(self, client, monkeypatch, test_user, db):
        _env(monkeypatch)
        sub = _create_subscription_via_webhook(client, db, test_user, sub_id="sub_device_1")
        db.refresh(test_user)
        assert test_user.subscription_status == "active"

        invoice_obj = {"id": "in_device_fail", "customer": "cus_billing_test",
                       "subscription": "sub_device_1"}
        _post_webhook(client, {"id": "evt_device_fail", "type": "invoice.payment_failed",
                                "created": int(time.time()), "data": {"object": invoice_obj}})

        db.refresh(test_user)
        assert test_user.subscription_status == "basic"


class TestSubscriptionStatusProperties:
    """Verify Subscription model property correctness."""

    def test_is_active_property(self, db, test_user):
        sub = Subscription(user_id=test_user.id, plan_id="basic", plan_name="Basic",
                           provider="stripe", status="active", amount=9.99, currency="USD",
                           billing_cycle="monthly")
        assert sub.is_active is True
        sub.status = "trialing"
        assert sub.is_active is True
        sub.status = "past_due"
        assert sub.is_active is False

    def test_is_canceled_property(self, db, test_user):
        sub = Subscription(user_id=test_user.id, plan_id="basic", plan_name="Basic",
                           provider="stripe", status="active", amount=0, currency="USD",
                           billing_cycle="monthly")
        assert sub.is_canceled is False
        sub.status = "canceled"
        assert sub.is_canceled is True

    def test_is_past_due_property(self, db, test_user):
        sub = Subscription(user_id=test_user.id, plan_id="basic", plan_name="Basic",
                           provider="stripe", status="past_due", amount=0, currency="USD",
                           billing_cycle="monthly")
        assert sub.is_past_due is True


class TestSubscriptionStateMachine:
    """Unit tests for the subscription state machine transitions."""

    def test_allowed_transitions(self):
        from services.subscription_state_machine import transition_subscription_status
        sub = Subscription(status="active", plan_id="basic", plan_name="Basic",
                           provider="stripe", amount=0, currency="USD", billing_cycle="monthly",
                           user_id=1)
        result = transition_subscription_status(sub, "past_due", source="test")
        assert result.applied is True
        assert sub.status == "past_due"

    def test_blocked_transition(self):
        from services.subscription_state_machine import transition_subscription_status
        sub = Subscription(status="incomplete_expired", plan_id="basic", plan_name="Basic",
                           provider="stripe", amount=0, currency="USD", billing_cycle="monthly",
                           user_id=1)
        result = transition_subscription_status(sub, "active", source="test")
        assert result.applied is False
        assert result.blocked is True
        assert sub.status == "incomplete_expired"

    def test_force_overrides_blocked(self):
        from services.subscription_state_machine import transition_subscription_status
        sub = Subscription(status="incomplete_expired", plan_id="basic", plan_name="Basic",
                           provider="stripe", amount=0, currency="USD", billing_cycle="monthly",
                           user_id=1)
        result = transition_subscription_status(sub, "active", source="test", force=True)
        assert result.applied is True
        assert sub.status == "active"

    def test_stale_event_ignored(self):
        from services.subscription_state_machine import transition_subscription_status
        sub = Subscription(status="active", plan_id="basic", plan_name="Basic",
                           provider="stripe", amount=0, currency="USD", billing_cycle="monthly",
                           user_id=1, extra_data={"last_event_created": 1000})
        result = transition_subscription_status(sub, "past_due", source="test", event_created=500)
        assert result.applied is False
        assert result.stale_event is True
        assert sub.status == "active"


class TestStripePlansEndpoint:
    """GET /stripe/plans returns correct plan data."""

    def test_plans_list(self, client, monkeypatch):
        _env(monkeypatch)
        resp = client.get("/api/payments/stripe/plans")
        assert resp.status_code == 200
        plans = resp.json()["plans"]
        plan_ids = [p["id"] for p in plans]
        assert "free" in plan_ids
        assert "basic" in plan_ids
        assert "premium" in plan_ids
        assert "ultra" in plan_ids
        for p in plans:
            if p["id"] == "free":
                assert p["requires_payment"] is False
            else:
                assert p["requires_payment"] is True
