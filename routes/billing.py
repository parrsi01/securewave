"""
SecureWave VPN - Billing and Subscription API Routes
FastAPI endpoints for payment processing and subscription management
"""

import logging
import os
import hashlib
from datetime import datetime, timedelta
from typing import Dict, List, Optional
from fastapi import APIRouter, Depends, HTTPException, Request, Header, status
from fastapi.responses import JSONResponse, RedirectResponse
from sqlalchemy.orm import Session
from pydantic import BaseModel, Field

from config.settings import get_settings
from database.session import get_db
from services.subscription_manager import SubscriptionManager
from services.billing_automation import BillingAutomationService
from services.stripe_service import StripeService
from services.paypal_service import PayPalService
from services.payment_webhooks import PaymentWebhookHandler
from models.subscription import Subscription
from models.user import User
from services.jwt_service import get_current_user
from services.payment_idempotency import run_idempotent
from utils.api_errors import ApiException
from utils.url_safety import require_safe_redirect_url
from utils.structured_logging import log_admin_action, sanitize_for_log
from slowapi import Limiter
from slowapi.util import get_remote_address

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/billing", tags=["Billing"])
SETTINGS = get_settings()
limiter = Limiter(key_func=get_remote_address, storage_uri=SETTINGS.redis_url)
IS_TESTING = SETTINGS.testing


def rate_limit(rule: str):
    if IS_TESTING:
        def decorator(func):
            return func
        return decorator
    return limiter.limit(rule)


def _missing_provider_config(provider: str) -> bool:
    if provider == "stripe":
        return not os.getenv("STRIPE_SECRET_KEY")
    if provider == "paypal":
        return not os.getenv("PAYPAL_CLIENT_ID") or not os.getenv("PAYPAL_CLIENT_SECRET")
    return True


def _base_url(request: Request) -> str:
    app_url = SETTINGS.app_url
    if app_url:
        return app_url
    return str(request.base_url).rstrip("/")


# ===========================
# REQUEST/RESPONSE MODELS
# ===========================

class CreateSubscriptionRequest(BaseModel):
    """Request model for creating a subscription"""
    plan_id: str = Field(..., description="Plan ID: basic, premium, ultra")
    billing_cycle: str = Field(default="monthly", description="Billing cycle: monthly or yearly")
    payment_method_id: Optional[str] = Field(None, description="Stripe payment method ID (for Stripe)")
    trial_days: int = Field(default=0, description="Trial period in days")
    provider: str = Field(default="stripe", description="Payment provider: stripe or paypal")
    return_url: Optional[str] = Field(None, description="Return URL (for PayPal)")
    cancel_url: Optional[str] = Field(None, description="Cancel URL (for PayPal)")


class UpgradeSubscriptionRequest(BaseModel):
    """Request model for upgrading a subscription"""
    new_plan_id: str = Field(..., description="New plan ID")
    billing_cycle: Optional[str] = Field(None, description="New billing cycle (optional)")


class CancelSubscriptionRequest(BaseModel):
    """Request model for canceling a subscription"""
    cancel_at_period_end: bool = Field(default=True, description="Cancel at end of billing period")
    reason: Optional[str] = Field(None, description="Cancellation reason")


class SubscriptionResponse(BaseModel):
    """Response model for subscription data"""
    id: int
    user_id: int
    plan_id: str
    plan_name: str
    provider: str
    status: str
    amount: float
    currency: str
    billing_cycle: str
    next_billing_date: Optional[str]
    is_active: bool
    cancel_at_period_end: bool


# ===========================
# SUBSCRIPTION ENDPOINTS
# ===========================

