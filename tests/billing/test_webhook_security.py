"""
tests/billing/test_webhook_security.py

Security tests for Stripe webhook processing:
  - Signature verification (valid / missing / tampered)
  - Replay attack prevention (duplicate event_id)
  - Payload hash mismatch detection
  - Stale event rejection
  - Idempotent processing (duplicate deliver → single DB state change)
  - No Stripe secrets in error responses
  - Duplicate endpoint removed (billing webhook 404)
"""

import hashlib
import hmac
import json
import os
import time
import uuid
from datetime import datetime
from unittest.mock import patch

import pytest


# ── Webhook signing helper (mimics Stripe's signing algorithm) ─────────────────

def _stripe_sig(payload: bytes, secret: str, timestamp: int = None) -> str:
    t = timestamp or int(time.time())
    signed_payload = f"{t}.{payload.decode()}".encode()
    mac = hmac.new(secret.encode(), signed_payload, "sha256").hexdigest()
    return f"t={t},v1={mac}"


def _event_body(event_type: str = "customer.subscription.updated", **overrides) -> bytes:
    event = {
        "id": f"evt_{uuid.uuid4().hex}",
        "type": event_type,
        "created": int(time.time()),
        "data": {"object": {"id": f"sub_{uuid.uuid4().hex}", "status": "active", "metadata": {}}},
        **overrides,
    }
    return json.dumps(event).encode()


_WEBHOOK_SECRET = "whsec_test_secret_1234567890abcdef"


# ══════════════════════════════════════════════════════════════════════════════
# 1. Signature verification
# ══════════════════════════════════════════════════════════════════════════════

class TestWebhookSignatureVerification:

    def _post(self, client, body: bytes, sig: str, path: str = "/api/payments/stripe/webhook"):
        return client.post(
            path,
            content=body,
            headers={"Stripe-Signature": sig, "Content-Type": "application/json"},
        )

    def test_missing_signature_header_rejected(self, client, db):
        body = _event_body()
        resp = client.post(
            "/api/payments/stripe/webhook",
            content=body,
            headers={"Content-Type": "application/json"},
        )
        assert resp.status_code == 400

    def test_empty_signature_rejected(self, client, db):
        body = _event_body()
        resp = self._post(client, body, sig="")
        assert resp.status_code == 400

    def test_valid_signature_accepted(self, client, db):
        body = _event_body("customer.created")
        sig = _stripe_sig(body, _WEBHOOK_SECRET)
        with patch.dict(os.environ, {"STRIPE_WEBHOOK_SECRET": _WEBHOOK_SECRET}):
            with patch("services.stripe_service.stripe.Webhook.construct_event") as mock_construct:
                import stripe as stripe_lib
                mock_event = {
                    "id": f"evt_{uuid.uuid4().hex}",
                    "type": "customer.created",
                    "created": int(time.time()),
                    "data": {"object": {}},
                }
                mock_construct.return_value = mock_event
                resp = self._post(client, body, sig)
        assert resp.status_code == 200

    def test_tampered_signature_rejected(self, client, db):
        body = _event_body()
        sig = _stripe_sig(body, _WEBHOOK_SECRET)
        tampered_sig = sig[:-4] + "XXXX"
        with patch.dict(os.environ, {"STRIPE_WEBHOOK_SECRET": _WEBHOOK_SECRET}):
            with patch("services.stripe_service.stripe.Webhook.construct_event") as mock_construct:
                import stripe as stripe_lib
                mock_construct.side_effect = stripe_lib.error.SignatureVerificationError(
                    "No matching signatures", sig
                )
                resp = self._post(client, body, tampered_sig)
        assert resp.status_code == 400

    def test_wrong_secret_rejected(self, client, db):
        body = _event_body()
        sig = _stripe_sig(body, "wrong_secret_xyz")
        with patch.dict(os.environ, {"STRIPE_WEBHOOK_SECRET": _WEBHOOK_SECRET}):
            with patch("services.stripe_service.stripe.Webhook.construct_event") as mock_construct:
                import stripe as stripe_lib
                mock_construct.side_effect = stripe_lib.error.SignatureVerificationError(
                    "No signatures found", sig
                )
                resp = self._post(client, body, sig)
        assert resp.status_code == 400

    def test_missing_webhook_secret_env_returns_503(self, client, db):
        """If STRIPE_WEBHOOK_SECRET is not set, return 503 not 500."""
        body = _event_body()
        sig = _stripe_sig(body, "anything")
        with patch.dict(os.environ, {}, clear=False):
            os.environ.pop("STRIPE_WEBHOOK_SECRET", None)
            resp = self._post(client, body, sig)
        assert resp.status_code == 503

    def test_error_response_does_not_expose_secret(self, client, db):
        """Stripe secret key must never appear in error response body."""
        body = _event_body()
        sig = _stripe_sig(body, "wrong")
        secret = "sk_test_super_secret_key_should_never_appear"
        with patch.dict(os.environ, {"STRIPE_WEBHOOK_SECRET": _WEBHOOK_SECRET, "STRIPE_SECRET_KEY": secret}):
            with patch("services.stripe_service.stripe.Webhook.construct_event") as mock_construct:
                import stripe as stripe_lib
                mock_construct.side_effect = stripe_lib.error.SignatureVerificationError("bad", sig)
                resp = self._post(client, body, sig)
        assert secret not in resp.text
        assert "sk_" not in resp.text


