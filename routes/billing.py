"""
SecureWave VPN - Billing and Subscription API Routes
FastAPI endpoints for payment processing and subscription management
"""

import logging
from typing import Dict, List, Optional
from fastapi import APIRouter, Depends, HTTPException, Request, Header, status
from fastapi.responses import JSONResponse, RedirectResponse
from sqlalchemy.orm import Session
from pydantic import BaseModel, Field

from database.session import get_db
from services.subscription_manager import SubscriptionManager
from services.billing_automation import BillingAutomationService
from services.stripe_service import StripeService
from services.paypal_service import PayPalService
from services.payment_webhooks import PaymentWebhookHandler
from models.user import User
from services.jwt_service import get_current_user

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/billing", tags=["Billing"])


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
async def create_subscription(
    request: CreateSubscriptionRequest,
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
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="User already has an active subscription"
            )

        if request.provider == "stripe":
            # Create Stripe subscription
            subscription = subscription_manager.create_subscription_stripe(
                user_id=current_user.id,
                plan_id=request.plan_id,
                billing_cycle=request.billing_cycle,
                payment_method_id=request.payment_method_id,
                trial_days=request.trial_days
            )

            return {
                "subscription_id": subscription.id,
                "status": subscription.status,
                "provider": "stripe",
                "message": "Subscription created successfully"
            }

        elif request.provider == "paypal":
            # Create PayPal subscription (returns approval URL)
            result = subscription_manager.create_subscription_paypal(
                user_id=current_user.id,
                plan_id=request.plan_id,
                billing_cycle=request.billing_cycle,
                return_url=request.return_url or f"{request.return_url}/billing/success",
                cancel_url=request.cancel_url or f"{request.cancel_url}/billing/cancel"
            )

            return {
                "subscription_id": result["subscription_id"],
                "paypal_subscription_id": result["paypal_subscription_id"],
                "approval_url": result["approval_url"],
                "status": result["status"],
                "provider": "paypal",
                "message": "Please complete payment via PayPal"
            }

        else:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Unsupported payment provider: {request.provider}"
            )

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
async def upgrade_subscription(
    subscription_id: int,
    request: UpgradeSubscriptionRequest,
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

        # Upgrade subscription
        updated_subscription = subscription_manager.upgrade_subscription(
            subscription_id=subscription_id,
            new_plan_id=request.new_plan_id,
            billing_cycle=request.billing_cycle
        )

        return {
            "message": "Subscription upgraded successfully",
            "subscription": {
                "id": updated_subscription.id,
                "plan_name": updated_subscription.plan_name,
                "amount": updated_subscription.amount,
                "billing_cycle": updated_subscription.billing_cycle,
            }
        }

    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))
    except Exception as e:
        logger.error(f"✗ Failed to upgrade subscription: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to upgrade subscription"
        )


@router.post("/subscriptions/{subscription_id}/cancel")
async def cancel_subscription(
    subscription_id: int,
    request: CancelSubscriptionRequest,
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

        # Cancel subscription
        canceled_subscription = subscription_manager.cancel_subscription(
            subscription_id=subscription_id,
            cancel_at_period_end=request.cancel_at_period_end,
            reason=request.reason
        )

        message = "Subscription will be canceled at period end" if request.cancel_at_period_end else "Subscription canceled immediately"

        return {
            "message": message,
            "subscription": {
                "id": canceled_subscription.id,
                "status": canceled_subscription.status,
                "cancel_at_period_end": canceled_subscription.cancel_at_period_end,
                "current_period_end": canceled_subscription.current_period_end.isoformat() if canceled_subscription.current_period_end else None,
            }
        }

    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))
    except Exception as e:
        logger.error(f"✗ Failed to cancel subscription: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to cancel subscription"
        )


@router.post("/subscriptions/{subscription_id}/reactivate")
async def reactivate_subscription(
    subscription_id: int,
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

        # Reactivate subscription
        reactivated_subscription = subscription_manager.reactivate_subscription(subscription_id)

        return {
            "message": "Subscription reactivated successfully",
            "subscription": {
                "id": reactivated_subscription.id,
                "status": reactivated_subscription.status,
                "cancel_at_period_end": reactivated_subscription.cancel_at_period_end,
            }
        }

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
async def create_billing_portal_session(
    return_url: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Create Stripe billing portal session
    Redirects user to Stripe-hosted billing portal
    """
    try:
        subscription_manager = SubscriptionManager(db)

        portal_url = subscription_manager.create_billing_portal_session(
            user_id=current_user.id,
            return_url=return_url
        )

        if not portal_url:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="No Stripe customer found. Please create a subscription first."
            )

        return {"url": portal_url}

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
            plans.append({
                "id": plan_id,
                "name": plan_data["name"],
                "description": plan_data.get("description", ""),
                "features": plan_data.get("features", []),
                "pricing": {
                    "monthly": plan_data["price_monthly"],
                    "yearly": plan_data["price_yearly"],
                    "yearly_discount": round((1 - (plan_data["price_yearly"] / (plan_data["price_monthly"] * 12))) * 100)
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
# WEBHOOK ENDPOINTS
# ===========================

@router.post("/webhooks/stripe", include_in_schema=False)
async def stripe_webhook(
    request: Request,
    stripe_signature: str = Header(None, alias="Stripe-Signature"),
    db: Session = Depends(get_db)
):
    """
    Handle Stripe webhook events
    Verifies signature and processes payment events
    """
    try:
        # Get raw body
        payload = await request.body()

        # Verify webhook signature
        stripe_service = StripeService()
        event = stripe_service.construct_webhook_event(payload, stripe_signature)

        # Process event
        webhook_handler = PaymentWebhookHandler(db)
        result = webhook_handler.handle_stripe_event(event)

        logger.info(f"✓ Processed Stripe webhook: {event['type']}")
        return JSONResponse(content={"status": "success", "result": result})

    except ValueError as e:
        logger.error(f"✗ Invalid Stripe webhook signature: {e}")
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid signature")
    except Exception as e:
        logger.error(f"✗ Failed to process Stripe webhook: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to process webhook"
        )


@router.post("/webhooks/paypal", include_in_schema=False)
async def paypal_webhook(
    request: Request,
    db: Session = Depends(get_db)
):
    """
    Handle PayPal webhook events
    Verifies signature and processes payment events
    """
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
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Get billing health report (admin only)
    Returns comprehensive billing metrics
    """
    try:
        # Check if user is admin
        if not current_user.is_admin:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Admin access required")

        billing_service = BillingAutomationService(db)
        report = billing_service.generate_billing_health_report()

        return report

    except Exception as e:
        logger.error(f"✗ Failed to generate health report: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to generate health report"
        )


@router.post("/admin/sync-subscriptions", include_in_schema=False)
async def sync_all_subscriptions(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Sync all subscriptions with payment providers (admin only)"""
    try:
        # Check if user is admin
        if not current_user.is_admin:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Admin access required")

        billing_service = BillingAutomationService(db)
        result = billing_service.sync_all_active_subscriptions()

        return result

    except Exception as e:
        logger.error(f"✗ Failed to sync subscriptions: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to sync subscriptions"
        )