@router.post("/subscriptions", response_model=Dict, status_code=status.HTTP_201_CREATED)
@rate_limit("10/minute")
async def create_subscription(
    payload: CreateSubscriptionRequest,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Create a new subscription

    For Stripe: Immediately creates subscription with payment method
    For PayPal: Returns approval URL for user to complete payment
    """
    try:
        subscription_manager = SubscriptionManager(db)

        # Check if user already has active subscription
        existing = subscription_manager.get_user_subscription(current_user.id)
        if existing and existing.is_active:
            raise ApiException(
                status_code=status.HTTP_400_BAD_REQUEST,
                code="subscription_exists",
                message="User already has an active subscription.",
            )

        if _missing_provider_config(payload.provider):
            raise ApiException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                code="payment_provider_not_configured",
                message="Payment provider is not configured on this server.",
                details={"provider": payload.provider},
            )

        base_url = _base_url(request)
        safe_return_url = None
        safe_cancel_url = None
        if payload.provider == "paypal":
            safe_return_url = require_safe_redirect_url(
                base_url=base_url,
                candidate=payload.return_url or "/billing?payment=success",
                field_name="return_url",
            )
            safe_cancel_url = require_safe_redirect_url(
                base_url=base_url,
                candidate=payload.cancel_url or "/billing?payment=canceled",
                field_name="cancel_url",
            )

        idempotency_payload = {
            "provider": payload.provider,
            "plan_id": payload.plan_id,
            "billing_cycle": payload.billing_cycle,
            "trial_days": payload.trial_days,
            "payment_method_id": payload.payment_method_id,
            "return_url": safe_return_url,
            "cancel_url": safe_cancel_url,
        }

        def _execute(idempotency_key: str):
            if payload.provider == "stripe":
                subscription = subscription_manager.create_subscription_stripe(
                    user_id=current_user.id,
                    plan_id=payload.plan_id,
                    billing_cycle=payload.billing_cycle,
                    payment_method_id=payload.payment_method_id,
                    trial_days=payload.trial_days,
                    idempotency_key=idempotency_key,
                )
                return {
                    "subscription_id": subscription.id,
                    "status": subscription.status,
                    "provider": "stripe",
                    "message": "Subscription created successfully",
                }

            if payload.provider == "paypal":
                result = subscription_manager.create_subscription_paypal(
                    user_id=current_user.id,
                    plan_id=payload.plan_id,
                    billing_cycle=payload.billing_cycle,
                    return_url=safe_return_url or "/billing?payment=success",
                    cancel_url=safe_cancel_url or "/billing?payment=canceled",
                )
                return {
                    "subscription_id": result["subscription_id"],
                    "paypal_subscription_id": result["paypal_subscription_id"],
                    "approval_url": result["approval_url"],
                    "status": result["status"],
                    "provider": "paypal",
                    "message": "Please complete payment via PayPal",
                }

            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Unsupported payment provider: {payload.provider}",
            )

        outcome = run_idempotent(
            db,
            provider=payload.provider,
            operation="subscription_create",
            user_id=current_user.id,
            request_payload=idempotency_payload,
            execute=_execute,
        )
        response = dict(outcome.response)
        response["replayed"] = outcome.replayed
        return response

    except HTTPException:
        raise
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))
    except Exception as e:
        logger.error(f"✗ Failed to create subscription: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to create subscription"
        )


@router.get("/subscriptions/current")
async def get_current_subscription(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Get user's current active subscription"""
    try:
        subscription_manager = SubscriptionManager(db)
        subscription = subscription_manager.get_user_subscription(current_user.id)

        if not subscription:
            return {"subscription": None, "message": "No active subscription"}

        return {
            "subscription": {
                "id": subscription.id,
                "plan_id": subscription.plan_id,
                "plan_name": subscription.plan_name,
                "provider": subscription.provider,
                "status": subscription.status,
                "amount": subscription.amount,
                "currency": subscription.currency,
                "billing_cycle": subscription.billing_cycle,
                "next_billing_date": subscription.next_billing_date.isoformat() if subscription.next_billing_date else None,
                "is_active": subscription.is_active,
                "cancel_at_period_end": subscription.cancel_at_period_end,
                "trial_end": subscription.trial_end.isoformat() if subscription.trial_end else None,
            }
        }

    except Exception as e:
        logger.error(f"✗ Failed to get subscription: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to retrieve subscription"
        )


@router.get("/subscriptions/history")
async def get_subscription_history(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Get user's subscription history"""
    try:
        subscription_manager = SubscriptionManager(db)
        subscriptions = subscription_manager.get_user_subscriptions(current_user.id)

        return {
            "subscriptions": [
                {
                    "id": sub.id,
                    "plan_name": sub.plan_name,
                    "provider": sub.provider,
                    "status": sub.status,
                    "amount": sub.amount,
                    "billing_cycle": sub.billing_cycle,
                    "created_at": sub.created_at.isoformat(),
                    "canceled_at": sub.canceled_at.isoformat() if sub.canceled_at else None,
                }
                for sub in subscriptions
            ]
        }

    except Exception as e:
        logger.error(f"✗ Failed to get subscription history: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to retrieve subscription history"
        )


@router.put("/subscriptions/{subscription_id}/upgrade")
@rate_limit("10/minute")
async def upgrade_subscription(
    subscription_id: int,
    payload: UpgradeSubscriptionRequest,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Upgrade or downgrade subscription plan"""
    try:
        subscription_manager = SubscriptionManager(db)

        # Verify subscription belongs to user
        subscription = subscription_manager.get_subscription(subscription_id)
        if not subscription or subscription.user_id != current_user.id:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Subscription not found")

        if _missing_provider_config(subscription.provider):
            raise ApiException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                code="payment_provider_not_configured",
                message="Payment provider is not configured on this server.",
                details={"provider": subscription.provider},
            )

        idempotency_payload = {
            "subscription_id": subscription_id,
            "new_plan_id": payload.new_plan_id,
            "billing_cycle": payload.billing_cycle,
        }

        def _execute(idempotency_key: str):
            updated_subscription = subscription_manager.upgrade_subscription(
                subscription_id=subscription_id,
                new_plan_id=payload.new_plan_id,
                billing_cycle=payload.billing_cycle,
                idempotency_key=idempotency_key,
            )
            return {
                "message": "Subscription upgraded successfully",
                "subscription": {
                    "id": updated_subscription.id,
                    "plan_name": updated_subscription.plan_name,
                    "amount": updated_subscription.amount,
                    "billing_cycle": updated_subscription.billing_cycle,
                },
            }

        outcome = run_idempotent(
            db,
            provider=subscription.provider,
            operation="subscription_upgrade",
            user_id=current_user.id,
            request_payload=idempotency_payload,
            execute=_execute,
        )
        response = dict(outcome.response)
        response["replayed"] = outcome.replayed
        return response

    except HTTPException:
        raise
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))
    except Exception as e:
        logger.error(f"✗ Failed to upgrade subscription: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to upgrade subscription"
        )


@router.post("/subscriptions/{subscription_id}/cancel")
@rate_limit("10/minute")
async def cancel_subscription(
    subscription_id: int,
    payload: CancelSubscriptionRequest,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Cancel subscription"""
    try:
        subscription_manager = SubscriptionManager(db)

        # Verify subscription belongs to user
        subscription = subscription_manager.get_subscription(subscription_id)
        if not subscription or subscription.user_id != current_user.id:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Subscription not found")

        if _missing_provider_config(subscription.provider):
            raise ApiException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                code="payment_provider_not_configured",
                message="Payment provider is not configured on this server.",
                details={"provider": subscription.provider},
            )

        idempotency_payload = {
            "subscription_id": subscription_id,
            "cancel_at_period_end": payload.cancel_at_period_end,
            "reason": payload.reason,
        }

        def _execute(idempotency_key: str):
            canceled_subscription = subscription_manager.cancel_subscription(
                subscription_id=subscription_id,
                cancel_at_period_end=payload.cancel_at_period_end,
                reason=payload.reason,
                idempotency_key=idempotency_key,
            )

            message = (
                "Subscription will be canceled at period end"
                if payload.cancel_at_period_end
                else "Subscription canceled immediately"
            )

            return {
                "message": message,
                "subscription": {
                    "id": canceled_subscription.id,
                    "status": canceled_subscription.status,
                    "cancel_at_period_end": canceled_subscription.cancel_at_period_end,
                    "current_period_end": canceled_subscription.current_period_end.isoformat() if canceled_subscription.current_period_end else None,
                },
            }

        outcome = run_idempotent(
            db,
            provider=subscription.provider,
            operation="subscription_cancel",
            user_id=current_user.id,
            request_payload=idempotency_payload,
            execute=_execute,
        )
        response = dict(outcome.response)
        response["replayed"] = outcome.replayed
        return response

    except HTTPException:
        raise
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))
    except Exception as e:
        logger.error(f"✗ Failed to cancel subscription: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to cancel subscription"
        )


