import os
from typing import Optional

import httpx


class PaypalService:
    def __init__(self):
        self.client_id = os.getenv("PAYPAL_CLIENT_ID", "")
        self.client_secret = os.getenv("PAYPAL_CLIENT_SECRET", "")
        mode = os.getenv("PAYPAL_MODE", "sandbox").lower()
        self.base_url = "https://api-m.paypal.com" if mode == "live" else "https://api-m.sandbox.paypal.com"
        self.return_url = os.getenv("APP_BASE_URL", "https://securewave-app.azurewebsites.net") + "/subscription.html"

    async def _access_token(self) -> Optional[str]:
        if not self.client_id or not self.client_secret:
            return None
        async with httpx.AsyncClient() as client:
            response = await client.post(
                f"{self.base_url}/v1/oauth2/token",
                data={"grant_type": "client_credentials"},
                auth=(self.client_id, self.client_secret),
            )
            response.raise_for_status()
            data = response.json()
            return data.get("access_token")

    async def create_order(self, amount: float) -> Optional[dict]:
        token = await self._access_token()
        if not token:
            return None
        headers = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}
        body = {
            "intent": "CAPTURE",
            "purchase_units": [
                {"amount": {"currency_code": "USD", "value": f"{amount:.2f}"}}
            ],
            "application_context": {
                "return_url": self.return_url + "?provider=paypal&status=success",
                "cancel_url": self.return_url + "?provider=paypal&status=cancel",
            },
        }
        async with httpx.AsyncClient() as client:
            resp = await client.post(f"{self.base_url}/v2/checkout/orders", headers=headers, json=body)
            resp.raise_for_status()
            return resp.json()

    async def capture_order(self, order_id: str) -> Optional[dict]:
        token = await self._access_token()
        if not token:
            return None
        headers = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}
        async with httpx.AsyncClient() as client:
            resp = await client.post(f"{self.base_url}/v2/checkout/orders/{order_id}/capture", headers=headers)
            resp.raise_for_status()
            return resp.json()
