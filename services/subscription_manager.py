"""
SecureWave VPN - Subscription Management Service
Orchestrates subscription operations across Stripe and PayPal
"""

import logging
from typing import Dict, Optional, List
from datetime import datetime, timedelta
from sqlalchemy.orm import Session

from models.subscription import Subscription
from models.invoice import Invoice
from models.user import User
from services.stripe_service import StripeService
from services.paypal_service import PayPalService

logger = logging.getLogger(__name__)


class SubscriptionManager:
    """
    High-level subscription management service
    Handles subscription operations across multiple payment providers
    """

    def __init__(self, db: Session):
        """
        Initialize subscription manager

        Args:
            db: Database session
        """
        self.db = db
        self.stripe = StripeService()
        self.paypal = PayPalService()

    # ===========================
    # SUBSCRIPTION CREATION
    # ===========================

    def create_subscription_stripe(
        self,
        user_id: int,
        plan_id: str,
        billing_cycle: str = "monthly",
        payment_method_id: Optional[str] = None,
        trial_days: int = 0
    ) -> Subscription:
        """
        Create Stripe subscription

        Args:
            user_id: User ID
            plan_id: Plan identifier (basic, premium, ultra)
            billing_cycle: monthly or yearly
            payment_method_id: Stripe payment method ID
            trial_days: Trial period in days

        Returns:
            Subscription object
        """
        try:
            user = self.db.query(User).filter_by(id=user_id).first()
            if not user:
                raise ValueError(f"User not found: {user_id}")

            # Get or create Stripe customer
            stripe_customer_id = user.stripe_customer_id

            if not stripe_customer_id:
                customer = self.stripe.create_customer(
                    email=user.email,
                    name=user.full_name,
                    metadata={"user_id": user_id}
                )
                stripe_customer_id = customer.id
                user.stripe_customer_id = stripe_customer_id
                self.db.commit()

            # Attach payment method if provided
            if payment_method_id:
                self.stripe.attach_payment_method(stripe_customer_id, payment_method_id)

            # Create Stripe subscription
            plan = self.stripe.get_plan_details(plan_id)
            stripe_sub = self.stripe.create_subscription(
                customer_id=stripe_customer_id,
                plan_id=plan_id,
                billing_cycle=billing_cycle,
                trial_days=trial_days,
                payment_method_id=payment_method_id,
                metadata={"user_id": user_id}
            )

            # Create database subscription record
            subscription = Subscription(
                user_id=user_id,
                plan_id=plan_id,
                plan_name=plan["name"],
                provider="stripe",
                status=stripe_sub.status,
                stripe_customer_id=stripe_customer_id,
                stripe_subscription_id=stripe_sub.id,
                stripe_payment_method_id=payment_method_id,
                amount=plan[f"price_{billing_cycle}"],
                currency="usd",
                billing_cycle=billing_cycle,
                current_period_start=datetime.fromtimestamp(stripe_sub.current_period_start),
                current_period_end=datetime.fromtimestamp(stripe_sub.current_period_end),
                next_billing_date=datetime.fromtimestamp(stripe_sub.current_period_end),
                auto_renew=True,
            )

            # Handle trial period
            if stripe_sub.trial_end:
                subscription.trial_start = datetime.fromtimestamp(stripe_sub.trial_start)
                subscription.trial_end = datetime.fromtimestamp(stripe_sub.trial_end)
                subscription.status = "trialing"

            self.db.add(subscription)
            self.db.commit()
            self.db.refresh(subscription)

            logger.info(f"✓ Stripe subscription created: {subscription.id} (user: {user_id}, plan: {plan_id})")
            return subscription

        except Exception as e:
            self.db.rollback()
            logger.error(f"✗ Failed to create Stripe subscription: {e}")
            raise

    def create_subscription_paypal(
        self,
        user_id: int,
        plan_id: str,
        billing_cycle: str = "monthly",
        return_url: str = "",
        cancel_url: str = ""
    ) -> Dict:
        """
        Create PayPal subscription (returns approval URL)

        Args:
            user_id: User ID
            plan_id: Plan identifier
            billing_cycle: monthly or yearly
            return_url: Return URL after approval
            cancel_url: Cancel URL

        Returns:
            Dict with subscription_id and approval_url
        """
        try:
            user = self.db.query(User).filter_by(id=user_id).first()
            if not user:
                raise ValueError(f"User not found: {user_id}")

            # Create PayPal subscription
            plan = self.paypal.get_plan_details(plan_id)
            paypal_sub = self.paypal.create_subscription(
                plan_id=plan_id,
                billing_cycle=billing_cycle,
                subscriber_email=user.email,
                subscriber_name={
                    "given_name": user.full_name.split()[0] if user.full_name else "",
                    "surname": " ".join(user.full_name.split()[1:]) if user.full_name else ""
                },
                return_url=return_url,
                cancel_url=cancel_url
            )

            # Create pending database subscription
            subscription = Subscription(
                user_id=user_id,
                plan_id=plan_id,
                plan_name=plan["name"],
                provider="paypal",
                status="pending_approval",  # Waiting for user to approve
                paypal_subscription_id=paypal_sub["subscription_id"],
                amount=plan[f"price_{billing_cycle}"],
                currency="usd",
                billing_cycle=billing_cycle,
                auto_renew=True,
            )

            self.db.add(subscription)
            self.db.commit()
            self.db.refresh(subscription)

            logger.info(f"✓ PayPal subscription created (pending approval): {subscription.id}")

            return {
                "subscription_id": subscription.id,
                "paypal_subscription_id": paypal_sub["subscription_id"],
                "approval_url": paypal_sub["approval_url"],
                "status": "pending_approval"
            }

        except Exception as e:
            self.db.rollback()
            logger.error(f"✗ Failed to create PayPal subscription: {e}")
            raise

    # ===========================
    # SUBSCRIPTION UPDATES
    # ===========================

    def upgrade_subscription(
        self,
        subscription_id: int,
        new_plan_id: str,
        billing_cycle: Optional[str] = None
    ) -> Subscription:
        """
        Upgrade/downgrade subscription to new plan

        Args:
            subscription_id: Subscription to update
            new_plan_id: New plan identifier
            billing_cycle: Optional new billing cycle

        Returns:
            Updated subscription
        """
        try:
            subscription = self.db.query(Subscription).filter_by(id=subscription_id).first()
            if not subscription:
                raise ValueError(f"Subscription not found: {subscription_id}")

            if not billing_cycle:
                billing_cycle = subscription.billing_cycle

            old_plan = subscription.plan_id
            old_amount = subscription.amount

            if subscription.provider == "stripe":
                # Update Stripe subscription
                self.stripe.update_subscription(
                    subscription_id=subscription.stripe_subscription_id,
                    plan_id=new_plan_id,
                    billing_cycle=billing_cycle,
                    proration_behavior="create_prorations"  # Prorate the difference
                )

                # Get updated plan details
                plan = self.stripe.get_plan_details(new_plan_id)
                new_amount = plan[f"price_{billing_cycle}"]

                # Update database record
                subscription.plan_id = new_plan_id
                subscription.plan_name = plan["name"]
                subscription.amount = new_amount
                subscription.billing_cycle = billing_cycle

            elif subscription.provider == "paypal":
                # Update PayPal subscription
                self.paypal.update_subscription_plan(
                    subscription_id=subscription.paypal_subscription_id,
                    new_plan_id=new_plan_id,
                    billing_cycle=billing_cycle
                )

                # Get updated plan details
                plan = self.paypal.get_plan_details(new_plan_id)
                new_amount = plan[f"price_{billing_cycle}"]

                # Update database record
                subscription.plan_id = new_plan_id
                subscription.plan_name = plan["name"]
                subscription.amount = new_amount
                subscription.billing_cycle = billing_cycle

            self.db.commit()
            self.db.refresh(subscription)

            logger.info(f"✓ Subscription upgraded: {subscription_id} ({old_plan} → {new_plan_id}, ${old_amount} → ${new_amount})")
            return subscription

        except Exception as e:
            self.db.rollback()
            logger.error(f"✗ Failed to upgrade subscription: {e}")
            raise

    def cancel_subscription(
        self,
        subscription_id: int,
        cancel_at_period_end: bool = True,
        reason: Optional[str] = None
    ) -> Subscription:
        """
        Cancel subscription

        Args:
            subscription_id: Subscription to cancel
            cancel_at_period_end: If True, cancel at end of billing period
            reason: Cancellation reason

        Returns:
            Canceled subscription
        """
        try:
            subscription = self.db.query(Subscription).filter_by(id=subscription_id).first()
            if not subscription:
                raise ValueError(f"Subscription not found: {subscription_id}")

            if subscription.provider == "stripe":
                self.stripe.cancel_subscription(
                    subscription_id=subscription.stripe_subscription_id,
                    cancel_at_period_end=cancel_at_period_end,
                    cancellation_reason=reason
                )
            elif subscription.provider == "paypal":
                if not cancel_at_period_end:
                    # PayPal doesn't support immediate cancellation with access preservation
                    # So we cancel immediately
                    self.paypal.cancel_subscription(
                        subscription_id=subscription.paypal_subscription_id,
                        reason=reason
                    )
                else:
                    # For end-of-period cancellation, we mark it in database
                    # and cancel via webhook when period ends
                    subscription.cancel_at_period_end = True

            # Update database
            if not cancel_at_period_end:
                subscription.status = "canceled"
                subscription.canceled_at = datetime.utcnow()
            else:
                subscription.cancel_at_period_end = True

            subscription.cancellation_reason = reason

            self.db.commit()
            self.db.refresh(subscription)

            logger.info(f"✓ Subscription canceled: {subscription_id} (at_period_end: {cancel_at_period_end})")
            return subscription

        except Exception as e:
            self.db.rollback()
            logger.error(f"✗ Failed to cancel subscription: {e}")
            raise

    def reactivate_subscription(self, subscription_id: int) -> Subscription:
        """Reactivate a canceled subscription (before period end)"""
        try:
            subscription = self.db.query(Subscription).filter_by(id=subscription_id).first()
            if not subscription:
                raise ValueError(f"Subscription not found: {subscription_id}")

            if not subscription.cancel_at_period_end:
                raise ValueError("Subscription is not set to cancel at period end")

            if subscription.provider == "stripe":
                self.stripe.reactivate_subscription(subscription.stripe_subscription_id)
            elif subscription.provider == "paypal":
                # For PayPal, we just update database flag
                pass

            # Update database
            subscription.cancel_at_period_end = False
            subscription.cancellation_reason = None

            self.db.commit()
            self.db.refresh(subscription)

            logger.info(f"✓ Subscription reactivated: {subscription_id}")
            return subscription

        except Exception as e:
            self.db.rollback()
            logger.error(f"✗ Failed to reactivate subscription: {e}")
            raise

    # ===========================
    # SUBSCRIPTION QUERIES
    # ===========================

    def get_user_subscription(self, user_id: int) -> Optional[Subscription]:
        """Get user's active subscription"""
        return self.db.query(Subscription).filter(
            Subscription.user_id == user_id,
            Subscription.status.in_(["active", "trialing", "past_due"])
        ).first()

    def get_user_subscriptions(self, user_id: int) -> List[Subscription]:
        """Get all user subscriptions (including canceled)"""
        return self.db.query(Subscription).filter_by(user_id=user_id).all()

    def get_subscription(self, subscription_id: int) -> Optional[Subscription]:
        """Get subscription by ID"""
        return self.db.query(Subscription).filter_by(id=subscription_id).first()

    def get_expiring_subscriptions(self, days: int = 7) -> List[Subscription]:
        """Get subscriptions expiring within X days"""
        expiry_threshold = datetime.utcnow() + timedelta(days=days)
        return self.db.query(Subscription).filter(
            Subscription.status == "active",
            Subscription.next_billing_date <= expiry_threshold,
            Subscription.auto_renew == True
        ).all()

    def get_past_due_subscriptions(self) -> List[Subscription]:
        """Get subscriptions with failed payments"""
        return self.db.query(Subscription).filter_by(status="past_due").all()

    # ===========================
    # INVOICE MANAGEMENT
    # ===========================

    def get_user_invoices(
        self,
        user_id: int,
        limit: int = 10
    ) -> List[Invoice]:
        """Get user's invoices"""
        return self.db.query(Invoice).filter_by(
            user_id=user_id
        ).order_by(Invoice.created_at.desc()).limit(limit).all()

    def get_invoice(self, invoice_id: int) -> Optional[Invoice]:
        """Get invoice by ID"""
        return self.db.query(Invoice).filter_by(id=invoice_id).first()

    # ===========================
    # BILLING PORTAL
    # ===========================

    def create_billing_portal_session(
        self,
        user_id: int,
        return_url: str
    ) -> Optional[str]:
        """
        Create billing portal session URL

        Args:
            user_id: User ID
            return_url: URL to return to

        Returns:
            Portal URL or None
        """
        try:
            user = self.db.query(User).filter_by(id=user_id).first()
            if not user or not user.stripe_customer_id:
                return None

            session = self.stripe.create_billing_portal_session(
                customer_id=user.stripe_customer_id,
                return_url=return_url
            )

            logger.info(f"✓ Billing portal session created for user: {user_id}")
            return session.url

        except Exception as e:
            logger.error(f"✗ Failed to create billing portal session: {e}")
            return None

    # ===========================
    # SUBSCRIPTION SYNC
    # ===========================

    def sync_subscription_from_stripe(
        self,
        stripe_subscription_id: str
    ) -> Optional[Subscription]:
        """
        Sync subscription from Stripe (webhook updates)

        Args:
            stripe_subscription_id: Stripe subscription ID

        Returns:
            Updated subscription
        """
        try:
            # Get from database
            subscription = self.db.query(Subscription).filter_by(
                stripe_subscription_id=stripe_subscription_id
            ).first()

            if not subscription:
                logger.warning(f"Subscription not found in database: {stripe_subscription_id}")
                return None

            # Get from Stripe
            stripe_sub = self.stripe.get_subscription(stripe_subscription_id)
            if not stripe_sub:
                return None

            # Update database record
            subscription.status = stripe_sub.status
            subscription.current_period_start = datetime.fromtimestamp(stripe_sub.current_period_start)
            subscription.current_period_end = datetime.fromtimestamp(stripe_sub.current_period_end)
            subscription.next_billing_date = datetime.fromtimestamp(stripe_sub.current_period_end)
            subscription.cancel_at_period_end = stripe_sub.cancel_at_period_end

            if stripe_sub.canceled_at:
                subscription.canceled_at = datetime.fromtimestamp(stripe_sub.canceled_at)

            self.db.commit()
            self.db.refresh(subscription)

            logger.info(f"✓ Subscription synced from Stripe: {subscription.id}")
            return subscription

        except Exception as e:
            self.db.rollback()
            logger.error(f"✗ Failed to sync subscription from Stripe: {e}")
            return None

    def sync_subscription_from_paypal(
        self,
        paypal_subscription_id: str
    ) -> Optional[Subscription]:
        """
        Sync subscription from PayPal (webhook updates)

        Args:
            paypal_subscription_id: PayPal subscription ID

        Returns:
            Updated subscription
        """
        try:
            # Get from database
            subscription = self.db.query(Subscription).filter_by(
                paypal_subscription_id=paypal_subscription_id
            ).first()

            if not subscription:
                logger.warning(f"Subscription not found in database: {paypal_subscription_id}")
                return None

            # Get from PayPal
            paypal_sub = self.paypal.get_subscription(paypal_subscription_id)
            if not paypal_sub:
                return None

            # Map PayPal status to our status
            status_map = {
                "APPROVAL_PENDING": "pending_approval",
                "APPROVED": "active",
                "ACTIVE": "active",
                "SUSPENDED": "past_due",
                "CANCELLED": "canceled",
                "EXPIRED": "canceled"
            }

            subscription.status = status_map.get(paypal_sub["status"], "incomplete")

            # Update billing dates if available
            if paypal_sub.get("billing_info"):
                billing_info = paypal_sub["billing_info"]
                if billing_info.get("next_billing_time"):
                    subscription.next_billing_date = datetime.fromisoformat(
                        billing_info["next_billing_time"].replace("Z", "+00:00")
                    )

            self.db.commit()
            self.db.refresh(subscription)

            logger.info(f"✓ Subscription synced from PayPal: {subscription.id}")
            return subscription

        except Exception as e:
            self.db.rollback()
            logger.error(f"✗ Failed to sync subscription from PayPal: {e}")
            return None
