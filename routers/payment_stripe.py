"""
SecureWave VPN - Stripe Payment Router

Provides direct Stripe endpoints under /api/payments/stripe/*:
  POST /stripe/create-checkout-session  - create a Stripe Checkout session
  POST /stripe/webhook                  - receive Stripe webhook events
  GET  /stripe/plans                    - list available plans with prices
  POST /stripe/create-portal-session    - create Stripe Customer Portal session
  GET  /stripe/subscription-status      - get current user's subscription status
"""

import logging
import os
import hashlib
from typing import Optional

from fastapi import APIRouter, Depends, Header, HTTPException, Request, status
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session
from slowapi import Limiter
from slowapi.util import get_remote_address

from config.settings import get_settings
from database.session import get_db
from models.subscription import Subscription
from models.user import User
from services.jwt_service import get_current_user
from services.stripe_service import StripeService
from services.payment_webhooks import PaymentWebhookHandler
from services.payment_idempotency import run_idempotent
from utils.api_errors import ApiException
from utils.url_safety import require_safe_redirect_url

logger = logging.getLogger(__name__)

router = APIRouter()
limiter = Limiter(key_func=get_remote_address)
SETTINGS = get_settings()
IS_TESTING = SETTINGS.testing


def rate_limit(rule: str):
    if IS_TESTING:
        def decorator(func):
            return func
        return decorator
    return limiter.limit(rule)


def _stripe_configured() -> bool:
    """Return True if the Stripe secret key is set."""
    return bool(os.getenv("STRIPE_SECRET_KEY"))


def _base_url(request: Request) -> str:
    app_url = SETTINGS.app_url
    if app_url:
        return app_url
    return str(request.base_url).rstrip("/")


# ---------------------------------------------------------------------------
# Request models
# ---------------------------------------------------------------------------

class CheckoutSessionRequest(BaseModel):
    plan_id: str = Field(..., description="Plan identifier: basic, premium, or ultra")
    billing_cycle: str = Field(default="monthly", description="monthly or yearly")
    trial_days: int = Field(default=0, ge=0, le=30, description="Trial days (0-30)")


class PortalSessionRequest(BaseModel):
    return_url: Optional[str] = Field(None, description="URL to redirect after portal session")


# ---------------------------------------------------------------------------
# POST /stripe/create-checkout-session
# ---------------------------------------------------------------------------