@router.post("/subscriptions/{subscription_id}/reactivate")
@rate_limit("10/minute")
async def reactivate_subscription(
    subscription_id: int,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Reactivate a canceled subscription (before period end)"""
    try:
        subscription_manager = SubscriptionManager(db)

        # Verify subscription belongs to user
        subscription = subscription_manager.get_subscription(subscription_id)
        if not subscription or subscription.user_id != current_user.id:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Subscription not found")

        if _missing_provider_config(subscription.provider):
            raise ApiException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                code="payment_provider_not_configured",
                message="Payment provider is not configured on this server.",
                details={"provider": subscription.provider},
            )

        idempotency_payload = {"subscription_id": subscription_id}

        def _execute(idempotency_key: str):
            reactivated_subscription = subscription_manager.reactivate_subscription(
                subscription_id,
                idempotency_key=idempotency_key,
            )
            return {
                "message": "Subscription reactivated successfully",
                "subscription": {
                    "id": reactivated_subscription.id,
                    "status": reactivated_subscription.status,
                    "cancel_at_period_end": reactivated_subscription.cancel_at_period_end,
                },
            }

        outcome = run_idempotent(
            db,
            provider=subscription.provider,
            operation="subscription_reactivate",
            user_id=current_user.id,
            request_payload=idempotency_payload,
            execute=_execute,
        )
        response = dict(outcome.response)
        response["replayed"] = outcome.replayed
        return response

    except HTTPException:
        raise
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))
    except Exception as e:
        logger.error(f"✗ Failed to reactivate subscription: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to reactivate subscription"
        )


# ===========================
# BILLING PORTAL
# ===========================

@router.get("/portal")
@rate_limit("20/minute")
async def create_billing_portal_session(
    request: Request,
    return_url: Optional[str] = None,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Create Stripe billing portal session
    Redirects user to Stripe-hosted billing portal
    """
    try:
        subscription_manager = SubscriptionManager(db)

        if _missing_provider_config("stripe"):
            raise ApiException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                code="stripe_not_configured",
                message="Stripe is not configured on this server.",
            )

        base_url = _base_url(request)
        safe_return_url = require_safe_redirect_url(
            base_url=base_url,
            candidate=return_url or "/billing",
            field_name="return_url",
        )

        portal_url = subscription_manager.create_billing_portal_session(
            user_id=current_user.id,
            return_url=safe_return_url
        )

        if not portal_url:
            raise ApiException(
                status_code=status.HTTP_400_BAD_REQUEST,
                code="no_billing_account",
                message="No Stripe customer found. Please create a subscription first.",
            )

        return {"url": portal_url}

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"✗ Failed to create billing portal session: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to create billing portal session"
        )