# ══════════════════════════════════════════════════════════════════════════════
# 2. Replay attack prevention
# ══════════════════════════════════════════════════════════════════════════════

class TestReplayAttackPrevention:

    def _make_event(self, event_id: str = None, event_type: str = "customer.created") -> dict:
        return {
            "id": event_id or f"evt_{uuid.uuid4().hex}",
            "type": event_type,
            "created": int(time.time()),
            "data": {"object": {"id": "cus_test"}},
        }

    def test_duplicate_event_id_returns_duplicate_status(self, db):
        """Delivering the same event_id twice must result in 'duplicate' on second call."""
        from services.payment_webhooks import PaymentWebhookHandler
        handler = PaymentWebhookHandler(db)
        event_id = f"evt_{uuid.uuid4().hex}"
        event = self._make_event(event_id)
        payload_hash = hashlib.sha256(json.dumps(event).encode()).hexdigest()

        # First delivery
        result1 = handler.handle_stripe_event(event, payload_hash=payload_hash)
        assert result1["status"] in ("processed", "ignored")

        # Second delivery — same event_id
        result2 = handler.handle_stripe_event(event, payload_hash=payload_hash)
        assert result2["status"] == "duplicate"

    def test_duplicate_with_mismatched_hash_raises(self, db):
        """Replay with a different payload hash (tampered body) must raise ValueError."""
        from services.payment_webhooks import PaymentWebhookHandler
        handler = PaymentWebhookHandler(db)
        event_id = f"evt_{uuid.uuid4().hex}"
        event = self._make_event(event_id)

        original_hash = hashlib.sha256(b"original_body").hexdigest()
        tampered_hash = hashlib.sha256(b"tampered_body").hexdigest()

        handler.handle_stripe_event(event, payload_hash=original_hash)

        with pytest.raises(ValueError, match="replay"):
            handler.handle_stripe_event(event, payload_hash=tampered_hash)

    def test_stale_event_dropped_by_state_machine(self, db):
        """A webhook with an older 'created' timestamp than the last processed one must be dropped."""
        from models.subscription import Subscription
        from services.subscription_state_machine import transition_subscription_status

        sub = Subscription(
            user_id=99999,
            plan_id="premium",
            plan_name="Premium",
            provider="stripe",
            status="active",
            amount=9.99,
            currency="USD",
            billing_cycle="monthly",
            extra_data={"last_event_created": 2000},
        )
        db.add(sub)
        db.commit()

        # Older event — should be rejected
        result = transition_subscription_status(
            sub,
            "past_due",
            source="stripe_webhook:invoice.payment_failed",
            event_created=1000,  # older than last_event_created=2000
        )
        assert result.applied is False
        assert result.stale_event is True
        assert sub.status == "active"

    def test_stale_event_max_age_rejected(self, client, db):
        """Events older than STRIPE_WEBHOOK_MAX_EVENT_AGE_SECONDS must be rejected."""
        body = _event_body("customer.created", created=int(time.time()) - 7200)  # 2h old
        sig = _stripe_sig(body, _WEBHOOK_SECRET)
        with patch.dict(os.environ, {"STRIPE_WEBHOOK_SECRET": _WEBHOOK_SECRET, "STRIPE_WEBHOOK_MAX_EVENT_AGE_SECONDS": "3600"}):
            with patch("services.stripe_service.stripe.Webhook.construct_event") as mock_construct:
                mock_construct.side_effect = ValueError("Stripe event too old")
                resp = client.post(
                    "/api/payments/stripe/webhook",
                    content=body,
                    headers={"Stripe-Signature": sig, "Content-Type": "application/json"},
                )
        assert resp.status_code == 400


# ══════════════════════════════════════════════════════════════════════════════
# 3. Idempotent event handling
# ══════════════════════════════════════════════════════════════════════════════

