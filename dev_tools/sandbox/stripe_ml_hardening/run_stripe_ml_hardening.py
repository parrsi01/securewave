#!/usr/bin/env python3
"""
Advanced performance + payment hardening simulation harness.

Outputs:
  - artifacts/stripe_and_ml_hardening_report.md
  - artifacts/stripe_ml_hardening/report.json
"""

from __future__ import annotations

import json
import os
import sys
import time
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from types import SimpleNamespace
from typing import Any

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

REPO_ROOT = Path(__file__).resolve().parents[3]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))


def _utc_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _configure_env() -> None:
    os.environ.setdefault("ENVIRONMENT", "development")
    os.environ.setdefault("TESTING", "true")
    os.environ.setdefault("DATABASE_URL", "sqlite:///:memory:")
    os.environ.setdefault("AUTO_CREATE_TABLES", "false")
    os.environ.setdefault("DB_ECHO", "false")
    os.environ.setdefault("STRIPE_SECRET_KEY", "sk_test_hardening_dummy")
    os.environ.setdefault("STRIPE_WEBHOOK_SECRET", "whsec_hardening_dummy")
    os.environ.setdefault("STRIPE_PRICE_BASIC_MONTHLY", "price_basic_monthly")
    os.environ.setdefault("STRIPE_PRICE_BASIC_YEARLY", "price_basic_yearly")
    os.environ.setdefault("STRIPE_PRICE_PREMIUM_MONTHLY", "price_premium_monthly")
    os.environ.setdefault("STRIPE_PRICE_PREMIUM_YEARLY", "price_premium_yearly")
    os.environ.setdefault("STRIPE_PRICE_ULTRA_MONTHLY", "price_ultra_monthly")
    os.environ.setdefault("STRIPE_PRICE_ULTRA_YEARLY", "price_ultra_yearly")