# ===========================
# INVOICE ENDPOINTS
# ===========================

@router.get("/invoices")
async def get_invoices(
    limit: int = 10,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Get user's invoices"""
    try:
        subscription_manager = SubscriptionManager(db)
        invoices = subscription_manager.get_user_invoices(current_user.id, limit=limit)

        return {
            "invoices": [invoice.to_dict() for invoice in invoices]
        }

    except Exception as e:
        logger.error(f"✗ Failed to get invoices: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to retrieve invoices"
        )


@router.get("/invoices/{invoice_id}")
async def get_invoice(
    invoice_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Get specific invoice details"""
    try:
        subscription_manager = SubscriptionManager(db)
        invoice = subscription_manager.get_invoice(invoice_id)

        if not invoice or invoice.user_id != current_user.id:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Invoice not found")

        return {"invoice": invoice.to_dict()}

    except Exception as e:
        logger.error(f"✗ Failed to get invoice: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to retrieve invoice"
        )


# ===========================
# PLANS ENDPOINT
# ===========================

@router.get("/plans")
async def get_available_plans():
    """Get available subscription plans"""
    try:
        stripe_service = StripeService()

        plans = []
        for plan_id, plan_data in stripe_service.PLANS.items():
            monthly = plan_data["price_monthly"]
            yearly = plan_data["price_yearly"]
            if monthly > 0:
                yearly_discount = round((1 - (yearly / (monthly * 12))) * 100)
            else:
                yearly_discount = 0

            plans.append({
                "id": plan_id,
                "name": plan_data["name"],
                "description": plan_data.get("description", ""),
                "features": plan_data.get("features", []),
                "pricing": {
                    "monthly": monthly,
                    "yearly": yearly,
                    "yearly_discount": yearly_discount,
                }
            })

        return {"plans": plans}

    except Exception as e:
        logger.error(f"✗ Failed to get plans: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to retrieve plans"
        )


# ===========================
# CHECKOUT SESSION
# ===========================

class CheckoutRequest(BaseModel):
    """Request for creating a Stripe Checkout session"""
    plan_id: str = Field(..., description="Plan ID: basic, premium, ultra")
    billing_cycle: str = Field(default="monthly", description="monthly or yearly")
    success_url: Optional[str] = Field(None, description="Redirect URL on success")
    cancel_url: Optional[str] = Field(None, description="Redirect URL on cancel")
    trial_days: int = Field(default=0, ge=0, le=30, description="Trial period (0-30 days)")


@router.post("/checkout-session")
@rate_limit("10/minute")
async def create_checkout_session(
    payload: CheckoutRequest,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Create a Stripe Checkout session.
    Returns a URL to redirect the user to Stripe's hosted payment page.
    """
    try:
        from services.stripe_service import stripe_mode_label

        if _missing_provider_config("stripe"):
            raise ApiException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                code="stripe_not_configured",
                message="Stripe is not configured on this server.",
            )

        # Verify plan exists
        plan = StripeService.get_plan_details(payload.plan_id)
        if not plan:
            raise ApiException(
                status_code=status.HTTP_400_BAD_REQUEST,
                code="unknown_plan",
                message="Invalid plan ID",
            )

        price_key = f"stripe_price_id_{payload.billing_cycle}"
        if not plan.get(price_key):
            raise ApiException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                code="stripe_price_not_configured",
                message=f"Stripe Price ID not configured for plan={payload.plan_id} cycle={payload.billing_cycle}.",
            )

        # Check existing active subscription
        subscription_manager = SubscriptionManager(db)
        existing = subscription_manager.get_user_subscription(current_user.id)
        if existing and existing.is_active:
            raise ApiException(
                status_code=status.HTTP_400_BAD_REQUEST,
                code="subscription_exists",
                message="User already has an active subscription.",
            )

        # Ensure user has a Stripe customer ID
        stripe_service = StripeService()
        stripe_customer_id = getattr(current_user, "stripe_customer_id", None)
        if not stripe_customer_id:
            customer = stripe_service.create_customer(
                email=current_user.email,
                name=getattr(current_user, "full_name", current_user.email),
                metadata={"securewave_user_id": str(current_user.id)},
                idempotency_key=f"sw_stripe_customer_create_{current_user.id}",
            )
            stripe_customer_id = customer.id
            current_user.stripe_customer_id = stripe_customer_id
            db.commit()

        base = _base_url(request)
        success_url = require_safe_redirect_url(
            base_url=base,
            candidate=payload.success_url or "/billing?payment=success&session_id={CHECKOUT_SESSION_ID}",
            field_name="success_url",
        )
        cancel_url = require_safe_redirect_url(
            base_url=base,
            candidate=payload.cancel_url or "/billing?payment=canceled",
            field_name="cancel_url",
        )

        idempotency_payload = {
            "plan_id": payload.plan_id,
            "billing_cycle": payload.billing_cycle,
            "trial_days": payload.trial_days,
            "success_url": success_url,
            "cancel_url": cancel_url,
        }

        def _execute(idempotency_key: str):
            session = stripe_service.create_checkout_session(
                customer_id=stripe_customer_id,
                plan_id=payload.plan_id,
                billing_cycle=payload.billing_cycle,
                success_url=success_url,
                cancel_url=cancel_url,
                trial_days=payload.trial_days,
                user_id=current_user.id,
                metadata={"securewave_user_id": str(current_user.id)},
                idempotency_key=idempotency_key,
            )
            return {
                "session_id": session.id,
                "url": session.url,
                "mode": stripe_mode_label(),
            }

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
        logger.info(
            "Checkout session created (%s mode) for user %s (replayed=%s)",
            stripe_mode_label(),
            current_user.id,
            outcome.replayed,
        )
        return response

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to create checkout session: {e}")
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Failed to create checkout session")


