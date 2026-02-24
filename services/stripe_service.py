"""
SecureWave VPN - Stripe Payment Integration Service
Complete Stripe integration for subscription management and payment processing
"""

import os
import uuid
import logging
import time
from typing import Dict, Optional, List
from datetime import datetime, timedelta

import stripe

logger = logging.getLogger(__name__)

STRIPE_API_VERSION = "2023-10-16"


def _stripe_secret_key() -> str:
    return (os.getenv("STRIPE_SECRET_KEY") or "").strip()


def _configure_stripe() -> None:
    # Stripe uses global module config; keep it in sync with env for tests and
    # multi-process deployments.
    stripe.api_key = _stripe_secret_key()
    stripe.api_version = STRIPE_API_VERSION


def _is_test_mode() -> bool:
    """Check if Stripe is configured with test keys."""
    key = _stripe_secret_key()
    return key.startswith("sk_test_")


def _is_live_mode() -> bool:
    """Check if Stripe is configured with live keys."""
    key = _stripe_secret_key()
    return key.startswith("sk_live_")


def _idempotency_key(prefix: str = "") -> str:
    """Generate a unique idempotency key for Stripe API calls."""
    return f"sw_{prefix}_{uuid.uuid4().hex}"


def stripe_mode_label() -> str:
    """Return 'test' or 'live' for logging/UI display."""
    if _is_test_mode():
        return "test"
    if _is_live_mode():
        return "live"
    return "unconfigured"


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
            "price_monthly": 9.99,
            "price_yearly": 99.99,  # ~$8.33/month (17% discount)
            "features": [
                "5 VPN connections",
                "Unlimited bandwidth",
                "All server locations",
                "Priority support",
                "Ad-blocking DNS"
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
        _configure_stripe()
        if not stripe.api_key:
            logger.warning("STRIPE_SECRET_KEY not configured - Stripe integration disabled")
        else:
            logger.info(f"Stripe initialized in {stripe_mode_label()} mode")

    @staticmethod
    def _ensure_configured() -> None:
        _configure_stripe()
        if not stripe.api_key:
            raise ValueError("STRIPE_SECRET_KEY is not configured")

    @classmethod
    def get_plan_details(cls, plan_id: str) -> Optional[Dict]:
        """Get plan configuration"""
        plan = cls.PLANS.get(plan_id)
        if not plan:
            return None
        data = dict(plan)

        # Price IDs must be read from the environment at runtime so tests can
        # override env vars and so deployments can rotate Price IDs without
        # requiring module reloads.
        if plan_id and plan_id != "free":
            env_prefix = plan_id.upper()
            monthly = os.getenv(f"STRIPE_PRICE_{env_prefix}_MONTHLY")
            yearly = os.getenv(f"STRIPE_PRICE_{env_prefix}_YEARLY")
            if monthly:
                data["stripe_price_id_monthly"] = monthly
            if yearly:
                data["stripe_price_id_yearly"] = yearly
        return data

    @classmethod
    def get_all_plans(cls) -> Dict:
        """Get all available plans"""
        return {pid: cls.get_plan_details(pid) for pid in cls.PLANS.keys()}

    @classmethod
    def resolve_plan_from_price_id(cls, price_id: str) -> Optional[Dict[str, str]]:
        """
        Best-effort mapping from a Stripe Price ID to a SecureWave plan.

        Returns {"plan_id": ..., "billing_cycle": ...} when a match is found.
        """
        if not price_id:
            return None
        for plan_id in cls.PLANS.keys():
            plan = cls.get_plan_details(plan_id) or {}
            for cycle in ("monthly", "yearly"):
                if plan.get(f"stripe_price_id_{cycle}") == price_id:
                    return {"plan_id": plan_id, "billing_cycle": cycle}
        return None

    # ===========================
    # CUSTOMER MANAGEMENT
    # ===========================

    def create_customer(
        self,
        email: str,
        name: Optional[str] = None,
        phone: Optional[str] = None,
        metadata: Optional[Dict] = None,
        idempotency_key: Optional[str] = None,
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
            self._ensure_configured()
            customer = stripe.Customer.create(
                email=email,
                name=name,
                phone=phone,
                metadata=metadata or {},
                idempotency_key=idempotency_key or _idempotency_key("cust"),
            )

            logger.info("Stripe customer created: %s", customer.id)
            return customer

        except stripe.error.StripeError as e:
            logger.error(f"✗ Failed to create Stripe customer: {e}")
            raise

    def get_customer(self, customer_id: str) -> Optional[stripe.Customer]:
        """Get customer by ID"""
        try:
            self._ensure_configured()
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
            self._ensure_configured()
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
            self._ensure_configured()
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
            self._ensure_configured()
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
            self._ensure_configured()
            stripe.PaymentMethod.detach(payment_method_id)
            logger.info(f"✓ Payment method detached: {payment_method_id}")
            return True
        except stripe.error.StripeError as e:
            logger.error(f"✗ Failed to detach payment method: {e}")
            return False

    def list_payment_methods(self, customer_id: str) -> List[stripe.PaymentMethod]:
        """List customer's payment methods"""
        try:
            self._ensure_configured()
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
        metadata: Optional[Dict] = None,
        idempotency_key: Optional[str] = None,
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
            self._ensure_configured()
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

            # Create subscription with idempotency
            subscription_data["idempotency_key"] = idempotency_key or _idempotency_key("sub")
            subscription = stripe.Subscription.create(**subscription_data)

            logger.info(f"✓ Subscription created: {subscription.id} ({plan_id}/{billing_cycle})")
            return subscription

        except stripe.error.StripeError as e:
            logger.error(f"✗ Failed to create subscription: {e}")
            raise

    def get_subscription(self, subscription_id: str) -> Optional[stripe.Subscription]:
        """Get subscription by ID"""
        try:
            self._ensure_configured()
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
        proration_behavior: str = "create_prorations",
        idempotency_key: Optional[str] = None,
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
            self._ensure_configured()
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

            subscription = stripe.Subscription.modify(
                subscription_id,
                **update_data,
                idempotency_key=idempotency_key or _idempotency_key("submod"),
            )
            logger.info(f"✓ Subscription updated: {subscription_id}")
            return subscription

        except stripe.error.StripeError as e:
            logger.error(f"✗ Failed to update subscription: {e}")
            raise

    def cancel_subscription(
        self,
        subscription_id: str,
        cancel_at_period_end: bool = True,
        cancellation_reason: Optional[str] = None,
        idempotency_key: Optional[str] = None,
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
            self._ensure_configured()
            if cancel_at_period_end:
                # Cancel at period end (user keeps access until then)
                subscription = stripe.Subscription.modify(
                    subscription_id,
                    cancel_at_period_end=True,
                    cancellation_details={
                        "comment": cancellation_reason or "User requested cancellation"
                    },
                    idempotency_key=idempotency_key or _idempotency_key("subcancel"),
                )
                logger.info(f"✓ Subscription set to cancel at period end: {subscription_id}")
            else:
                # Cancel immediately
                subscription = stripe.Subscription.delete(
                    subscription_id,
                    prorate=True,
                    idempotency_key=idempotency_key or _idempotency_key("subcancel"),
                )
                logger.info(f"✓ Subscription canceled immediately: {subscription_id}")

            return subscription

        except stripe.error.StripeError as e:
            logger.error(f"✗ Failed to cancel subscription: {e}")
            raise

    def reactivate_subscription(self, subscription_id: str, *, idempotency_key: Optional[str] = None) -> stripe.Subscription:
        """Reactivate a canceled subscription (before period end)"""
        try:
            self._ensure_configured()
            subscription = stripe.Subscription.modify(
                subscription_id,
                cancel_at_period_end=False,
                idempotency_key=idempotency_key or _idempotency_key("subreactivate"),
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
            self._ensure_configured()
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
            self._ensure_configured()
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
            self._ensure_configured()
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
            webhook_secret = (os.getenv("STRIPE_WEBHOOK_SECRET") or "").strip()
            if not webhook_secret:
                raise ValueError("STRIPE_WEBHOOK_SECRET is not configured")
            tolerance = int(os.getenv("STRIPE_WEBHOOK_TOLERANCE_SECONDS", "300"))
            event = stripe.Webhook.construct_event(
                payload,
                signature,
                webhook_secret,
                tolerance=tolerance,
            )
            # Defense-in-depth: reject stale event objects even if a valid
            # signature is presented (e.g., replay with leaked secret).
            max_event_age = int(os.getenv("STRIPE_WEBHOOK_MAX_EVENT_AGE_SECONDS", "172800"))
            if max_event_age > 0:
                created = event.get("created")
                if created is not None:
                    try:
                        age_seconds = abs(int(time.time()) - int(created))
                    except Exception:
                        age_seconds = 0
                    if age_seconds > max_event_age:
                        raise ValueError(f"Stripe event too old ({age_seconds}s)")
            logger.info("Stripe webhook event verified: %s", event.get("type"))
            return event
        except stripe.error.SignatureVerificationError as e:
            logger.warning("Invalid Stripe webhook signature")
            raise ValueError("Invalid webhook signature") from e
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
            self._ensure_configured()
            amount_cents = int(amount * 100)  # Convert to cents

            payment_intent = stripe.PaymentIntent.create(
                amount=amount_cents,
                currency=currency,
                customer=customer_id,
                description=description,
                metadata=metadata or {},
                automatic_payment_methods={"enabled": True},
                idempotency_key=_idempotency_key("pi"),
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
            self._ensure_configured()
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
        trial_days: int = 0,
        user_id: Optional[int] = None,
        metadata: Optional[Dict] = None,
        idempotency_key: Optional[str] = None,
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
            user_id: SecureWave user ID (used for client_reference_id/metadata)
            metadata: Additional metadata to attach to the session/subscription
            idempotency_key: Provider idempotency key (dedupes at Stripe)

        Returns:
            Checkout.Session with url
        """
        try:
            self._ensure_configured()
            plan = self.get_plan_details(plan_id)
            if not plan:
                raise ValueError(f"Invalid plan ID: {plan_id}")
            price_key = f"stripe_price_id_{billing_cycle}"
            price_id = plan.get(price_key)
            if not price_id:
                raise ValueError(f"Price ID not configured for {plan_id}/{billing_cycle}")

            base_metadata = {
                "securewave_user_id": str(user_id) if user_id is not None else None,
                "plan_id": plan_id,
                "billing_cycle": billing_cycle,
                "stripe_mode": stripe_mode_label(),
            }
            merged_meta = {k: v for k, v in base_metadata.items() if v is not None}
            if metadata:
                merged_meta.update({str(k): str(v) for k, v in metadata.items() if v is not None})

            session_data = {
                "customer": customer_id,
                "client_reference_id": str(user_id) if user_id is not None else customer_id,
                "mode": "subscription",
                "line_items": [{
                    "price": price_id,
                    "quantity": 1,
                }],
                "success_url": success_url,
                "cancel_url": cancel_url,
                "metadata": merged_meta,
            }

            # Ensure subscription metadata is present for reliable webhook mapping.
            subscription_data = {"metadata": merged_meta}
            if trial_days > 0:
                subscription_data["trial_period_days"] = trial_days
            session_data["subscription_data"] = subscription_data

            session = stripe.checkout.Session.create(
                **session_data,
                idempotency_key=idempotency_key or _idempotency_key("checkout"),
            )
            logger.info(f"✓ Checkout session created: {session.id}")
            return session

        except stripe.error.StripeError as e:
            logger.error(f"✗ Failed to create checkout session: {e}")
            raise