def _ensure_tables(engine) -> None:
    from database.base import Base
    from models import (  # noqa: F401
        user,
        subscription,
        payment_idempotency_key,
        webhook_event_receipt,
        audit_log,
        vpn_server,
        vpn_server_rtt_sample,
        vpn_connection,
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

    import database.session as db_session

    db_session.SessionLocal.configure(bind=engine)


def _payload_hash(event: dict[str, Any]) -> str:
    import hashlib

    payload = json.dumps(event, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


@dataclass
class ScenarioResult:
    name: str
    ok: bool
    detail: str
    evidence: dict[str, Any]


def main() -> int:
    _configure_env()

    engine = create_engine(
        "sqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
        echo=False,
    )
    SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
    _ensure_tables(engine)
    db = SessionLocal()

    from models.subscription import Subscription
    from models.user import User
    from services.marl_policy import MARLPolicyEngine, StateVector
    from services.subscription_manager import SubscriptionManager
    from services.wireguard_tuning import tune_wireguard
    import services.payment_webhooks as payment_webhooks_mod
    from services.payment_webhooks import PaymentWebhookHandler

    # Keep simulation offline.
    payment_webhooks_mod.EmailService.send_email = lambda self, **kwargs: True  # type: ignore[assignment]

    artifacts_dir = REPO_ROOT / "artifacts" / "stripe_ml_hardening"
    artifacts_dir.mkdir(parents=True, exist_ok=True)

    now = datetime.utcnow()

    user = User(
        email="hardening-sim@example.com",
        hashed_password="x",
        email_verified=True,
        is_active=True,
        subscription_status="active",
        stripe_customer_id="cus_hardening_sim",
        created_at=now,
    )
    db.add(user)
    db.commit()
    db.refresh(user)

    subscription = Subscription(
        user_id=user.id,
        plan_id="basic",
        plan_name="Basic Plan",
        provider="stripe",
        status="active",
        stripe_customer_id="cus_hardening_sim",
        stripe_subscription_id="sub_hardening_sim",
        stripe_price_id="price_basic_monthly",
        amount=9.99,
        currency="USD",
        billing_cycle="monthly",
        current_period_start=now - timedelta(days=1),
        current_period_end=now + timedelta(days=29),
        next_billing_date=now + timedelta(days=29),
        activated_at=now - timedelta(days=1),
        auto_renew=True,
    )
    db.add(subscription)
    db.commit()
    db.refresh(subscription)

    perf_results: list[ScenarioResult] = []
    pay_results: list[ScenarioResult] = []

    # ------------------------------------------------------------------
    # 1) MARL-XGBoost hardening scenarios
    # ------------------------------------------------------------------
    engine_policy = MARLPolicyEngine()

    free_state = StateVector(
        user_id=1,
        server_id="srv-1",
        latency_ms=170.0,
        packet_loss=0.05,
        jitter_ms=20.0,
        user_priority=0,
    )
    premium_state = StateVector(
        user_id=2,
        server_id="srv-1",
        latency_ms=170.0,
        packet_loss=0.05,
        jitter_ms=20.0,
        user_priority=1,
    )
    free_decision = engine_policy.decide(free_state)
    premium_decision = engine_policy.decide(premium_state)
    free_weight = float((free_decision.optimization_hints or {}).get("latency_weight", 1.0))
    premium_weight = float((premium_decision.optimization_hints or {}).get("latency_weight", 1.0))
    perf_results.append(
        ScenarioResult(
            name="Latency weighting",
            ok=premium_weight > free_weight,
            detail="Premium tier receives stronger latency weighting than free tier.",
            evidence={"free_weight": free_weight, "premium_weight": premium_weight},
        )
    )

    # Predictive load balancing.
    for load in (0.72, 0.78, 0.84, 0.88):
        engine_policy.decide(
            StateVector(
                user_id=7,
                server_id="srv-trend",
                server_load=load,
                latency_ms=55.0,
                packet_loss=0.01,
                jitter_ms=3.0,
            )
        )
    predictive_decision = engine_policy.decide(
        StateVector(
            user_id=7,
            server_id="srv-trend",
            server_load=0.89,
            latency_ms=60.0,
            packet_loss=0.01,
            jitter_ms=3.0,
        )
    )
    predicted_load = float((predictive_decision.optimization_hints or {}).get("predicted_server_load", 0.0))
    perf_results.append(
        ScenarioResult(
            name="Predictive load balancing",
            ok=(
                predictive_decision.action.value in {"rotate_server", "reroute"}
                and predictive_decision.safety_override
                and predicted_load >= engine_policy.max_server_load
            ),
            detail="Rising load trend triggers proactive rotate before hard overload.",
            evidence={
                "action": predictive_decision.action.value,
                "safety_override": predictive_decision.safety_override,
                "predicted_server_load": predicted_load,
            },
        )
    )

    # Adaptive MTU selection.
    mtu_stable = tune_wireguard(
        endpoint="1.1.1.1:51820",
        client_ip="8.8.8.8",
        forwarded_for=None,
        observed_latency_ms=30.0,
        packet_loss=0.0,
        jitter_ms=2.0,
        server_health_status="healthy",
        device_type="windows",
    )
    mtu_unstable = tune_wireguard(
        endpoint="1.1.1.1:51820",
        client_ip="8.8.8.8",
        forwarded_for=None,
        observed_latency_ms=320.0,
        packet_loss=0.14,
        jitter_ms=70.0,
        server_health_status="unstable",
        device_type="windows",
    )
    perf_results.append(
        ScenarioResult(
            name="Adaptive MTU selection",
            ok=(mtu_unstable.mtu or 1500) < (mtu_stable.mtu or 1200),
            detail="MTU is reduced under unstable/lossy conditions.",
            evidence={"stable_mtu": mtu_stable.mtu, "unstable_mtu": mtu_unstable.mtu},
        )
    )

    # Server health pre-classification.
    healthy = engine_policy.preclassify_server_health(
        StateVector(
            user_id=9,
            server_id="srv-health",
            latency_ms=35.0,
            packet_loss=0.0,
            jitter_ms=1.0,
            server_load=0.35,
        )
    )
    unstable = engine_policy.preclassify_server_health(
        StateVector(
            user_id=9,
            server_id="srv-health",
            latency_ms=500.0,
            packet_loss=0.22,
            jitter_ms=90.0,
            server_load=0.95,
        )
    )
    perf_results.append(
        ScenarioResult(
            name="Server health pre-classification",
            ok=(healthy == "healthy" and unstable in {"degraded", "unstable"}),
            detail="Pre-classifier separates healthy vs risky servers before deeper checks.",
            evidence={"healthy_case": healthy, "risky_case": unstable},
        )
    )

    # ------------------------------------------------------------------
    # 2) Stripe hardening simulation scenarios
    # ------------------------------------------------------------------
    manager = SubscriptionManager(db)
    manager.stripe.update_subscription = lambda **kwargs: {"ok": True, "kwargs": kwargs}  # type: ignore[method-assign]
    manager.stripe.cancel_subscription = lambda **kwargs: {"ok": True, "kwargs": kwargs}  # type: ignore[method-assign]
    manager.stripe.reactivate_subscription = lambda *args, **kwargs: {"ok": True, "args": args, "kwargs": kwargs}  # type: ignore[method-assign]
    manager.stripe.get_subscription = lambda *_args, **_kwargs: None  # type: ignore[method-assign]
    manager.stripe.create_billing_portal_session = (  # type: ignore[method-assign]
        lambda **kwargs: SimpleNamespace(url="https://billing.stripe.test/portal")
    )

    upgraded = manager.upgrade_subscription(
        subscription_id=subscription.id,
        new_plan_id="premium",
        billing_cycle="monthly",
        idempotency_key="hardening_upgrade_1",
    )
    upgraded_plan = str(upgraded.plan_id)
    downgraded = manager.upgrade_subscription(
        subscription_id=subscription.id,
        new_plan_id="basic",
        billing_cycle="monthly",
        idempotency_key="hardening_downgrade_1",
    )
    downgraded_plan = str(downgraded.plan_id)
    pay_results.append(
        ScenarioResult(
            name="Upgrade/downgrade",
            ok=(upgraded_plan == "premium" and downgraded_plan == "basic"),
            detail="Plan transitions complete with manager + idempotent provider calls.",
            evidence={"after_upgrade": upgraded_plan, "after_downgrade": downgraded_plan},
        )
    )

    handler = PaymentWebhookHandler(db)

    # Failed payment.
    fail_evt = {
        "id": "evt_hardening_invoice_failed",
        "type": "invoice.payment_failed",
        "created": int(time.time()),
        "data": {"object": {"id": "in_hardening_1", "subscription": "sub_hardening_sim", "hosted_invoice_url": "https://billing.test/in_hardening_1"}},
    }
    fail_result = handler.handle_stripe_event(fail_evt, payload_hash=_payload_hash(fail_evt))
    db.refresh(subscription)
    pay_results.append(
        ScenarioResult(
            name="Failed payment",
            ok=subscription.status in {"past_due", "unpaid"},
            detail="Invoice failure pushes subscription to collection state.",
            evidence={"status": subscription.status, "handler_status": fail_result.get("status")},
        )
    )

    # Expired card.
    expired_evt = {
        "id": "evt_hardening_expired_card",
        "type": "payment_intent.payment_failed",
        "created": int(time.time()) + 1,
        "data": {
            "object": {
                "id": "pi_hardening_expired",
                "metadata": {"stripe_subscription_id": "sub_hardening_sim"},
                "last_payment_error": {"code": "expired_card", "decline_code": "expired_card"},
            }
        },
    }
    expired_result = handler.handle_stripe_event(expired_evt, payload_hash=_payload_hash(expired_evt))
    db.refresh(subscription)
    pay_results.append(
        ScenarioResult(
            name="Expired card",
            ok=subscription.status == "unpaid",
            detail="Expired card failure escalates to unpaid state.",
            evidence={"status": subscription.status, "handler_result": expired_result.get("result")},
        )
    )

    # Concurrent subscription change / out-of-order protection.
    subscription.status = "active"
    subscription.failed_payment_count = 0
    db.add(subscription)
    db.commit()

    t_now = int(time.time()) + 100
    newer_evt = {
        "id": "evt_hardening_newer_update",
        "type": "customer.subscription.updated",
        "created": t_now,
        "data": {
            "object": {
                "id": "sub_hardening_sim",
                "customer": "cus_hardening_sim",
                "status": "active",
                "current_period_start": t_now,
                "current_period_end": t_now + 30 * 24 * 3600,
                "items": {"data": [{"price": {"id": "price_basic_monthly"}}]},
                "metadata": {"securewave_user_id": str(user.id), "plan_id": "basic", "billing_cycle": "monthly"},
            }
        },
    }
    older_evt = {
        "id": "evt_hardening_older_update",
        "type": "customer.subscription.updated",
        "created": t_now - 30,
        "data": {
            "object": {
                "id": "sub_hardening_sim",
                "customer": "cus_hardening_sim",
                "status": "past_due",
                "current_period_start": t_now - 30,
                "current_period_end": t_now + 30 * 24 * 3600,
                "items": {"data": [{"price": {"id": "price_basic_monthly"}}]},
                "metadata": {"securewave_user_id": str(user.id), "plan_id": "basic", "billing_cycle": "monthly"},
            }
        },
    }
    handler.handle_stripe_event(newer_evt, payload_hash=_payload_hash(newer_evt))
    handler.handle_stripe_event(older_evt, payload_hash=_payload_hash(older_evt))
    db.refresh(subscription)
    pay_results.append(
        ScenarioResult(
            name="Concurrent subscription change",
            ok=subscription.status == "active",
            detail="Out-of-order stale update is ignored by state machine.",
            evidence={"final_status": subscription.status},
        )
    )

    all_results = perf_results + pay_results
    passed = sum(1 for row in all_results if row.ok)
    total = len(all_results)

    raw = {
        "generated_at": _utc_iso(),
        "performance_results": [row.__dict__ for row in perf_results],
        "payment_results": [row.__dict__ for row in pay_results],
        "summary": {"passed": passed, "total": total},
    }
    (artifacts_dir / "report.json").write_text(json.dumps(raw, indent=2), encoding="utf-8")

    lines = [
        "# Stripe and ML Hardening Report",
        "",
        f"- Generated: `{raw['generated_at']}`",
        f"- Passed scenarios: `{passed}/{total}`",
        "",
        "## MARL-XGBoost Improvements",
        "",
        "- Latency weighting: enabled and tier-aware (premium > free).",
        "- Predictive load balancing: proactive rotate on rising load trend.",
        "- Adaptive MTU selection: lower MTU under unstable/lossy paths.",
        "- Server health pre-classification: healthy/degraded/unstable before full health loop.",
        "",
        "## Stripe Hardening",
        "",
        "- Webhook verification: signature + event-age guard.",
        "- Replay protection: duplicate event payload-hash mismatch rejected.",
        "- Idempotent checkout: single-flight guard for conflicting in-progress checkout requests.",
        "- Subscription state machine: guarded transitions + stale event suppression.",
        "",
        "## Simulation Results",
        "",
        "| Scenario | Status | Detail |",
        "|---|---|---|",
    ]
    for row in all_results:
        lines.append(f"| {row.name} | {'PASS' if row.ok else 'FAIL'} | {row.detail} |")

    lines.extend(
        [
            "",
            "## Raw Artifact",
            "",
            "- `artifacts/stripe_ml_hardening/report.json`",
            "",
        ]
    )

    report_path = REPO_ROOT / "artifacts" / "stripe_and_ml_hardening_report.md"
    report_path.write_text("\n".join(lines), encoding="utf-8")

    db.close()
    print(json.dumps({"report": str(report_path), "passed": passed, "total": total}, indent=2))
    return 0 if passed == total else 1


if __name__ == "__main__":
    raise SystemExit(main())