@router.get("/stripe-status")
async def get_stripe_status(current_user: User = Depends(get_current_user)):
    """Returns Stripe configuration status (test/live/unconfigured). Requires authentication."""
    from services.stripe_service import stripe_mode_label
    configured = bool(os.getenv("STRIPE_SECRET_KEY"))
    webhook_configured = bool(os.getenv("STRIPE_WEBHOOK_SECRET"))
    return {
        "configured": configured,
        "mode": stripe_mode_label(),
        "webhook_configured": webhook_configured,
    }


# ===========================
# WEBHOOK ENDPOINTS
# ===========================
# NOTE: POST /api/billing/webhooks/stripe has been removed.
# The canonical Stripe webhook endpoint is POST /api/payments/stripe/webhook
# (mounted via payment_stripe router in main.py).


@router.post("/webhooks/paypal", include_in_schema=False)
@rate_limit("120/minute")
async def paypal_webhook(
    request: Request,
    db: Session = Depends(get_db)
):
    """
    Handle PayPal webhook events
    Verifies signature and processes payment events
    """
    if _missing_provider_config("paypal") or not os.getenv("PAYPAL_WEBHOOK_ID"):
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="PayPal webhook processing is not configured",
        )
    try:
        # Get raw body and headers
        payload = await request.body()
        headers = dict(request.headers)

        # Verify webhook signature
        paypal_service = PayPalService()
        if not paypal_service.verify_webhook_signature(headers, payload.decode()):
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid signature")

        # Parse event
        import json
        event = json.loads(payload)

        # Process event
        webhook_handler = PaymentWebhookHandler(db)
        result = webhook_handler.handle_paypal_event(event)

        logger.info(f"✓ Processed PayPal webhook: {event.get('event_type')}")
        return JSONResponse(content={"status": "success", "result": result})

    except ValueError as e:
        logger.error(f"✗ Invalid PayPal webhook: {e}")
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))
    except Exception as e:
        logger.error(f"✗ Failed to process PayPal webhook: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to process webhook"
        )