class TestIdempotentEventHandling:

    def test_processed_event_not_reprocessed(self, db):
        """An event already marked 'processed' must return 'duplicate' without re-running the handler."""
        from services.payment_webhooks import PaymentWebhookHandler
        from models.webhook_event_receipt import WebhookEventReceipt

        event_id = f"evt_{uuid.uuid4().hex}"
        receipt = WebhookEventReceipt(
            provider="stripe",
            event_id=event_id,
            event_type="invoice.paid",
            status="processed",
            attempt_count=1,
            received_at=datetime.utcnow(),
        )
        db.add(receipt)
        db.commit()

        event = {
            "id": event_id,
            "type": "invoice.paid",
            "created": int(time.time()),
            "data": {"object": {}},
        }
        handler = PaymentWebhookHandler(db)
        result = handler.handle_stripe_event(event)
        assert result["status"] == "duplicate"

    def test_failed_event_can_be_retried(self, db):
        """An event marked 'failed' must be retried on next delivery."""
        from services.payment_webhooks import PaymentWebhookHandler
        from models.webhook_event_receipt import WebhookEventReceipt

        event_id = f"evt_{uuid.uuid4().hex}"
        receipt = WebhookEventReceipt(
            provider="stripe",
            event_id=event_id,
            event_type="customer.created",
            status="failed",
            attempt_count=1,
            received_at=datetime.utcnow(),
        )
        db.add(receipt)
        db.commit()

        event = {
            "id": event_id,
            "type": "customer.created",
            "created": int(time.time()),
            "data": {"object": {}},
        }
        handler = PaymentWebhookHandler(db)
        # Should NOT return 'duplicate' — failed events are retried
        result = handler.handle_stripe_event(event)
        assert result["status"] != "duplicate"

    def test_unknown_event_type_marked_ignored(self, db):
        """Unrecognised event types must be stored as 'ignored', not failed."""
        from services.payment_webhooks import PaymentWebhookHandler
        from models.webhook_event_receipt import WebhookEventReceipt

        event_id = f"evt_{uuid.uuid4().hex}"
        event = {
            "id": event_id,
            "type": "radar.early_fraud_warning.created",  # not in handler map
            "created": int(time.time()),
            "data": {"object": {}},
        }
        handler = PaymentWebhookHandler(db)
        result = handler.handle_stripe_event(event)
        assert result["status"] == "ignored"

        receipt = db.query(WebhookEventReceipt).filter_by(event_id=event_id).first()
        assert receipt is not None
        assert receipt.status == "ignored"


# ══════════════════════════════════════════════════════════════════════════════
# 4. Duplicate endpoint removed
# ══════════════════════════════════════════════════════════════════════════════

class TestNoDuplicateWebhookEndpoint:

    def test_billing_stripe_webhook_removed(self, client, db):
        """
        POST /api/billing/webhooks/stripe must no longer exist.
        The canonical endpoint is POST /api/payments/stripe/webhook.
        """
        body = _event_body()
        resp = client.post(
            "/api/billing/webhooks/stripe",
            content=body,
            headers={"Stripe-Signature": "t=1,v1=fake", "Content-Type": "application/json"},
        )
        assert resp.status_code == 404

    def test_canonical_webhook_endpoint_exists(self, client, db):
        """POST /api/payments/stripe/webhook must exist (400 for missing sig, not 404)."""
        body = _event_body()
        resp = client.post(
            "/api/payments/stripe/webhook",
            content=body,
            headers={"Content-Type": "application/json"},
        )
        # 400 (missing sig) or 503 (no secret) — either is correct, not 404
        assert resp.status_code in (400, 503)


# ══════════════════════════════════════════════════════════════════════════════
# 5. stripe-status endpoint requires authentication
# ══════════════════════════════════════════════════════════════════════════════

class TestStripeStatusAuth:

    def test_stripe_status_unauthenticated_rejected(self, client, db):
        client.cookies.clear()
        resp = client.get("/api/billing/stripe-status")
        assert resp.status_code == 401

    def test_stripe_status_authenticated_succeeds(self, client, db):
        from models.user import User
        from services.hashing_service import hash_password
        user = User(
            email=f"stripe_{uuid.uuid4().hex[:6]}@test.com",
            hashed_password=hash_password("SecurePass123!"),
            email_verified=True,
            is_active=True,
            created_at=datetime.utcnow(),
        )
        db.add(user)
        db.commit()

        login = client.post("/api/auth/login", json={"email": user.email, "password": "SecurePass123!"})
        assert login.status_code == 200

        resp = client.get("/api/billing/stripe-status")
        assert resp.status_code == 200
        body = resp.json()
        assert "configured" in body
        assert "mode" in body


# ══════════════════════════════════════════════════════════════════════════════
# 6. PayPal webhook pre-flight guard
# ══════════════════════════════════════════════════════════════════════════════

class TestPayPalWebhookPreflight:

    def test_paypal_webhook_without_credentials_returns_503(self, client, db):
        """PayPal webhook must return 503 when credentials are not configured."""
        env_patch = {}
        env_patch["PAYPAL_CLIENT_ID"] = ""
        with patch.dict(os.environ, env_patch):
            os.environ.pop("PAYPAL_CLIENT_ID", None)
            resp = client.post(
                "/api/billing/webhooks/paypal",
                content=b'{"event_type":"BILLING.SUBSCRIPTION.ACTIVATED"}',
                headers={"Content-Type": "application/json"},
            )
        assert resp.status_code == 503
