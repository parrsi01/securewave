"""
SecureWave VPN - Payment Webhook Handlers
Processes webhook events from Stripe and PayPal
"""

import logging
from typing import Dict, Optional
from datetime import datetime, timedelta
from sqlalchemy.orm import Session

from models.subscription import Subscription
from models.invoice import Invoice
from models.user import User
from services.stripe_service import StripeService
from services.paypal_service import PayPalService
from services.email_service import EmailService
from services.enhanced_email_service import get_enhanced_email_service

logger = logging.getLogger(__name__)


class PaymentWebhookHandler:
    """
    Handles webhook events from payment providers
    Updates subscription status, processes payments, sends notifications
    """

    def __init__(self, db: Session):
        """
        Initialize webhook handler

        Args:
            db: Database session
        """
        self.db = db
        self.stripe = StripeService()
        self.paypal = PayPalService()
        self.email_service = EmailService()
        self.enhanced_email = get_enhanced_email_service(db)

    def _get_user_for_subscription(self, subscription: Optional[Subscription]) -> Optional[User]:
        if not subscription:
            return None
        return self.db.query(User).filter_by(id=subscription.user_id).first()

    def _send_simple_billing_email(
        self,
        to_email: str,
        subject: str,
        heading: str,
        message: str,
        action_url: Optional[str] = None,
    ) -> None:
        html_action = f'<p><a href="{action_url}">Review billing details</a></p>' if action_url else ""
        html_content = f"""
        <html>
          <body style="font-family: Arial, sans-serif; line-height: 1.6; color: #1F2937;">
            <h2>{heading}</h2>
            <p>{message}</p>
            {html_action}
            <p>SecureWave Billing</p>
          </body>
        </html>
        """
        text_content = f"{heading}\n\n{message}\n{action_url or ''}\n\nSecureWave Billing"
        self.email_service.send_email(to_email=to_email, subject=subject, html_content=html_content, text_content=text_content)

    @staticmethod
    def _field(source: Dict, name: str, default=None):
        if source is None:
            return default
        if isinstance(source, dict):
            return source.get(name, default)
        return getattr(source, name, default)

    def _extract_subscription_price_id(self, subscription_data: Dict) -> Optional[str]:
        items = self._field(subscription_data, "items") or {}
        data = self._field(items, "data") or []
        if not data:
            return None
        first_item = data[0]
        price = self._field(first_item, "price") or {}
        return self._field(price, "id")

    def _timestamp_or_none(self, value) -> Optional[datetime]:
        return datetime.fromtimestamp(value) if value else None

    def _sync_stripe_subscription_record(
        self,
        subscription_data: Dict,
        user_id: Optional[int] = None,
        customer_id: Optional[str] = None,
    ) -> Optional[Subscription]:
        stripe_sub_id = self._field(subscription_data, "id")
        if not stripe_sub_id:
            return None

        metadata = self._field(subscription_data, "metadata") or {}
        if user_id is None:
            raw_user_id = metadata.get("securewave_user_id") or metadata.get("user_id")
            user_id = int(raw_user_id) if raw_user_id else None

        customer_id = customer_id or self._field(subscription_data, "customer")
        price_id = self._extract_subscription_price_id(subscription_data)
        plan_id = metadata.get("plan_id")
        billing_cycle = metadata.get("billing_cycle")
        plan = None
        if not plan_id or not billing_cycle:
            plan_id, billing_cycle, plan = self.stripe.find_plan_by_price_id(price_id)
        else:
            plan = self.stripe.get_plan_details(plan_id)

        if not user_id or not plan_id or not billing_cycle or not plan:
            logger.warning("Stripe subscription missing SecureWave metadata: %s", stripe_sub_id)
            return None

        user = self.db.query(User).filter_by(id=user_id).first()
        if not user:
            logger.warning("Stripe subscription user not found: %s", user_id)
            return None
        if customer_id and not user.stripe_customer_id:
            user.stripe_customer_id = customer_id

        subscription = self.db.query(Subscription).filter_by(
            stripe_subscription_id=stripe_sub_id
        ).first()
        if not subscription:
            subscription = Subscription(
                user_id=user_id,
                plan_id=plan_id,
                plan_name=plan["name"],
                provider="stripe",
                stripe_customer_id=customer_id,
                stripe_subscription_id=stripe_sub_id,
                stripe_price_id=price_id,
                amount=plan[f"price_{billing_cycle}"],
                currency="usd",
                billing_cycle=billing_cycle,
                auto_renew=True,
            )
            self.db.add(subscription)

        subscription.status = self._field(subscription_data, "status", subscription.status)
        subscription.plan_id = plan_id
        subscription.plan_name = plan["name"]
        subscription.stripe_customer_id = customer_id
        subscription.stripe_price_id = price_id
        subscription.amount = plan[f"price_{billing_cycle}"]
        subscription.billing_cycle = billing_cycle
        subscription.current_period_start = self._timestamp_or_none(
            self._field(subscription_data, "current_period_start")
        )
        subscription.current_period_end = self._timestamp_or_none(
            self._field(subscription_data, "current_period_end")
        )
        subscription.next_billing_date = subscription.current_period_end
        subscription.cancel_at_period_end = bool(
            self._field(subscription_data, "cancel_at_period_end", False)
        )
        trial_start = self._field(subscription_data, "trial_start")
        trial_end = self._field(subscription_data, "trial_end")
        subscription.trial_start = self._timestamp_or_none(trial_start)
        subscription.trial_end = self._timestamp_or_none(trial_end)
        if subscription.status in ("active", "trialing"):
            subscription.activated_at = subscription.activated_at or datetime.utcnow()
            user.subscription_status = "active"
        elif subscription.status in ("canceled", "incomplete_expired", "unpaid"):
            user.subscription_status = "inactive"
        subscription.extra_data = {
            **(subscription.extra_data or {}),
            "last_stripe_sync": datetime.utcnow().isoformat(),
        }
        self.db.commit()
        self.db.refresh(subscription)
        return subscription

    # ===========================
    # STRIPE WEBHOOK HANDLERS
    # ===========================

    def handle_stripe_event(self, event: Dict) -> Dict:
        """
        Process Stripe webhook event

        Args:
            event: Verified Stripe event

        Returns:
            Processing result
        """
        event_type = event["type"]
        event_data = event["data"]["object"]

        logger.info(f"Processing Stripe event: {event_type}")

        # Map event types to handlers
        handlers = {
            # Customer events
            "customer.created": self._stripe_customer_created,
            "customer.updated": self._stripe_customer_updated,
            "customer.deleted": self._stripe_customer_deleted,
            "checkout.session.completed": self._stripe_checkout_completed,

            # Subscription events
            "customer.subscription.created": self._stripe_subscription_created,
            "customer.subscription.updated": self._stripe_subscription_updated,
            "customer.subscription.deleted": self._stripe_subscription_deleted,
            "customer.subscription.trial_will_end": self._stripe_trial_ending,

            # Payment events
            "invoice.created": self._stripe_invoice_created,
            "invoice.finalized": self._stripe_invoice_finalized,
            "invoice.paid": self._stripe_invoice_paid,
            "invoice.payment_failed": self._stripe_invoice_payment_failed,
            "invoice.payment_action_required": self._stripe_invoice_action_required,

            # Payment intent events
            "payment_intent.succeeded": self._stripe_payment_succeeded,
            "payment_intent.payment_failed": self._stripe_payment_failed,

            # Charge events
            "charge.succeeded": self._stripe_charge_succeeded,
            "charge.failed": self._stripe_charge_failed,
            "charge.refunded": self._stripe_charge_refunded,
        }

        handler = handlers.get(event_type)

        if handler:
            try:
                result = handler(event_data)
                logger.info(f"✓ Stripe event processed: {event_type}")
                return {"status": "success", "event_type": event_type, "result": result}
            except Exception as e:
                logger.error(f"✗ Failed to process Stripe event {event_type}: {e}")
                return {"status": "error", "event_type": event_type, "error": str(e)}
        else:
            logger.info(f"Unhandled Stripe event type: {event_type}")
            return {"status": "ignored", "event_type": event_type}

    def _stripe_checkout_completed(self, session_data: Dict) -> Dict:
        """Handle hosted Checkout completion for subscription signup."""
        if self._field(session_data, "mode") != "subscription":
            return {"status": "ignored", "reason": "not_subscription"}

        stripe_sub_id = self._field(session_data, "subscription")
        customer_id = self._field(session_data, "customer")
        raw_user_id = self._field(session_data, "client_reference_id")
        metadata = self._field(session_data, "metadata") or {}
        if not raw_user_id:
            raw_user_id = metadata.get("securewave_user_id")
        user_id = int(raw_user_id) if raw_user_id else None

        subscription_data = self.stripe.get_subscription(stripe_sub_id) if stripe_sub_id else None
        if not subscription_data:
            return {"status": "not_found", "subscription_id": stripe_sub_id}

        subscription = self._sync_stripe_subscription_record(
            subscription_data,
            user_id=user_id,
            customer_id=customer_id,
        )
        if not subscription:
            return {"status": "not_synced", "subscription_id": stripe_sub_id}
        return {"status": "synced", "subscription_id": subscription.id}

    def _stripe_subscription_created(self, subscription_data: Dict) -> Dict:
        """Handle subscription.created event"""
        stripe_sub_id = subscription_data["id"]
        customer_id = self._field(subscription_data, "customer")
        subscription = self._sync_stripe_subscription_record(
            subscription_data,
            customer_id=customer_id,
        )

        return {
            "subscription_id": subscription.id if subscription else stripe_sub_id,
            "status": self._field(subscription_data, "status"),
        }

    def _stripe_subscription_updated(self, subscription_data: Dict) -> Dict:
        """Handle subscription.updated event"""
        stripe_sub_id = subscription_data["id"]

        subscription = self.db.query(Subscription).filter_by(
            stripe_subscription_id=stripe_sub_id
        ).first()

        if not subscription:
            logger.warning(f"Subscription not found: {stripe_sub_id}")
            return {"status": "not_found"}

        # Update subscription details
        subscription.status = subscription_data["status"]
        subscription.current_period_start = datetime.fromtimestamp(subscription_data["current_period_start"])
        subscription.current_period_end = datetime.fromtimestamp(subscription_data["current_period_end"])
        subscription.next_billing_date = datetime.fromtimestamp(subscription_data["current_period_end"])
        subscription.cancel_at_period_end = subscription_data.get("cancel_at_period_end", False)

        if subscription_data.get("canceled_at"):
            subscription.canceled_at = datetime.fromtimestamp(subscription_data["canceled_at"])

        self.db.commit()

        logger.info(f"✓ Subscription updated: {subscription.id} (status: {subscription.status})")
        return {"subscription_id": subscription.id, "status": subscription.status}

    def _stripe_subscription_deleted(self, subscription_data: Dict) -> Dict:
        """Handle subscription.deleted event"""
        stripe_sub_id = subscription_data["id"]

        subscription = self.db.query(Subscription).filter_by(
            stripe_subscription_id=stripe_sub_id
        ).first()

        if subscription:
            subscription.status = "canceled"
            subscription.canceled_at = datetime.utcnow()
            self.db.commit()

        return {"subscription_id": stripe_sub_id, "status": "canceled"}

    def _stripe_trial_ending(self, subscription_data: Dict) -> Dict:
        """Handle trial ending (send notification 3 days before)"""
        stripe_sub_id = subscription_data["id"]

        subscription = self.db.query(Subscription).filter_by(
            stripe_subscription_id=stripe_sub_id
        ).first()

        if subscription:
            user = self._get_user_for_subscription(subscription)
            if user:
                self.enhanced_email.send_subscription_expiring_email(
                    to_email=user.email,
                    user_name=user.full_name or user.email.split("@")[0],
                    days_remaining=3,
                    subscription_plan=subscription.plan_name,
                    user_id=user.id,
                )
            logger.info(f"✓ Trial ending soon for subscription: {subscription.id}")

        return {"subscription_id": stripe_sub_id, "action": "trial_ending_notification"}

    def _stripe_invoice_created(self, invoice_data: Dict) -> Dict:
        """Handle invoice.created event"""
        return {"status": "invoice_created"}

    def _stripe_invoice_finalized(self, invoice_data: Dict) -> Dict:
        """Handle invoice.finalized event"""
        return {"status": "invoice_finalized"}

    def _stripe_invoice_paid(self, invoice_data: Dict) -> Dict:
        """Handle invoice.paid event (payment succeeded)"""
        stripe_invoice_id = invoice_data["id"]
        customer_id = invoice_data["customer"]
        subscription_id = invoice_data.get("subscription")

        # Find subscription
        subscription = None
        if subscription_id:
            subscription = self.db.query(Subscription).filter_by(
                stripe_subscription_id=subscription_id
            ).first()

        # Create/update invoice record
        invoice = self.db.query(Invoice).filter_by(
            stripe_invoice_id=stripe_invoice_id
        ).first()

        if not invoice and subscription:
            invoice = Invoice(
                user_id=subscription.user_id,
                subscription_id=subscription.id,
                invoice_number=f"INV-{datetime.utcnow().strftime('%Y%m%d')}-{invoice_data['number']}",
                provider="stripe",
                stripe_invoice_id=stripe_invoice_id,
                stripe_charge_id=invoice_data.get("charge"),
                stripe_payment_intent_id=invoice_data.get("payment_intent"),
                amount_due=invoice_data["amount_due"] / 100,
                amount_paid=invoice_data["amount_paid"] / 100,
                amount_remaining=invoice_data["amount_remaining"] / 100,
                currency=invoice_data["currency"],
                subtotal=invoice_data["subtotal"] / 100,
                tax_amount=invoice_data.get("tax", 0) / 100,
                status="paid",
                paid_at=datetime.fromtimestamp(invoice_data["status_transitions"]["paid_at"]),
                pdf_url=invoice_data.get("invoice_pdf"),
                hosted_invoice_url=invoice_data.get("hosted_invoice_url"),
                period_start=datetime.fromtimestamp(invoice_data["period_start"]) if invoice_data.get("period_start") else None,
                period_end=datetime.fromtimestamp(invoice_data["period_end"]) if invoice_data.get("period_end") else None,
            )
            self.db.add(invoice)
        elif invoice:
            invoice.status = "paid"
            invoice.paid_at = datetime.fromtimestamp(invoice_data["status_transitions"]["paid_at"])
            invoice.amount_paid = invoice_data["amount_paid"] / 100

        # Update subscription payment tracking
        if subscription:
            subscription.last_payment_date = datetime.utcnow()
            subscription.last_payment_amount = invoice_data["amount_paid"] / 100
            subscription.last_payment_status = "succeeded"
            subscription.failed_payment_count = 0
            subscription.renewal_count += 1
            subscription.status = "active"

        self.db.commit()

        logger.info(f"✓ Invoice paid: {stripe_invoice_id}")
        return {"invoice_id": stripe_invoice_id, "amount": invoice_data["amount_paid"] / 100}

    def _stripe_invoice_payment_failed(self, invoice_data: Dict) -> Dict:
        """Handle invoice.payment_failed event"""
        stripe_invoice_id = invoice_data["id"]
        subscription_id = invoice_data.get("subscription")

        subscription = None
        if subscription_id:
            subscription = self.db.query(Subscription).filter_by(
                stripe_subscription_id=subscription_id
            ).first()

        if subscription:
            subscription.last_payment_status = "failed"
            subscription.failed_payment_count += 1
            subscription.status = "past_due"
            user = self._get_user_for_subscription(subscription)
            if user:
                hosted_url = invoice_data.get("hosted_invoice_url")
                self._send_simple_billing_email(
                    to_email=user.email,
                    subject="Payment failed - action required",
                    heading="We couldn't process your payment",
                    message="Your subscription payment failed. Please update your billing details to avoid service interruption.",
                    action_url=hosted_url,
                )

            self.db.commit()

        invoice = self.db.query(Invoice).filter_by(
            stripe_invoice_id=stripe_invoice_id
        ).first()
        if invoice:
            invoice.status = "past_due"
            invoice.attempt_count = (invoice.attempt_count or 0) + 1
            invoice.next_payment_attempt = datetime.utcnow() + timedelta(days=1)
            self.db.commit()

        logger.warning(f"⚠ Invoice payment failed: {stripe_invoice_id}")
        return {"invoice_id": stripe_invoice_id, "status": "failed"}

    def _stripe_invoice_action_required(self, invoice_data: Dict) -> Dict:
        """Handle invoice.payment_action_required (3D Secure)"""
        stripe_invoice_id = invoice_data["id"]
        subscription_id = invoice_data.get("subscription")
        subscription = None
        if subscription_id:
            subscription = self.db.query(Subscription).filter_by(
                stripe_subscription_id=subscription_id
            ).first()
        user = self._get_user_for_subscription(subscription)
        if user:
            hosted_url = invoice_data.get("hosted_invoice_url")
            self._send_simple_billing_email(
                to_email=user.email,
                subject="Additional verification required",
                heading="Complete your payment verification",
                message="Your payment requires additional verification (3D Secure). Please complete the verification to keep your subscription active.",
                action_url=hosted_url,
            )
        invoice = self.db.query(Invoice).filter_by(
            stripe_invoice_id=stripe_invoice_id
        ).first()
        if invoice:
            invoice.status = "open"
            invoice.hosted_invoice_url = invoice_data.get("hosted_invoice_url")
            invoice.internal_notes = "Payment action required (3D Secure)"
            self.db.commit()
        return {"status": "action_required"}

    def _stripe_payment_succeeded(self, payment_intent_data: Dict) -> Dict:
        """Handle payment_intent.succeeded event"""
        return {"status": "payment_succeeded"}

    def _stripe_payment_failed(self, payment_intent_data: Dict) -> Dict:
        """Handle payment_intent.payment_failed event"""
        return {"status": "payment_failed"}

    def _stripe_charge_succeeded(self, charge_data: Dict) -> Dict:
        """Handle charge.succeeded event"""
        return {"status": "charge_succeeded"}

    def _stripe_charge_failed(self, charge_data: Dict) -> Dict:
        """Handle charge.failed event"""
        return {"status": "charge_failed"}

    def _stripe_charge_refunded(self, charge_data: Dict) -> Dict:
        """Handle charge.refunded event"""
        charge_id = charge_data["id"]
        amount_refunded = charge_data["amount_refunded"] / 100

        invoice = self.db.query(Invoice).filter_by(stripe_charge_id=charge_id).first()
        if invoice:
            invoice.status = "void"
            invoice.amount_paid = max(0.0, invoice.amount_paid - amount_refunded)
            invoice.amount_remaining = 0.0
            invoice.internal_notes = f"Refunded ${amount_refunded:.2f} via Stripe"
            self.db.commit()

            subscription = self.db.query(Subscription).filter_by(id=invoice.subscription_id).first()
            if subscription:
                subscription.last_payment_status = "refunded"
                subscription.status = "canceled"
                self.db.commit()

                user = self._get_user_for_subscription(subscription)
                if user:
                    self._send_simple_billing_email(
                        to_email=user.email,
                        subject="Refund processed",
                        heading="Your refund is complete",
                        message=f"A refund of ${amount_refunded:.2f} has been processed.",
                    )
        logger.info(f"✓ Charge refunded: {charge_id} (${amount_refunded})")
        return {"charge_id": charge_id, "amount_refunded": amount_refunded}

    def _stripe_customer_created(self, customer_data: Dict) -> Dict:
        """Handle customer.created event"""
        return {"status": "customer_created"}

    def _stripe_customer_updated(self, customer_data: Dict) -> Dict:
        """Handle customer.updated event"""
        return {"status": "customer_updated"}

    def _stripe_customer_deleted(self, customer_data: Dict) -> Dict:
        """Handle customer.deleted event"""
        customer_id = customer_data["id"]

        # Update user record
        user = self.db.query(User).filter_by(stripe_customer_id=customer_id).first()
        if user:
            user.stripe_customer_id = None
            self.db.commit()

        return {"customer_id": customer_id, "status": "deleted"}

    # ===========================
    # PAYPAL WEBHOOK HANDLERS
    # ===========================

    def handle_paypal_event(self, event: Dict) -> Dict:
        """
        Process PayPal webhook event

        Args:
            event: Verified PayPal event

        Returns:
            Processing result
        """
        event_type = event.get("event_type")
        resource = event.get("resource", {})

        logger.info(f"Processing PayPal event: {event_type}")

        # Map event types to handlers
        handlers = {
            # Billing subscription events
            "BILLING.SUBSCRIPTION.CREATED": self._paypal_subscription_created,
            "BILLING.SUBSCRIPTION.ACTIVATED": self._paypal_subscription_activated,
            "BILLING.SUBSCRIPTION.UPDATED": self._paypal_subscription_updated,
            "BILLING.SUBSCRIPTION.EXPIRED": self._paypal_subscription_expired,
            "BILLING.SUBSCRIPTION.CANCELLED": self._paypal_subscription_cancelled,
            "BILLING.SUBSCRIPTION.SUSPENDED": self._paypal_subscription_suspended,
            "BILLING.SUBSCRIPTION.PAYMENT.FAILED": self._paypal_payment_failed,

            # Payment events
            "PAYMENT.SALE.COMPLETED": self._paypal_payment_completed,
            "PAYMENT.SALE.REFUNDED": self._paypal_payment_refunded,
        }

        handler = handlers.get(event_type)

        if handler:
            try:
                result = handler(resource)
                logger.info(f"✓ PayPal event processed: {event_type}")
                return {"status": "success", "event_type": event_type, "result": result}
            except Exception as e:
                logger.error(f"✗ Failed to process PayPal event {event_type}: {e}")
                return {"status": "error", "event_type": event_type, "error": str(e)}
        else:
            logger.info(f"Unhandled PayPal event type: {event_type}")
            return {"status": "ignored", "event_type": event_type}

    def _paypal_subscription_created(self, resource: Dict) -> Dict:
        """Handle subscription created event"""
        return {"status": "subscription_created"}

    def _paypal_subscription_activated(self, resource: Dict) -> Dict:
        """Handle subscription activated event (user approved)"""
        paypal_sub_id = resource.get("id")

        subscription = self.db.query(Subscription).filter_by(
            paypal_subscription_id=paypal_sub_id
        ).first()

        if subscription:
            subscription.status = "active"
            subscription.activated_at = datetime.utcnow()
            self.db.commit()

        logger.info(f"✓ PayPal subscription activated: {paypal_sub_id}")
        return {"subscription_id": paypal_sub_id, "status": "active"}

    def _paypal_subscription_updated(self, resource: Dict) -> Dict:
        """Handle subscription updated event"""
        paypal_sub_id = resource.get("id")

        subscription = self.db.query(Subscription).filter_by(
            paypal_subscription_id=paypal_sub_id
        ).first()

        if subscription:
            # Update subscription from PayPal data
            status_map = {
                "ACTIVE": "active",
                "SUSPENDED": "past_due",
                "CANCELLED": "canceled",
                "EXPIRED": "canceled"
            }
            subscription.status = status_map.get(resource.get("status"), subscription.status)
            self.db.commit()

        return {"subscription_id": paypal_sub_id, "status": "updated"}

    def _paypal_subscription_expired(self, resource: Dict) -> Dict:
        """Handle subscription expired event"""
        paypal_sub_id = resource.get("id")

        subscription = self.db.query(Subscription).filter_by(
            paypal_subscription_id=paypal_sub_id
        ).first()

        if subscription:
            subscription.status = "canceled"
            subscription.canceled_at = datetime.utcnow()
            self.db.commit()

        return {"subscription_id": paypal_sub_id, "status": "expired"}

    def _paypal_subscription_cancelled(self, resource: Dict) -> Dict:
        """Handle subscription cancelled event"""
        paypal_sub_id = resource.get("id")

        subscription = self.db.query(Subscription).filter_by(
            paypal_subscription_id=paypal_sub_id
        ).first()

        if subscription:
            subscription.status = "canceled"
            subscription.canceled_at = datetime.utcnow()
            self.db.commit()

        return {"subscription_id": paypal_sub_id, "status": "cancelled"}

    def _paypal_subscription_suspended(self, resource: Dict) -> Dict:
        """Handle subscription suspended event (payment failure)"""
        paypal_sub_id = resource.get("id")

        subscription = self.db.query(Subscription).filter_by(
            paypal_subscription_id=paypal_sub_id
        ).first()

        if subscription:
            subscription.status = "past_due"
            self.db.commit()

        return {"subscription_id": paypal_sub_id, "status": "suspended"}

    def _paypal_payment_failed(self, resource: Dict) -> Dict:
        """Handle payment failed event"""
        paypal_sub_id = resource.get("id")

        subscription = self.db.query(Subscription).filter_by(
            paypal_subscription_id=paypal_sub_id
        ).first()

        if subscription:
            subscription.last_payment_status = "failed"
            subscription.failed_payment_count += 1
            subscription.status = "past_due"
            self.db.commit()
            user = self._get_user_for_subscription(subscription)
            if user:
                self._send_simple_billing_email(
                    to_email=user.email,
                    subject="Payment failed - action required",
                    heading="We couldn't process your PayPal payment",
                    message="Your PayPal payment failed. Please update your billing details to avoid service interruption.",
                )

        logger.warning(f"⚠ PayPal payment failed for subscription: {paypal_sub_id}")
        return {"subscription_id": paypal_sub_id, "status": "payment_failed"}

    def _paypal_payment_completed(self, resource: Dict) -> Dict:
        """Handle payment completed event"""
        sale_id = resource.get("id")
        amount = float(resource.get("amount", {}).get("total", 0))

        # Try to find subscription from billing agreement ID
        billing_agreement_id = resource.get("billing_agreement_id")

        if billing_agreement_id:
            subscription = self.db.query(Subscription).filter_by(
                paypal_subscription_id=billing_agreement_id
            ).first()

            if subscription:
                subscription.last_payment_date = datetime.utcnow()
                subscription.last_payment_amount = amount
                subscription.last_payment_status = "succeeded"
                subscription.failed_payment_count = 0
                subscription.renewal_count += 1
                subscription.status = "active"
                self.db.commit()
                existing_invoice = self.db.query(Invoice).filter_by(
                    paypal_transaction_id=sale_id
                ).first()
                if not existing_invoice:
                    invoice = Invoice(
                        user_id=subscription.user_id,
                        subscription_id=subscription.id,
                        invoice_number=f"PP-{datetime.utcnow().strftime('%Y%m%d')}-{sale_id[-6:]}",
                        provider="paypal",
                        paypal_transaction_id=sale_id,
                        paypal_invoice_id=resource.get("invoice_id"),
                        amount_due=amount,
                        amount_paid=amount,
                        amount_remaining=0.0,
                        currency=resource.get("amount", {}).get("currency") or "USD",
                        subtotal=amount,
                        status="paid",
                        paid_at=datetime.utcnow(),
                        description="PayPal subscription payment",
                    )
                    self.db.add(invoice)
                    self.db.commit()

                user = self._get_user_for_subscription(subscription)
                if user:
                    self.enhanced_email.send_subscription_renewed_email(
                        to_email=user.email,
                        user_name=user.full_name or user.email.split("@")[0],
                        subscription_plan=subscription.plan_name,
                        amount=amount,
                        user_id=user.id,
                    )

        logger.info(f"✓ PayPal payment completed: {sale_id} (${amount})")
        return {"sale_id": sale_id, "amount": amount}

    def _paypal_payment_refunded(self, resource: Dict) -> Dict:
        """Handle payment refunded event"""
        sale_id = resource.get("id")
        amount = float(resource.get("amount", {}).get("total", 0))

        invoice = self.db.query(Invoice).filter_by(paypal_transaction_id=sale_id).first()
        if invoice:
            invoice.status = "void"
            invoice.amount_paid = max(0.0, invoice.amount_paid - amount)
            invoice.amount_remaining = 0.0
            invoice.internal_notes = f"Refunded ${amount:.2f} via PayPal"
            self.db.commit()

            subscription = self.db.query(Subscription).filter_by(id=invoice.subscription_id).first()
            if subscription:
                subscription.last_payment_status = "refunded"
                subscription.status = "canceled"
                self.db.commit()

                user = self._get_user_for_subscription(subscription)
                if user:
                    self._send_simple_billing_email(
                        to_email=user.email,
                        subject="Refund processed",
                        heading="Your refund is complete",
                        message=f"A refund of ${amount:.2f} has been processed.",
                    )

        logger.info(f"✓ PayPal payment refunded: {sale_id} (${amount})")
        return {"sale_id": sale_id, "amount_refunded": amount}