# ===========================
# ADMIN ENDPOINTS
# ===========================

@router.get("/admin/health-report", include_in_schema=False)
async def get_billing_health_report(
    request: Request,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Get billing health report (admin only)
    Returns comprehensive billing metrics
    """
    ip_address = request.client.host if request.client else None
    try:
        # Check if user is admin
        if not current_user.is_admin:
            log_admin_action("billing_health_report", current_user.id, ip_address, "denied")
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Admin access required")

        billing_service = BillingAutomationService(db)
        report = billing_service.generate_billing_health_report()
        log_admin_action("billing_health_report", current_user.id, ip_address, "success")

        return report

    except HTTPException:
        raise
    except Exception as e:
        logger.error("Failed to generate health report: %s", sanitize_for_log(str(e)))
        log_admin_action("billing_health_report", current_user.id, ip_address, "error")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to generate health report"
        )


@router.post("/admin/sync-subscriptions", include_in_schema=False)
async def sync_all_subscriptions(
    request: Request,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Sync all subscriptions with payment providers (admin only)"""
    ip_address = request.client.host if request.client else None
    try:
        # Check if user is admin
        if not current_user.is_admin:
            log_admin_action("billing_sync_subscriptions", current_user.id, ip_address, "denied")
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Admin access required")

        billing_service = BillingAutomationService(db)
        result = billing_service.sync_all_active_subscriptions()
        log_admin_action("billing_sync_subscriptions", current_user.id, ip_address, "success")

        return result

    except HTTPException:
        raise
    except Exception as e:
        logger.error("Failed to sync subscriptions: %s", sanitize_for_log(str(e)))
        log_admin_action("billing_sync_subscriptions", current_user.id, ip_address, "error")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to sync subscriptions"
        )
