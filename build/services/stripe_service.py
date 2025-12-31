import os
from typing import Optional

import stripe

stripe.api_key = os.getenv("STRIPE_SECRET_KEY", "")


class StripeService:
    def __init__(self):
        self.base_url = os.getenv("APP_BASE_URL", "https://securewave-app.azurewebsites.net")
        self.price_id = os.getenv("STRIPE_PRICE_ID")
        self.currency = os.getenv("STRIPE_CURRENCY", "usd")
        self.amount_cents = int(float(os.getenv("SUBSCRIPTION_PRICE", "9.99")) * 100)

    def create_checkout_session(self, email: str) -> Optional[str]:
        if not stripe.api_key:
            return None
        line_item = (
            {"price": self.price_id, "quantity": 1}
            if self.price_id
            else {
                "price_data": {
                    "currency": self.currency,
                    "product_data": {"name": "SecureWave VPN"},
                    "unit_amount": self.amount_cents,
                    "recurring": {"interval": "month"},
                },
                "quantity": 1,
            }
        )
        session = stripe.checkout.Session.create(
            payment_method_types=["card"],
            mode="subscription",
            line_items=[line_item],
            customer_email=email,
            success_url=f"{self.base_url}/subscription.html?status=success",
            cancel_url=f"{self.base_url}/subscription.html?status=cancel",
        )
        return session.url
