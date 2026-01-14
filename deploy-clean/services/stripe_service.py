"""
SecureWave VPN - Stripe Payment Integration Service
Complete Stripe integration for subscription management and payment processing
"""

import os
import logging
from typing import Dict, Optional, List
from datetime import datetime, timedelta
from dotenv import load_dotenv

import stripe

# Load environment variables
load_dotenv()
load_dotenv(".env.production")

logger = logging.getLogger(__name__)

# Configure Stripe
stripe.api_key = os.getenv("STRIPE_SECRET_KEY")
stripe.api_version = "2023-10-16"  # Latest stable version

# Webhook secret for signature verification
STRIPE_WEBHOOK_SECRET = os.getenv("STRIPE_WEBHOOK_SECRET")


class StripeService:
    """
    Production-grade Stripe integration service
    Handles customers, subscriptions, payments, and webhooks
    """

    # Subscription plans configuration
    PLANS = {
        "free": {
            "name": "Free Plan",
            "price_monthly": 0,
            "price_yearly": 0,
            "features": [
                "1 VPN connection",
                "5 GB bandwidth/month",
                "Limited server access",
                "Standard support"
            ],
            "stripe_price_id_monthly": None,  # Free plan doesn't use Stripe
            "stripe_price_id_yearly": None,
        },
        "basic": {
            "name": "Basic Plan",
            "price_monthly": 9.99,
            "price_yearly": 99.99,  # ~$8.33/month (17% discount)
            "features": [
                "3 VPN connections",
                "Unlimited bandwidth",
                "All server locations",
                "Priority support",
                "Ad-blocking DNS"
            ],
            "stripe_price_id_monthly": os.getenv("STRIPE_PRICE_BASIC_MONTHLY"),
            "stripe_price_id_yearly": os.getenv("STRIPE_PRICE_BASIC_YEARLY"),
        },
        "premium": {
            "name": "Premium Plan",
            "price_monthly": 14.99,
            "price_yearly": 149.99,  # ~$12.50/month (17% discount)
            "features": [
                "5 VPN connections",
                "Unlimited bandwidth",
                "All server locations",
                "24/7 premium support",
                "Ad-blocking + malware protection",
                "Dedicated IP available"
            ],
            "stripe_price_id_monthly": os.getenv("STRIPE_PRICE_PREMIUM_MONTHLY"),
            "stripe_price_id_yearly": os.getenv("STRIPE_PRICE_PREMIUM_YEARLY"),
        },
        "ultra": {
            "name": "Ultra Plan",
            "price_monthly": 24.99,
            "price_yearly": 249.99,  # ~$20.83/month (17% discount)
            "features": [
                "10 VPN connections",
                "Unlimited bandwidth",
                "All server locations + early access",
                "VIP 24/7 support",
                "Complete security suite",
                "2 dedicated IPs included",
                "Port forwarding",
                "Multi-hop routing"
            ],
            "stripe_price_id_monthly": os.getenv("STRIPE_PRICE_ULTRA_MONTHLY"),
            "stripe_price_id_yearly": os.getenv("STRIPE_PRICE_ULTRA_YEARLY"),
        },
    }

    def __init__(self):
        """Initialize Stripe service"""
        if not stripe.api_key:
            logger.warning("STRIPE_SECRET_KEY not configured - Stripe integration disabled")

    @classmethod
    def get_plan_details(cls, plan_id: str) -> Optional[Dict]:
        """Get plan configuration"""
        return cls.PLANS.get(plan_id)

    @classmethod
    def get_all_plans(cls) -> Dict:
        """Get all available plans"""
        return cls.PLANS

    # ===========================
    # CUSTOMER MANAGEMENT
    # ===========================

    def create_customer(
        self,
        email: str,
        name: Optional[str] = None,
        phone: Optional[str] = None,
        metadata: Optional[Dict] = None
    ) -> stripe.Customer:
        """
        Create a Stripe customer

        Args:
            email: Customer email
            name: Customer name
            phone: Customer phone
            metadata: Additional metadata

        Returns:
            Stripe Customer object
        """
        try:
            customer = stripe.Customer.create(
                email=email,
                name=name,
                phone=phone,
                metadata=metadata or {},
            )

            logger.info(f"✓ Stripe customer created: {customer.id} ({email})")
            return customer

        except stripe.error.StripeError as e:
            logger.error(f"✗ Failed to create Stripe customer: {e}")
            raise

    def get_customer(self, customer_id: str) -> Optional[stripe.Customer]:
        """Get customer by ID"""
        try:
            return stripe.Customer.retrieve(customer_id)
        except stripe.error.StripeError as e:
            logger.error(f"✗ Failed to retrieve customer {customer_id}: {e}")
            return None

    def update_customer(
        self,
        customer_id: str,
        email: Optional[str] = None,
        name: Optional[str] = None,
        phone: Optional[str] = None,
        metadata: Optional[Dict] = None
    ) -> stripe.Customer:
        """Update customer information"""
        try:
            update_data = {}
            if email:
                update_data["email"] = email
            if name:
                update_data["name"] = name
            if phone:
                update_data["phone"] = phone
            if metadata:
                update_data["metadata"] = metadata

            customer = stripe.Customer.modify(customer_id, **update_data)
            logger.info(f"✓ Stripe customer updated: {customer_id}")
            return customer

        except stripe.error.StripeError as e:
            logger.error(f"✗ Failed to update customer: {e}")
            raise

    def delete_customer(self, customer_id: str) -> bool:
        """Delete customer (GDPR compliance)"""
        try:
            stripe.Customer.delete(customer_id)
            logger.info(f"✓ Stripe customer deleted: {customer_id}")
            return True
        except stripe.error.StripeError as e:
            logger.error(f"✗ Failed to delete customer: {e}")
            return False

    # ===========================
    # PAYMENT METHOD MANAGEMENT
    # ===========================

    def attach_payment_method(
        self,
        customer_id: str,
        payment_method_id: str
    ) -> stripe.PaymentMethod:
        """Attach payment method to customer"""
        try:
            payment_method = stripe.PaymentMethod.attach(
                payment_method_id,
                customer=customer_id,
            )

            # Set as default payment method
            stripe.Customer.modify(
                customer_id,
                invoice_settings={"default_payment_method": payment_method_id}
            )

            logger.info(f"✓ Payment method attached: {payment_method_id}")
            return payment_method

        except stripe.error.StripeError as e:
            logger.error(f"✗ Failed to attach payment method: {e}")
            raise

    def detach_payment_method(self, payment_method_id: str) -> bool:
        """Detach payment method from customer"""
        try:
            stripe.PaymentMethod.detach(payment_method_id)
            logger.info(f"✓ Payment method detached: {payment_method_id}")
            return True
        except stripe.error.StripeError as e:
            logger.error(f"✗ Failed to detach payment method: {e}")
            return False

    def list_payment_methods(self, customer_id: str) -> List[stripe.PaymentMethod]:
        """List customer's payment methods"""
        try:
            payment_methods = stripe.PaymentMethod.list(
                customer=customer_id,
                type="card",
            )
            return payment_methods.data
        except stripe.error.StripeError as e:
            logger.error(f"✗ Failed to list payment methods: {e}")
            return []

    # ===========================
    # SUBSCRIPTION MANAGEMENT
    # ===========================

    def create_subscription(
        self,
        customer_id: str,
        plan_id: str,
        billing_cycle: str = "monthly",
        trial_days: int = 0,
        payment_method_id: Optional[str] = None,
        metadata: Optional[Dict] = None
    ) -> stripe.Subscription:
        """
        Create a subscription

        Args:
            customer_id: Stripe customer ID
            plan_id: Plan identifier (basic, premium, ultra)
            billing_cycle: monthly or yearly
            trial_days: Trial period in days (0 = no trial)
            payment_method_id: Payment method to use
            metadata: Additional metadata

        Returns:
            Stripe Subscription object
        """
        try:
            plan = self.get_plan_details(plan_id)
            if not plan:
                raise ValueError(f"Invalid plan ID: {plan_id}")

            # Get price ID based on billing cycle
            price_key = f"stripe_price_id_{billing_cycle}"
            price_id = plan.get(price_key)

            if not price_id:
                raise ValueError(f"Price ID not configured for {plan_id}/{billing_cycle}")

            # Prepare subscription data
            subscription_data = {
                "customer": customer_id,
                "items": [{"price": price_id}],
                "metadata": metadata or {},
                "expand": ["latest_invoice.payment_intent"],
            }

            # Add trial period
            if trial_days > 0:
                trial_end = datetime.utcnow() + timedelta(days=trial_days)
                subscription_data["trial_end"] = int(trial_end.timestamp())

            # Add payment method
            if payment_method_id:
                subscription_data["default_payment_method"] = payment_method_id

            # Automatic tax calculation (if configured)
            subscription_data["automatic_tax"] = {"enabled": True}

            # Create subscription
            subscription = stripe.Subscription.create(**subscription_data)

            logger.info(f"✓ Subscription created: {subscription.id} ({plan_id}/{billing_cycle})")
            return subscription

        except stripe.error.StripeError as e:
            logger.error(f"✗ Failed to create subscription: {e}")
            raise

    def get_subscription(self, subscription_id: str) -> Optional[stripe.Subscription]:
        """Get subscription by ID"""
        try:
            return stripe.Subscription.retrieve(subscription_id)
        except stripe.error.StripeError as e:
            logger.error(f"✗ Failed to retrieve subscription: {e}")
            return None

    def update_subscription(
        self,
        subscription_id: str,
        plan_id: Optional[str] = None,
        billing_cycle: Optional[str] = None,
        payment_method_id: Optional[str] = None,
        proration_behavior: str = "create_prorations"
    ) -> stripe.Subscription:
        """
        Update subscription (upgrade/downgrade)

        Args:
            subscription_id: Subscription to update
            plan_id: New plan ID
            billing_cycle: New billing cycle
            payment_method_id: New payment method
            proration_behavior: create_prorations, none, always_invoice

        Returns:
            Updated subscription
        """
        try:
            update_data = {
                "proration_behavior": proration_behavior,
            }

            # Update plan
            if plan_id and billing_cycle:
                plan = self.get_plan_details(plan_id)
                price_key = f"stripe_price_id_{billing_cycle}"
                price_id = plan.get(price_key)

                if price_id:
                    subscription = stripe.Subscription.retrieve(subscription_id)
                    update_data["items"] = [{
                        "id": subscription["items"]["data"][0].id,
                        "price": price_id,
                    }]

            # Update payment method
            if payment_method_id:
                update_data["default_payment_method"] = payment_method_id

            subscription = stripe.Subscription.modify(subscription_id, **update_data)
            logger.info(f"✓ Subscription updated: {subscription_id}")
            return subscription

        except stripe.error.StripeError as e:
            logger.error(f"✗ Failed to update subscription: {e}")
            raise

    def cancel_subscription(
        self,
        subscription_id: str,
        cancel_at_period_end: bool = True,
        cancellation_reason: Optional[str] = None
    ) -> stripe.Subscription:
        """
        Cancel subscription

        Args:
            subscription_id: Subscription to cancel
            cancel_at_period_end: If True, cancel at end of billing period
            cancellation_reason: Reason for cancellation

        Returns:
            Canceled subscription
        """
        try:
            if cancel_at_period_end:
                # Cancel at period end (user keeps access until then)
                subscription = stripe.Subscription.modify(
                    subscription_id,
                    cancel_at_period_end=True,
                    cancellation_details={
                        "comment": cancellation_reason or "User requested cancellation"
                    }
                )
                logger.info(f"✓ Subscription set to cancel at period end: {subscription_id}")
            else:
                # Cancel immediately
                subscription = stripe.Subscription.delete(
                    subscription_id,
                    prorate=True
                )
                logger.info(f"✓ Subscription canceled immediately: {subscription_id}")

            return subscription

        except stripe.error.StripeError as e:
            logger.error(f"✗ Failed to cancel subscription: {e}")
            raise

    def reactivate_subscription(self, subscription_id: str) -> stripe.Subscription:
        """Reactivate a canceled subscription (before period end)"""
        try:
            subscription = stripe.Subscription.modify(
                subscription_id,
                cancel_at_period_end=False,
            )
            logger.info(f"✓ Subscription reactivated: {subscription_id}")
            return subscription
        except stripe.error.StripeError as e:
            logger.error(f"✗ Failed to reactivate subscription: {e}")
            raise

    # ===========================
    # INVOICE MANAGEMENT
    # ===========================

    def get_invoice(self, invoice_id: str) -> Optional[stripe.Invoice]:
        """Get invoice by ID"""
        try:
            return stripe.Invoice.retrieve(invoice_id)
        except stripe.error.StripeError as e:
            logger.error(f"✗ Failed to retrieve invoice: {e}")
            return None

    def list_invoices(
        self,
        customer_id: str,
        limit: int = 10
    ) -> List[stripe.Invoice]:
        """List customer invoices"""
        try:
            invoices = stripe.Invoice.list(
                customer=customer_id,
                limit=limit,
            )
            return invoices.data
        except stripe.error.StripeError as e:
            logger.error(f"✗ Failed to list invoices: {e}")
            return []

    def create_invoice_item(
        self,
        customer_id: str,
        amount: float,
        currency: str = "usd",
        description: Optional[str] = None
    ) -> stripe.InvoiceItem:
        """Create one-time invoice item (for additional charges)"""
        try:
            amount_cents = int(amount * 100)  # Convert to cents
            invoice_item = stripe.InvoiceItem.create(
                customer=customer_id,
                amount=amount_cents,
                currency=currency,
                description=description,
            )
            logger.info(f"✓ Invoice item created: {invoice_item.id}")
            return invoice_item
        except stripe.error.StripeError as e:
            logger.error(f"✗ Failed to create invoice item: {e}")
            raise

    # ===========================
    # WEBHOOK HANDLING
    # ===========================

    @staticmethod
    def construct_webhook_event(
        payload: bytes,
        signature: str
    ) -> stripe.Event:
        """
        Verify and construct webhook event from Stripe

        Args:
            payload: Raw request body
            signature: Stripe-Signature header

        Returns:
            Verified Stripe Event

        Raises:
            ValueError: If signature verification fails
        """
        try:
            event = stripe.Webhook.construct_event(
                payload,
                signature,
                STRIPE_WEBHOOK_SECRET
            )
            logger.info(f"✓ Webhook event verified: {event['type']}")
            return event
        except ValueError as e:
            logger.error(f"✗ Invalid webhook signature: {e}")
            raise
        except Exception as e:
            logger.error(f"✗ Webhook error: {e}")
            raise

    # ===========================
    # PAYMENT INTENT (for one-time payments)
    # ===========================

    def create_payment_intent(
        self,
        amount: float,
        currency: str = "usd",
        customer_id: Optional[str] = None,
        description: Optional[str] = None,
        metadata: Optional[Dict] = None
    ) -> stripe.PaymentIntent:
        """
        Create payment intent for one-time payment

        Args:
            amount: Amount in dollars
            currency: Currency code
            customer_id: Optional customer ID
            description: Payment description
            metadata: Additional metadata

        Returns:
            PaymentIntent object with client_secret for frontend
        """
        try:
            amount_cents = int(amount * 100)  # Convert to cents

            payment_intent = stripe.PaymentIntent.create(
                amount=amount_cents,
                currency=currency,
                customer=customer_id,
                description=description,
                metadata=metadata or {},
                automatic_payment_methods={"enabled": True},
            )

            logger.info(f"✓ Payment intent created: {payment_intent.id} (${amount})")
            return payment_intent

        except stripe.error.StripeError as e:
            logger.error(f"✗ Failed to create payment intent: {e}")
            raise

    # ===========================
    # BILLING PORTAL
    # ===========================

    def create_billing_portal_session(
        self,
        customer_id: str,
        return_url: str
    ) -> stripe.billing_portal.Session:
        """
        Create customer billing portal session

        Allows customers to:
        - Update payment method
        - View invoices
        - Cancel subscription
        - Download receipts

        Args:
            customer_id: Stripe customer ID
            return_url: URL to return to after portal session

        Returns:
            BillingPortal.Session with url
        """
        try:
            session = stripe.billing_portal.Session.create(
                customer=customer_id,
                return_url=return_url,
            )
            logger.info(f"✓ Billing portal session created for customer: {customer_id}")
            return session
        except stripe.error.StripeError as e:
            logger.error(f"✗ Failed to create billing portal session: {e}")
            raise

    # ===========================
    # CHECKOUT SESSION (Alternative to custom form)
    # ===========================

    def create_checkout_session(
        self,
        customer_id: str,
        plan_id: str,
        billing_cycle: str = "monthly",
        success_url: str = "",
        cancel_url: str = "",
        trial_days: int = 0
    ) -> stripe.checkout.Session:
        """
        Create Stripe Checkout session (hosted payment page)

        Args:
            customer_id: Stripe customer ID
            plan_id: Plan to subscribe to
            billing_cycle: monthly or yearly
            success_url: Redirect URL on success
            cancel_url: Redirect URL on cancel
            trial_days: Trial period in days

        Returns:
            Checkout.Session with url
        """
        try:
            plan = self.get_plan_details(plan_id)
            price_key = f"stripe_price_id_{billing_cycle}"
            price_id = plan.get(price_key)

            session_data = {
                "customer": customer_id,
                "mode": "subscription",
                "line_items": [{
                    "price": price_id,
                    "quantity": 1,
                }],
                "success_url": success_url,
                "cancel_url": cancel_url,
            }

            # Add trial
            if trial_days > 0:
                session_data["subscription_data"] = {
                    "trial_period_days": trial_days
                }

            session = stripe.checkout.Session.create(**session_data)
            logger.info(f"✓ Checkout session created: {session.id}")
            return session

        except stripe.error.StripeError as e:
            logger.error(f"✗ Failed to create checkout session: {e}")
            raise
