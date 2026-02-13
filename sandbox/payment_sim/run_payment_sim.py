#!/usr/bin/env python3
"""
Offline payment simulation:
signup -> create checkout session -> simulate Stripe webhooks -> verify DB state.

Outputs:
  artifacts/payment_sim/report.json
  artifacts/payment_sim/summary.csv
"""

from __future__ import annotations

import csv
import hashlib
import hmac
import json
import os
import sys
import time
from pathlib import Path
from types import SimpleNamespace

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

# Ensure repo root is on sys.path when running as a script.
PROJECT_ROOT = Path(__file__).resolve().parents[2]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))


def _stripe_signature_header(*, payload: bytes, secret: str, timestamp: int | None = None) -> str:
    ts = int(timestamp or time.time())
    signed_payload = f"{ts}.".encode("utf-8") + payload
    sig = hmac.new(secret.encode("utf-8"), signed_payload, hashlib.sha256).hexdigest()
    return f"t={ts},v1={sig}"


def _configure_env() -> None:
    # Test-mode defaults for an offline simulation.
    os.environ.setdefault("TESTING", "true")
    os.environ.setdefault("DATABASE_URL", "sqlite:///:memory:")
    os.environ.setdefault("ENVIRONMENT", "development")

    os.environ.setdefault("SECRET_KEY", "payment-sim-secret-key")
    os.environ.setdefault("ACCESS_TOKEN_SECRET", "payment-sim-access-secret")
    os.environ.setdefault("REFRESH_TOKEN_SECRET", "payment-sim-refresh-secret")

    # Stripe test-mode config (no live payments).
    os.environ.setdefault("STRIPE_SECRET_KEY", "sk_test_dummy")
    os.environ.setdefault("STRIPE_WEBHOOK_SECRET", "whsec_test_secret")
    os.environ.setdefault("STRIPE_PRICE_BASIC_MONTHLY", "price_basic_monthly")
    os.environ.setdefault("STRIPE_PRICE_BASIC_YEARLY", "price_basic_yearly")

    # Keep dependencies quiet/offline.
    os.environ.setdefault("ENABLE_SENTRY", "false")
    os.environ.setdefault("ENABLE_APP_INSIGHTS", "false")
    os.environ.setdefault("EMAIL_VALIDATOR_CHECK_DELIVERABILITY", "false")
    os.environ.setdefault("BCRYPT_ROUNDS", "4")
    os.environ.setdefault("DB_ECHO", "false")


def _patch_stripe_api() -> dict:
    import stripe  # noqa: WPS433 - local import is intentional

    calls = {"customer_create": 0, "session_create": 0, "portal_create": 0}

    def fake_customer_create(**_kwargs):
        calls["customer_create"] += 1
        return SimpleNamespace(id="cus_test_123")

    def fake_session_create(**_kwargs):
        calls["session_create"] += 1
        return SimpleNamespace(id="cs_test_123", url="https://checkout.stripe.test/cs_test_123")

    def fake_portal_create(**_kwargs):
        calls["portal_create"] += 1
        return SimpleNamespace(url="https://billing.stripe.test/portal")

    stripe.Customer.create = staticmethod(fake_customer_create)
    stripe.checkout.Session.create = staticmethod(fake_session_create)
    stripe.billing_portal.Session.create = staticmethod(fake_portal_create)

    return calls


def _ensure_tables(engine) -> None:
    from database.base import Base

    # Import models for metadata registration.
    from models import (  # noqa: F401
        user,
        subscription,
        payment_idempotency_key,
        webhook_event_receipt,
        audit_log,
        vpn_server,
        vpn_server_rtt_sample,
        vpn_connection,
        vpn_demo_session,
        wireguard_peer,
        gdpr,
        support_ticket,
        usage_analytics,
        invoice,
        email_log,
        auth_refresh_token,
        jwt_blacklist_token,
    )

    Base.metadata.create_all(bind=engine)

    # Make "production" SessionLocal use our engine so any out-of-band calls share state.
    import database.session as db_session
    db_session.SessionLocal.configure(bind=engine)


