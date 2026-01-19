"""
SecureWave VPN - PayPal Payment Integration Service
Complete PayPal integration for subscription management and payment processing
"""

import os
import logging
import base64
import requests
from typing import Dict, Optional, List
from datetime import datetime, timedelta
from dotenv import load_dotenv

# Load environment variables
load_dotenv()
load_dotenv(".env.production")

logger = logging.getLogger(__name__)

# PayPal configuration
PAYPAL_CLIENT_ID = os.getenv("PAYPAL_CLIENT_ID")
PAYPAL_CLIENT_SECRET = os.getenv("PAYPAL_CLIENT_SECRET")
PAYPAL_MODE = os.getenv("PAYPAL_MODE", "sandbox")  # sandbox or live

# API URLs
PAYPAL_API_BASE = (
    "https://api-m.paypal.com" if PAYPAL_MODE == "live"
    else "https://api-m.sandbox.paypal.com"
)


class PayPalService:
    """
    Production-grade PayPal integration service
    Handles subscriptions, billing plans, and webhook verification
    """

    # Subscription plans configuration (mirrors Stripe)
    PLANS = {
        "basic": {
            "name": "Basic Plan",
            "description": "3 VPN connections with unlimited bandwidth",
            "price_monthly": 9.99,
            "price_yearly": 99.99,
            "paypal_plan_id_monthly": os.getenv("PAYPAL_PLAN_BASIC_MONTHLY"),
            "paypal_plan_id_yearly": os.getenv("PAYPAL_PLAN_BASIC_YEARLY"),
        },
        "premium": {
            "name": "Premium Plan",
            "description": "5 VPN connections with unlimited bandwidth",
            "price_monthly": 9.99,
            "price_yearly": 99.99,
            "paypal_plan_id_monthly": os.getenv("PAYPAL_PLAN_PREMIUM_MONTHLY"),
            "paypal_plan_id_yearly": os.getenv("PAYPAL_PLAN_PREMIUM_YEARLY"),
        },
        "ultra": {
            "name": "Ultra Plan",
            "description": "10 VPN connections with VIP support",
            "price_monthly": 24.99,
            "price_yearly": 249.99,
            "paypal_plan_id_monthly": os.getenv("PAYPAL_PLAN_ULTRA_MONTHLY"),
            "paypal_plan_id_yearly": os.getenv("PAYPAL_PLAN_ULTRA_YEARLY"),
        },
    }

    def __init__(self):
        """Initialize PayPal service"""
        if not PAYPAL_CLIENT_ID or not PAYPAL_CLIENT_SECRET:
            logger.warning("PayPal credentials not configured - PayPal integration disabled")
        self.access_token = None
        self.token_expires_at = None

    @classmethod
    def get_plan_details(cls, plan_id: str) -> Optional[Dict]:
        """Get plan configuration"""
        return cls.PLANS.get(plan_id)

    @classmethod
    def get_all_plans(cls) -> Dict:
        """Get all available plans"""
        return cls.PLANS

    # ===========================
    # AUTHENTICATION
    # ===========================

    def get_access_token(self) -> str:
        """
        Get OAuth2 access token from PayPal

        Returns:
            Access token string
        """
        # Return cached token if still valid
        if self.access_token and self.token_expires_at:
            if datetime.utcnow() < self.token_expires_at:
                return self.access_token

        # Get new token
        try:
            auth_string = f"{PAYPAL_CLIENT_ID}:{PAYPAL_CLIENT_SECRET}"
            auth_bytes = auth_string.encode('utf-8')
            auth_b64 = base64.b64encode(auth_bytes).decode('utf-8')

            headers = {
                "Authorization": f"Basic {auth_b64}",
                "Content-Type": "application/x-www-form-urlencoded"
            }

            data = {"grant_type": "client_credentials"}

            response = requests.post(
                f"{PAYPAL_API_BASE}/v1/oauth2/token",
                headers=headers,
                data=data,
                timeout=10
            )
            response.raise_for_status()

            token_data = response.json()
            self.access_token = token_data["access_token"]
            expires_in = token_data.get("expires_in", 3600)
            self.token_expires_at = datetime.utcnow() + timedelta(seconds=expires_in - 60)

            logger.info("✓ PayPal access token obtained")
            return self.access_token

        except requests.exceptions.RequestException as e:
            logger.error(f"✗ Failed to get PayPal access token: {e}")
            raise

    def _get_headers(self) -> Dict:
        """Get headers with authorization"""
        token = self.get_access_token()
        return {
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
            "Accept": "application/json"
        }

    # ===========================
    # BILLING PLAN MANAGEMENT
    # ===========================

    def create_billing_plan(
        self,
        plan_id: str,
        billing_cycle: str = "monthly"
    ) -> Dict:
        """
        Create PayPal billing plan

        Args:
            plan_id: Plan identifier (basic, premium, ultra)
            billing_cycle: monthly or yearly

        Returns:
            Created plan details
        """
        try:
            plan = self.get_plan_details(plan_id)
            if not plan:
                raise ValueError(f"Invalid plan ID: {plan_id}")

            price = plan[f"price_{billing_cycle}"]

            # Billing cycle configuration
            if billing_cycle == "monthly":
                frequency = {"interval_unit": "MONTH", "interval_count": 1}
            else:  # yearly
                frequency = {"interval_unit": "YEAR", "interval_count": 1}

            plan_data = {
                "product_id": os.getenv(f"PAYPAL_PRODUCT_ID_{plan_id.upper()}"),
                "name": f"{plan['name']} - {billing_cycle.title()}",
                "description": plan["description"],
                "status": "ACTIVE",
                "billing_cycles": [
                    {
                        "frequency": frequency,
                        "tenure_type": "REGULAR",
                        "sequence": 1,
                        "total_cycles": 0,  # Infinite
                        "pricing_scheme": {
                            "fixed_price": {
                                "value": str(price),
                                "currency_code": "USD"
                            }
                        }
                    }
                ],
                "payment_preferences": {
                    "auto_bill_outstanding": True,
                    "setup_fee": {
                        "value": "0",
                        "currency_code": "USD"
                    },
                    "setup_fee_failure_action": "CONTINUE",
                    "payment_failure_threshold": 3
                }
            }

            response = requests.post(
                f"{PAYPAL_API_BASE}/v1/billing/plans",
                headers=self._get_headers(),
                json=plan_data,
                timeout=10
            )
            response.raise_for_status()

            plan_response = response.json()
            logger.info(f"✓ PayPal billing plan created: {plan_response['id']}")
            return plan_response

        except requests.exceptions.RequestException as e:
            logger.error(f"✗ Failed to create billing plan: {e}")
            raise

    def get_billing_plan(self, plan_id: str) -> Dict:
        """Get billing plan details"""
        try:
            response = requests.get(
                f"{PAYPAL_API_BASE}/v1/billing/plans/{plan_id}",
                headers=self._get_headers(),
                timeout=10
            )
            response.raise_for_status()
            return response.json()
        except requests.exceptions.RequestException as e:
            logger.error(f"✗ Failed to get billing plan: {e}")
            raise

    # ===========================
    # SUBSCRIPTION MANAGEMENT
    # ===========================

    def create_subscription(
        self,
        plan_id: str,
        billing_cycle: str = "monthly",
        subscriber_email: Optional[str] = None,
        subscriber_name: Optional[Dict] = None,
        return_url: str = "",
        cancel_url: str = ""
    ) -> Dict:
        """
        Create PayPal subscription

        Args:
            plan_id: Plan identifier (basic, premium, ultra)
            billing_cycle: monthly or yearly
            subscriber_email: Customer email
            subscriber_name: Customer name dict (given_name, surname)
            return_url: Redirect URL after approval
            cancel_url: Redirect URL on cancel

        Returns:
            Subscription details with approval URL
        """
        try:
            plan = self.get_plan_details(plan_id)
            if not plan:
                raise ValueError(f"Invalid plan ID: {plan_id}")

            paypal_plan_id = plan.get(f"paypal_plan_id_{billing_cycle}")
            if not paypal_plan_id:
                raise ValueError(f"PayPal plan ID not configured for {plan_id}/{billing_cycle}")

            subscription_data = {
                "plan_id": paypal_plan_id,
                "application_context": {
                    "brand_name": "SecureWave VPN",
                    "locale": "en-US",
                    "shipping_preference": "NO_SHIPPING",
                    "user_action": "SUBSCRIBE_NOW",
                    "return_url": return_url,
                    "cancel_url": cancel_url
                }
            }

            # Add subscriber info
            if subscriber_email or subscriber_name:
                subscriber = {}
                if subscriber_email:
                    subscriber["email_address"] = subscriber_email
                if subscriber_name:
                    subscriber["name"] = subscriber_name
                subscription_data["subscriber"] = subscriber

            response = requests.post(
                f"{PAYPAL_API_BASE}/v1/billing/subscriptions",
                headers=self._get_headers(),
                json=subscription_data,
                timeout=10
            )
            response.raise_for_status()

            subscription = response.json()

            # Extract approval URL
            approval_url = None
            for link in subscription.get("links", []):
                if link.get("rel") == "approve":
                    approval_url = link.get("href")
                    break

            logger.info(f"✓ PayPal subscription created: {subscription['id']}")

            return {
                "subscription_id": subscription["id"],
                "status": subscription["status"],
                "approval_url": approval_url,
                "plan_id": paypal_plan_id
            }

        except requests.exceptions.RequestException as e:
            logger.error(f"✗ Failed to create subscription: {e}")
            raise

    def get_subscription(self, subscription_id: str) -> Dict:
        """Get subscription details"""
        try:
            response = requests.get(
                f"{PAYPAL_API_BASE}/v1/billing/subscriptions/{subscription_id}",
                headers=self._get_headers(),
                timeout=10
            )
            response.raise_for_status()
            return response.json()
        except requests.exceptions.RequestException as e:
            logger.error(f"✗ Failed to get subscription: {e}")
            raise

    def cancel_subscription(
        self,
        subscription_id: str,
        reason: Optional[str] = None
    ) -> bool:
        """
        Cancel PayPal subscription

        Args:
            subscription_id: Subscription to cancel
            reason: Cancellation reason

        Returns:
            True if successful
        """
        try:
            data = {
                "reason": reason or "Customer requested cancellation"
            }

            response = requests.post(
                f"{PAYPAL_API_BASE}/v1/billing/subscriptions/{subscription_id}/cancel",
                headers=self._get_headers(),
                json=data,
                timeout=10
            )
            response.raise_for_status()

            logger.info(f"✓ PayPal subscription canceled: {subscription_id}")
            return True

        except requests.exceptions.RequestException as e:
            logger.error(f"✗ Failed to cancel subscription: {e}")
            return False

    def suspend_subscription(self, subscription_id: str, reason: Optional[str] = None) -> bool:
        """Suspend subscription (can be reactivated)"""
        try:
            data = {
                "reason": reason or "Temporary suspension"
            }

            response = requests.post(
                f"{PAYPAL_API_BASE}/v1/billing/subscriptions/{subscription_id}/suspend",
                headers=self._get_headers(),
                json=data,
                timeout=10
            )
            response.raise_for_status()

            logger.info(f"✓ PayPal subscription suspended: {subscription_id}")
            return True

        except requests.exceptions.RequestException as e:
            logger.error(f"✗ Failed to suspend subscription: {e}")
            return False

    def reactivate_subscription(
        self,
        subscription_id: str,
        reason: Optional[str] = None
    ) -> bool:
        """Reactivate suspended subscription"""
        try:
            data = {
                "reason": reason or "Customer reactivated subscription"
            }

            response = requests.post(
                f"{PAYPAL_API_BASE}/v1/billing/subscriptions/{subscription_id}/activate",
                headers=self._get_headers(),
                json=data,
                timeout=10
            )
            response.raise_for_status()

            logger.info(f"✓ PayPal subscription reactivated: {subscription_id}")
            return True

        except requests.exceptions.RequestException as e:
            logger.error(f"✗ Failed to reactivate subscription: {e}")
            return False

    def update_subscription_plan(
        self,
        subscription_id: str,
        new_plan_id: str,
        billing_cycle: str = "monthly"
    ) -> bool:
        """
        Update subscription to new plan

        Args:
            subscription_id: Subscription to update
            new_plan_id: New plan identifier
            billing_cycle: New billing cycle

        Returns:
            True if successful
        """
        try:
            plan = self.get_plan_details(new_plan_id)
            if not plan:
                raise ValueError(f"Invalid plan ID: {new_plan_id}")

            paypal_plan_id = plan.get(f"paypal_plan_id_{billing_cycle}")

            data = {
                "plan_id": paypal_plan_id
            }

            response = requests.post(
                f"{PAYPAL_API_BASE}/v1/billing/subscriptions/{subscription_id}/revise",
                headers=self._get_headers(),
                json=data,
                timeout=10
            )
            response.raise_for_status()

            logger.info(f"✓ PayPal subscription updated: {subscription_id}")
            return True

        except requests.exceptions.RequestException as e:
            logger.error(f"✗ Failed to update subscription: {e}")
            return False

    # ===========================
    # TRANSACTION MANAGEMENT
    # ===========================

    def list_subscription_transactions(
        self,
        subscription_id: str,
        start_time: Optional[str] = None,
        end_time: Optional[str] = None
    ) -> List[Dict]:
        """
        List subscription transactions

        Args:
            subscription_id: Subscription ID
            start_time: Start time (ISO format)
            end_time: End time (ISO format)

        Returns:
            List of transactions
        """
        try:
            # Default to last 30 days
            if not start_time:
                start_time = (datetime.utcnow() - timedelta(days=30)).isoformat() + "Z"
            if not end_time:
                end_time = datetime.utcnow().isoformat() + "Z"

            params = {
                "start_time": start_time,
                "end_time": end_time
            }

            response = requests.get(
                f"{PAYPAL_API_BASE}/v1/billing/subscriptions/{subscription_id}/transactions",
                headers=self._get_headers(),
                params=params,
                timeout=10
            )
            response.raise_for_status()

            transactions = response.json().get("transactions", [])
            return transactions

        except requests.exceptions.RequestException as e:
            logger.error(f"✗ Failed to list transactions: {e}")
            return []

    # ===========================
    # WEBHOOK VERIFICATION
    # ===========================

    def verify_webhook_signature(
        self,
        headers: Dict,
        body: str
    ) -> bool:
        """
        Verify PayPal webhook signature

        Args:
            headers: Request headers
            body: Raw request body

        Returns:
            True if signature is valid
        """
        try:
            webhook_id = os.getenv("PAYPAL_WEBHOOK_ID")
            if not webhook_id:
                logger.warning("PAYPAL_WEBHOOK_ID not configured")
                return False

            # Extract signature headers
            transmission_id = headers.get("Paypal-Transmission-Id")
            transmission_time = headers.get("Paypal-Transmission-Time")
            transmission_sig = headers.get("Paypal-Transmission-Sig")
            cert_url = headers.get("Paypal-Cert-Url")
            auth_algo = headers.get("Paypal-Auth-Algo")

            if not all([transmission_id, transmission_time, transmission_sig, cert_url, auth_algo]):
                logger.error("Missing webhook signature headers")
                return False

            # Verify signature via PayPal API
            verification_data = {
                "transmission_id": transmission_id,
                "transmission_time": transmission_time,
                "cert_url": cert_url,
                "auth_algo": auth_algo,
                "transmission_sig": transmission_sig,
                "webhook_id": webhook_id,
                "webhook_event": body
            }

            response = requests.post(
                f"{PAYPAL_API_BASE}/v1/notifications/verify-webhook-signature",
                headers=self._get_headers(),
                json=verification_data,
                timeout=10
            )
            response.raise_for_status()

            verification_status = response.json().get("verification_status")
            is_valid = verification_status == "SUCCESS"

            if is_valid:
                logger.info("✓ PayPal webhook signature verified")
            else:
                logger.warning(f"✗ Invalid PayPal webhook signature: {verification_status}")

            return is_valid

        except requests.exceptions.RequestException as e:
            logger.error(f"✗ Webhook verification failed: {e}")
            return False

    # ===========================
    # PAYMENT CAPTURE (for one-time payments)
    # ===========================

    def create_order(
        self,
        amount: float,
        currency: str = "USD",
        description: str = "SecureWave VPN Payment"
    ) -> Dict:
        """
        Create PayPal order for one-time payment

        Args:
            amount: Payment amount
            currency: Currency code
            description: Payment description

        Returns:
            Order details with approval URL
        """
        try:
            order_data = {
                "intent": "CAPTURE",
                "purchase_units": [
                    {
                        "description": description,
                        "amount": {
                            "currency_code": currency,
                            "value": f"{amount:.2f}"
                        }
                    }
                ],
                "application_context": {
                    "brand_name": "SecureWave VPN",
                    "locale": "en-US",
                    "user_action": "PAY_NOW",
                    "return_url": os.getenv("PAYPAL_RETURN_URL", ""),
                    "cancel_url": os.getenv("PAYPAL_CANCEL_URL", "")
                }
            }

            response = requests.post(
                f"{PAYPAL_API_BASE}/v2/checkout/orders",
                headers=self._get_headers(),
                json=order_data,
                timeout=10
            )
            response.raise_for_status()

            order = response.json()

            # Extract approval URL
            approval_url = None
            for link in order.get("links", []):
                if link.get("rel") == "approve":
                    approval_url = link.get("href")
                    break

            logger.info(f"✓ PayPal order created: {order['id']}")

            return {
                "order_id": order["id"],
                "status": order["status"],
                "approval_url": approval_url
            }

        except requests.exceptions.RequestException as e:
            logger.error(f"✗ Failed to create order: {e}")
            raise

    def capture_order(self, order_id: str) -> Dict:
        """Capture payment for approved order"""
        try:
            response = requests.post(
                f"{PAYPAL_API_BASE}/v2/checkout/orders/{order_id}/capture",
                headers=self._get_headers(),
                timeout=10
            )
            response.raise_for_status()

            capture_result = response.json()
            logger.info(f"✓ PayPal order captured: {order_id}")
            return capture_result

        except requests.exceptions.RequestException as e:
            logger.error(f"✗ Failed to capture order: {e}")
            raise