@router.post("/stripe/create-checkout-session")
@rate_limit("10/minute")
async def create_checkout_session(
    payload: CheckoutSessionRequest,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Create a Stripe Checkout session for the specified plan.

    Returns the checkout session URL that the frontend should redirect to.
    """
    stripe_service = StripeService()
    plan = stripe_service.get_plan_details(payload.plan_id)
    if not plan:
        raise ApiException(
            status_code=status.HTTP_400_BAD_REQUEST,
            code="unknown_plan",
            message=f"Unknown plan: {payload.plan_id}",
        )

    # Free plan does not require Stripe
    if payload.plan_id == "free":
        return {
            "message": "Free plan does not require payment",
            "plan": "free",
            "checkout_url": None,
        }

    if not _stripe_configured():
        raise ApiException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            code="stripe_not_configured",
            message="Stripe is not configured on this server.",
        )

    price_key = f"stripe_price_id_{payload.billing_cycle}"
    if not plan.get(price_key):
        raise ApiException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            code="stripe_price_not_configured",
            message=f"Stripe Price ID not configured for plan={payload.plan_id} cycle={payload.billing_cycle}.",
        )

    base = _base_url(request)

    try:
        # Prevent multiple active subscriptions for a single user (use the portal for upgrades/downgrades).
        existing = (
            db.query(Subscription)
            .filter_by(user_id=current_user.id)
            .filter(Subscription.status.in_(["active", "trialing", "past_due"]))
            .order_by(Subscription.created_at.desc())
            .first()
        )
        if existing:
            raise ApiException(
                status_code=status.HTTP_400_BAD_REQUEST,
                code="subscription_exists",
                message="An active subscription already exists. Use the billing portal to manage your plan.",
            )

        # Ensure the user has a Stripe customer ID
        customer_id = getattr(current_user, "stripe_customer_id", None)
        if not customer_id:
            customer = stripe_service.create_customer(
                email=current_user.email,
                name=getattr(current_user, "full_name", None),
                metadata={"securewave_user_id": str(current_user.id)},
                idempotency_key=f"sw_stripe_customer_create_{current_user.id}",
            )
            customer_id = customer.id
            current_user.stripe_customer_id = customer_id
            db.commit()

        idempotency_payload = {
            "plan_id": payload.plan_id,
            "billing_cycle": payload.billing_cycle,
            "trial_days": payload.trial_days,
        }

        def _execute(idempotency_key: str):
            session = stripe_service.create_checkout_session(
                customer_id=customer_id,
                plan_id=payload.plan_id,
                billing_cycle=payload.billing_cycle,
                success_url=f"{base}/billing?payment=success&session_id={{CHECKOUT_SESSION_ID}}",
                cancel_url=f"{base}/billing?payment=canceled",
                trial_days=payload.trial_days,
                user_id=current_user.id,
                metadata={"securewave_user_id": str(current_user.id)},
                idempotency_key=idempotency_key,
            )
            return {"checkout_url": session.url, "session_id": session.id}

        outcome = run_idempotent(
            db,
            provider="stripe",
            operation="checkout_session_create",
            user_id=current_user.id,
            request_payload=idempotency_payload,
            execute=_execute,
        )

        response = dict(outcome.response)
        response["replayed"] = outcome.replayed
        return response

    except Exception as e:
        logger.error("Failed to create checkout session: %s", e)
        raise ApiException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            code="checkout_session_failed",
            message="Failed to create checkout session.",
        )


# ---------------------------------------------------------------------------
# POST /stripe/webhook
# ---------------------------------------------------------------------------

@router.post("/stripe/webhook")
@rate_limit("120/minute")
async def stripe_webhook(
    request: Request,
    stripe_signature: Optional[str] = Header(None, alias="Stripe-Signature"),
    db: Session = Depends(get_db),
):
    """
    Receive and verify Stripe webhook events.

    The endpoint reads the raw request body and verifies the Stripe-Signature
    header against the configured STRIPE_WEBHOOK_SECRET. Invalid or missing
    signatures are rejected with 400.
    """
    if not stripe_signature:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Missing Stripe-Signature header",
        )

    if not (os.getenv("STRIPE_WEBHOOK_SECRET") or "").strip():
        raise ApiException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            code="stripe_webhook_not_configured",
            message="STRIPE_WEBHOOK_SECRET is not configured.",
        )

    payload = await request.body()

    try:
        event = StripeService.construct_webhook_event(payload, stripe_signature)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid webhook signature",
        )
    except Exception as e:
        logger.error("Webhook signature verification failed: %s", e)
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Webhook verification error",
        )

    # Process the verified event
    try:
        handler = PaymentWebhookHandler(db)
        payload_hash = hashlib.sha256(payload).hexdigest()
        result = handler.handle_stripe_event(event, payload_hash=payload_hash)
        logger.info("Stripe webhook processed: %s", event.get("type"))
        return JSONResponse(content={"status": "success", "result": result})
    except ValueError as e:
        logger.warning("Rejected webhook event %s: %s", event.get("type"), e)
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid webhook payload replay",
        )
    except Exception as e:
        logger.error("Failed to process webhook event %s: %s", event.get("type"), e)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to process webhook event",
        )


# ---------------------------------------------------------------------------
# GET /stripe/plans
# ---------------------------------------------------------------------------

@router.get("/stripe/plans")
async def get_stripe_plans():
    """
    Return all available subscription plans with pricing details.

    This endpoint does not require authentication so the pricing page can
    display plans to unauthenticated visitors.
    """
    plans = []
    for plan_id, plan_data in StripeService.PLANS.items():
        monthly = plan_data["price_monthly"]
        yearly = plan_data["price_yearly"]

        # Calculate yearly discount safely (avoid division by zero for free tier)
        if monthly > 0:
            yearly_discount = round((1 - (yearly / (monthly * 12))) * 100)
        else:
            yearly_discount = 0

        plans.append({
            "id": plan_id,
            "name": plan_data["name"],
            "features": plan_data.get("features", []),
            "pricing": {
                "monthly": monthly,
                "yearly": yearly,
                "yearly_discount": yearly_discount,
            },
            "requires_payment": plan_id != "free",
        })

    return {"plans": plans}


# ---------------------------------------------------------------------------
# POST /stripe/create-portal-session
# ---------------------------------------------------------------------------

@router.post("/stripe/create-portal-session")
@rate_limit("10/minute")
async def create_portal_session(
    payload: PortalSessionRequest,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Create a Stripe Customer Portal session.

    The portal allows customers to manage their subscription, update
    payment methods, view invoices, and cancel.
    """
    stripe_service = StripeService()
    base = _base_url(request)
    return_url = require_safe_redirect_url(
        base_url=base,
        candidate=payload.return_url or "/billing",
        field_name="return_url",
    )

    if not _stripe_configured():
        raise ApiException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            code="stripe_not_configured",
            message="Stripe is not configured on this server.",
        )

    customer_id = getattr(current_user, "stripe_customer_id", None)
    if not customer_id:
        raise ApiException(
            status_code=status.HTTP_400_BAD_REQUEST,
            code="no_billing_account",
            message="No billing account found. Please subscribe to a plan first.",
        )

    try:
        session = stripe_service.create_billing_portal_session(
            customer_id=customer_id,
            return_url=return_url,
        )
        return {"url": session.url}
    except Exception as e:
        logger.error("Failed to create portal session: %s", e)
        raise ApiException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            code="portal_session_failed",
            message="Failed to create billing portal session.",
        )


# ---------------------------------------------------------------------------
# GET /stripe/subscription-status
# ---------------------------------------------------------------------------

@router.get("/stripe/subscription-status")
async def get_subscription_status(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Return the current user's subscription status.

    Checks the local database first. Returns plan details, billing cycle,
    and whether the subscription is active.
    """
    from models.subscription import Subscription

    subscription = (
        db.query(Subscription)
        .filter_by(user_id=current_user.id)
        .filter(Subscription.status.in_(["active", "trialing", "past_due"]))
        .order_by(Subscription.created_at.desc())
        .first()
    )

    if not subscription:
        return {
            "has_subscription": False,
            "plan": "free",
            "status": "none",
            "message": "No active subscription -- using free tier",
        }

    return {
        "has_subscription": True,
        "subscription_id": subscription.id,
        "plan": subscription.plan_id,
        "plan_name": subscription.plan_name,
        "status": subscription.status,
        "provider": subscription.provider,
        "billing_cycle": subscription.billing_cycle,
        "amount": subscription.amount,
        "currency": subscription.currency,
        "next_billing_date": (
            subscription.next_billing_date.isoformat()
            if subscription.next_billing_date
            else None
        ),
        "cancel_at_period_end": subscription.cancel_at_period_end,
        "is_active": subscription.is_active,
    }