def main() -> int:
    _configure_env()
    stripe_calls = _patch_stripe_api()

    engine = create_engine(
        "sqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
        echo=False,
    )
    SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
    _ensure_tables(engine)

    db = SessionLocal()
    steps: list[dict] = []

    from database.session import get_db
    from utils.inprocess_testclient import InProcessTestClient
    from main import app

    def _override_get_db():
        try:
            yield db
        finally:
            pass

    app.dependency_overrides[get_db] = _override_get_db

    email = f"simuser_{int(time.time())}@example.com"
    password = "SecurePass123"

    artifacts_dir = Path("artifacts/payment_sim")
    artifacts_dir.mkdir(parents=True, exist_ok=True)

    with InProcessTestClient(app, raise_server_exceptions=False) as client:
        # 1) Signup
        reg = client.post(
            "/api/auth/register",
            json={"email": email, "password": password, "password_confirm": password},
        )
        steps.append({"step": "signup", "status_code": reg.status_code, "ok": reg.status_code in (200, 201)})
        if reg.status_code not in (200, 201):
            _write_outputs(artifacts_dir, steps, stripe_calls, {"error": reg.text})
            return 1

        csrf = client.cookies.get("csrf_token") or ""
        me = client.get("/api/auth/me")
        me_data = me.json() if me.headers.get("content-type", "").startswith("application/json") else {}
        user_id = me_data.get("id")
        steps.append({"step": "auth_me", "status_code": me.status_code, "ok": me.status_code == 200})

        # 2) Create checkout session (cookie + CSRF)
        checkout = client.post(
            "/api/payments/stripe/create-checkout-session",
            json={"plan_id": "basic", "billing_cycle": "monthly"},
            headers={"X-CSRF-Token": csrf},
        )
        checkout_data = checkout.json() if checkout.headers.get("content-type", "").startswith("application/json") else {}
        steps.append({"step": "create_checkout_session", "status_code": checkout.status_code, "ok": checkout.status_code == 200})
        if checkout.status_code != 200:
            _write_outputs(artifacts_dir, steps, stripe_calls, {"error": checkout_data or checkout.text})
            return 1

        # 3) Simulate Stripe webhooks
        # Stripe webhooks do not carry SecureWave auth cookies; clear them so CSRF
        # middleware doesn't block the requests.
        client.cookies.clear()

        webhook_secret = os.environ["STRIPE_WEBHOOK_SECRET"]
        now = int(time.time())

        # a) checkout.session.completed
        checkout_evt = {
            "id": "evt_sim_checkout_completed",
            "type": "checkout.session.completed",
            "data": {
                "object": {
                    "id": checkout_data.get("session_id") or "cs_test_123",
                    "customer": "cus_test_123",
                    "client_reference_id": str(user_id) if user_id is not None else None,
                    "subscription": "sub_sim_123",
                    "payment_status": "paid",
                    "metadata": {
                        "securewave_user_id": str(user_id) if user_id is not None else "",
                        "plan_id": "basic",
                        "billing_cycle": "monthly",
                    },
                }
            },
        }
        _post_webhook(client, steps, checkout_evt, webhook_secret)

        # b) customer.subscription.created
        sub_evt = {
            "id": "evt_sim_sub_created",
            "type": "customer.subscription.created",
            "data": {
                "object": {
                    "id": "sub_sim_123",
                    "customer": "cus_test_123",
                    "status": "active",
                    "current_period_start": now,
                    "current_period_end": now + 30 * 24 * 3600,
                    "cancel_at_period_end": False,
                    "items": {"data": [{"price": {"id": os.environ["STRIPE_PRICE_BASIC_MONTHLY"]}}]},
                    "metadata": {
                        "securewave_user_id": str(user_id) if user_id is not None else "",
                        "plan_id": "basic",
                        "billing_cycle": "monthly",
                    },
                }
            },
        }
        _post_webhook(client, steps, sub_evt, webhook_secret)

        # 4) Verify DB state
        from models.subscription import Subscription
        from models.user import User

        user = db.query(User).filter_by(email=email).first()
        subscription = db.query(Subscription).filter_by(stripe_subscription_id="sub_sim_123").first()
        ok_state = bool(user and subscription and subscription.status in ("active", "trialing") and user.subscription_status == "active")
        steps.append({"step": "verify_db_state", "status_code": 0, "ok": ok_state})

        report = {
            "user": {"id": getattr(user, "id", None), "email": email, "subscription_status": getattr(user, "subscription_status", None)},
            "subscription": subscription.to_dict(include_sensitive=True) if subscription else None,
            "stripe_calls": stripe_calls,
        }
        _write_outputs(artifacts_dir, steps, stripe_calls, report)

    app.dependency_overrides.clear()
    return 0 if ok_state else 1


def _post_webhook(client, steps: list[dict], event: dict, secret: str) -> None:
    payload = json.dumps(event, separators=(",", ":"), sort_keys=True).encode("utf-8")
    sig = _stripe_signature_header(payload=payload, secret=secret)
    resp = client.post("/api/payments/stripe/webhook", data=payload, headers={"Stripe-Signature": sig})
    steps.append({"step": f"webhook:{event.get('type')}", "status_code": resp.status_code, "ok": resp.status_code == 200})


def _write_outputs(artifacts_dir: Path, steps: list[dict], stripe_calls: dict, report: dict) -> None:
    (artifacts_dir / "report.json").write_text(
        json.dumps(
            {
                "steps": steps,
                "stripe_calls": stripe_calls,
                "report": report,
                "ts": int(time.time()),
            },
            indent=2,
        ),
        encoding="utf-8",
    )

    with (artifacts_dir / "summary.csv").open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=["step", "status_code", "ok"])
        writer.writeheader()
        for row in steps:
            writer.writerow({k: row.get(k) for k in writer.fieldnames})


if __name__ == "__main__":
    raise SystemExit(main())
