"""
Stripe live billing provisioning helpers.

This module creates/reuses the Stripe objects SecureWave needs for production
subscriptions: Products, recurring Prices, a webhook endpoint, and a Customer
Portal configuration. It writes only to caller-selected private env files.
"""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from decimal import Decimal, ROUND_HALF_UP
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional

import stripe

from services.stripe_service import LATEST_STRIPE_API_VERSION, StripeService


MANAGED_BY = "securewave_stripe_billing_provisioner"
WEBHOOK_PATH = "/api/billing/webhooks/stripe"
WEBHOOK_EVENTS = [
    "customer.created",
    "customer.updated",
    "customer.deleted",
    "checkout.session.completed",
    "customer.subscription.created",
    "customer.subscription.updated",
    "customer.subscription.deleted",
    "customer.subscription.trial_will_end",
    "invoice.created",
    "invoice.finalized",
    "invoice.paid",
    "invoice.payment_failed",
    "invoice.payment_action_required",
    "payment_intent.succeeded",
    "payment_intent.payment_failed",
    "charge.succeeded",
    "charge.failed",
    "charge.refunded",
]


def _get(obj: Any, key: str, default: Any = None) -> Any:
    if isinstance(obj, dict):
        return obj.get(key, default)
    return getattr(obj, key, default)


def _data(response: Any) -> List[Any]:
    return list(_get(response, "data", []) or [])


def _iter_collection(response: Any) -> Iterable[Any]:
    auto_paging_iter = getattr(response, "auto_paging_iter", None)
    if callable(auto_paging_iter):
        yield from auto_paging_iter()
        return
    yield from _data(response)


def _metadata(obj: Any) -> Dict[str, str]:
    metadata = _get(obj, "metadata", {}) or {}
    return dict(metadata)


def _amount_cents(amount: float) -> int:
    return int((Decimal(str(amount)) * Decimal("100")).quantize(Decimal("1"), ROUND_HALF_UP))


def _env_bool(name: str, default: bool = False) -> bool:
    value = os.getenv(name)
    if value is None:
        return default
    return value.strip().lower() in ("1", "true", "yes", "on")


def _product_name(plan_id: str, plan: Dict[str, Any]) -> str:
    label = str(plan["name"]).replace(" Plan", "").strip()
    if label.lower().startswith("securewave "):
        return label
    return f"SecureWave {label or plan_id.title()}"


def _lookup_key(plan_id: str, billing_cycle: str) -> str:
    return f"securewave_{plan_id}_{billing_cycle}"


def _price_env_name(plan_id: str, billing_cycle: str) -> str:
    return f"STRIPE_PRICE_{plan_id.upper()}_{billing_cycle.upper()}"


@dataclass
class ProvisionedPrice:
    plan_id: str
    billing_cycle: str
    price_id: str
    created: bool


@dataclass
class ProvisionedProduct:
    plan_id: str
    product_id: str
    created: bool
    prices: Dict[str, ProvisionedPrice] = field(default_factory=dict)


@dataclass
class StripeProvisioningResult:
    products: Dict[str, ProvisionedProduct]
    webhook_endpoint_id: Optional[str]
    webhook_secret: Optional[str]
    webhook_created: bool
    portal_config_id: Optional[str]
    portal_created: bool
    env_file: Optional[Path]
    blockers: List[str] = field(default_factory=list)

    @property
    def env_values(self) -> Dict[str, str]:
        values = {
            "PAYMENTS_MOCK": "false",
            "DEMO_BILLING": "false",
            "PAYMENT_PROVIDER": "stripe",
            "STRIPE_API_VERSION": LATEST_STRIPE_API_VERSION,
            "STRIPE_AUTOMATIC_TAX": "true" if _env_bool("STRIPE_AUTOMATIC_TAX", False) else "false",
        }
        if self.webhook_secret:
            values["STRIPE_WEBHOOK_SECRET"] = self.webhook_secret
        if self.portal_config_id:
            values["STRIPE_PORTAL_CONFIG_ID"] = self.portal_config_id
        for product in self.products.values():
            for billing_cycle, price in product.prices.items():
                values[_price_env_name(product.plan_id, billing_cycle)] = price.price_id
        return values


class StripeBillingProvisioner:
    """Idempotently provision SecureWave Stripe Billing resources."""

    def __init__(
        self,
        *,
        app_url: str,
        secret_key: str,
        publishable_key: str,
        env_file: Optional[Path] = None,
        currency: str = "usd",
        allow_test_mode: bool = False,
        stripe_client: Any = stripe,
    ) -> None:
        self.app_url = app_url.rstrip("/")
        self.secret_key = secret_key.strip()
        self.publishable_key = publishable_key.strip()
        self.env_file = env_file
        self.currency = currency.lower()
        self.allow_test_mode = allow_test_mode
        self.stripe = stripe_client
        self.webhook_url = f"{self.app_url}{WEBHOOK_PATH}"

    def validate(self) -> None:
        if not self.app_url.startswith("https://") and not self.allow_test_mode:
            raise ValueError("APP_URL must be an https:// URL for live Stripe provisioning")
        if not self.secret_key:
            raise ValueError("STRIPE_SECRET_KEY is required")
        if not self.publishable_key:
            raise ValueError("STRIPE_PUBLISHABLE_KEY is required")

        secret_prefixes = ("sk_test_", "rk_test_", "sk_live_", "rk_live_") if self.allow_test_mode else ("sk_live_", "rk_live_")
        publishable_prefixes = ("pk_test_", "pk_live_") if self.allow_test_mode else ("pk_live_",)
        if not self.secret_key.startswith(secret_prefixes):
            raise ValueError("STRIPE_SECRET_KEY must be a live-mode key; pass --allow-test-mode for test setup")
        if not self.publishable_key.startswith(publishable_prefixes):
            raise ValueError("STRIPE_PUBLISHABLE_KEY must be a live-mode key; pass --allow-test-mode for test setup")

    def provision(self, *, write_env_file: bool = True) -> StripeProvisioningResult:
        self.validate()
        self.stripe.api_key = self.secret_key
        self.stripe.api_version = LATEST_STRIPE_API_VERSION

        products: Dict[str, ProvisionedProduct] = {}
        for plan_id, plan in StripeService.get_all_plans().items():
            if plan_id == "free":
                continue
            product, product_created = self._ensure_product(plan_id, plan)
            product_id = _get(product, "id")
            provisioned = ProvisionedProduct(plan_id=plan_id, product_id=product_id, created=product_created)
            for billing_cycle in ("monthly", "yearly"):
                price, price_created = self._ensure_price(plan_id, plan, billing_cycle, product_id)
                provisioned.prices[billing_cycle] = ProvisionedPrice(
                    plan_id=plan_id,
                    billing_cycle=billing_cycle,
                    price_id=_get(price, "id"),
                    created=price_created,
                )
            products[plan_id] = provisioned

        webhook_endpoint, webhook_created = self._ensure_webhook_endpoint()
        webhook_secret = _get(webhook_endpoint, "secret") or os.getenv("STRIPE_WEBHOOK_SECRET")
        portal_config, portal_created = self._ensure_portal_configuration(products)

        blockers: List[str] = []
        if not webhook_secret:
            blockers.append(
                "STRIPE_WEBHOOK_SECRET cannot be read for an existing Stripe webhook endpoint; copy it from the Stripe Dashboard or create a new endpoint."
            )

        result = StripeProvisioningResult(
            products=products,
            webhook_endpoint_id=_get(webhook_endpoint, "id"),
            webhook_secret=webhook_secret,
            webhook_created=webhook_created,
            portal_config_id=_get(portal_config, "id"),
            portal_created=portal_created,
            env_file=self.env_file if write_env_file else None,
            blockers=blockers,
        )

        if write_env_file and self.env_file:
            self.write_env_file(result)
        return result

    def _ensure_product(self, plan_id: str, plan: Dict[str, Any]) -> tuple[Any, bool]:
        product_name = _product_name(plan_id, plan)
        for product in _iter_collection(self.stripe.Product.list(active=True, limit=100)):
            metadata = _metadata(product)
            if metadata.get("securewave_plan_id") == plan_id or _get(product, "name") == product_name:
                return product, False

        product = self.stripe.Product.create(
            name=product_name,
            description=", ".join(plan.get("features", [])[:3]),
            metadata={
                "managed_by": MANAGED_BY,
                "securewave_plan_id": plan_id,
            },
        )
        return product, True

    def _ensure_price(self, plan_id: str, plan: Dict[str, Any], billing_cycle: str, product_id: str) -> tuple[Any, bool]:
        lookup_key = _lookup_key(plan_id, billing_cycle)
        interval = "month" if billing_cycle == "monthly" else "year"
        amount = _amount_cents(plan[f"price_{billing_cycle}"])

        list_by_lookup = self.stripe.Price.list(lookup_keys=[lookup_key], active=True, limit=1)
        for price in _data(list_by_lookup):
            return price, False

        for price in _iter_collection(self.stripe.Price.list(product=product_id, active=True, limit=100)):
            recurring = _get(price, "recurring", {}) or {}
            if (
                _get(price, "lookup_key") == lookup_key
                or (
                    _get(price, "unit_amount") == amount
                    and _get(price, "currency") == self.currency
                    and _get(recurring, "interval") == interval
                )
            ):
                return price, False

        price = self.stripe.Price.create(
            product=product_id,
            unit_amount=amount,
            currency=self.currency,
            lookup_key=lookup_key,
            recurring={"interval": interval},
            metadata={
                "managed_by": MANAGED_BY,
                "securewave_plan_id": plan_id,
                "securewave_billing_cycle": billing_cycle,
                "securewave_env_var": _price_env_name(plan_id, billing_cycle),
            },
        )
        return price, True

    def _ensure_webhook_endpoint(self) -> tuple[Any, bool]:
        for endpoint in _iter_collection(self.stripe.WebhookEndpoint.list(limit=100)):
            if _get(endpoint, "url") == self.webhook_url:
                enabled_events = sorted(_get(endpoint, "enabled_events", []) or [])
                if enabled_events != sorted(WEBHOOK_EVENTS):
                    endpoint = self.stripe.WebhookEndpoint.modify(
                        _get(endpoint, "id"),
                        enabled_events=WEBHOOK_EVENTS,
                        metadata={
                            "managed_by": MANAGED_BY,
                            "securewave_endpoint": "billing_webhook",
                        },
                    )
                return endpoint, False

        endpoint = self.stripe.WebhookEndpoint.create(
            url=self.webhook_url,
            enabled_events=WEBHOOK_EVENTS,
            metadata={
                "managed_by": MANAGED_BY,
                "securewave_endpoint": "billing_webhook",
            },
        )
        return endpoint, True

    def _ensure_portal_configuration(self, products: Dict[str, ProvisionedProduct]) -> tuple[Any, bool]:
        configured_id = os.getenv("STRIPE_PORTAL_CONFIG_ID")
        if configured_id:
            config = self.stripe.billing_portal.Configuration.retrieve(configured_id)
            return self._update_portal_configuration(config, products), False

        for config in _iter_collection(self.stripe.billing_portal.Configuration.list(limit=100)):
            metadata = _metadata(config)
            if metadata.get("managed_by") == MANAGED_BY and metadata.get("securewave_config") == "customer_portal":
                return self._update_portal_configuration(config, products), False

        config = self.stripe.billing_portal.Configuration.create(
            business_profile={
                "headline": "Manage your SecureWave subscription",
            },
            features=self._portal_features(products),
            metadata={
                "managed_by": MANAGED_BY,
                "securewave_config": "customer_portal",
            },
        )
        return config, True

    def _update_portal_configuration(self, config: Any, products: Dict[str, ProvisionedProduct]) -> Any:
        return self.stripe.billing_portal.Configuration.modify(
            _get(config, "id"),
            business_profile={
                "headline": "Manage your SecureWave subscription",
            },
            features=self._portal_features(products),
            metadata={
                "managed_by": MANAGED_BY,
                "securewave_config": "customer_portal",
            },
        )

    def _portal_features(self, products: Dict[str, ProvisionedProduct]) -> Dict[str, Any]:
        portal_products = []
        for product in products.values():
            portal_products.append({
                "product": product.product_id,
                "prices": [
                    product.prices["monthly"].price_id,
                    product.prices["yearly"].price_id,
                ],
            })

        return {
            "customer_update": {
                "enabled": True,
                "allowed_updates": ["email", "address", "phone"],
            },
            "invoice_history": {"enabled": True},
            "payment_method_update": {"enabled": True},
            "subscription_cancel": {
                "enabled": True,
                "mode": "at_period_end",
                "cancellation_reason": {
                    "enabled": True,
                    "options": ["too_expensive", "missing_features", "switched_service", "unused", "other"],
                },
            },
            "subscription_update": {
                "enabled": True,
                "default_allowed_updates": ["price"],
                "proration_behavior": "create_prorations",
                "products": portal_products,
            },
        }

    def write_env_file(self, result: StripeProvisioningResult) -> None:
        if not self.env_file:
            raise ValueError("env_file is required to write billing release env")

        self.env_file.parent.mkdir(parents=True, exist_ok=True)
        values = {
            "PAYMENTS_MOCK": "false",
            "DEMO_BILLING": "false",
            "PAYMENT_PROVIDER": "stripe",
            "STRIPE_SECRET_KEY": self.secret_key,
            "STRIPE_WEBHOOK_SECRET": result.webhook_secret or "",
            "STRIPE_PUBLISHABLE_KEY": self.publishable_key,
            "STRIPE_API_VERSION": LATEST_STRIPE_API_VERSION,
            **result.env_values,
        }
        values.setdefault("STRIPE_AUTOMATIC_TAX", "true" if _env_bool("STRIPE_AUTOMATIC_TAX", False) else "false")

        lines = ["# SecureWave billing release environment. Do not commit."]
        for key in [
            "PAYMENTS_MOCK",
            "DEMO_BILLING",
            "PAYMENT_PROVIDER",
            "STRIPE_SECRET_KEY",
            "STRIPE_WEBHOOK_SECRET",
            "STRIPE_PUBLISHABLE_KEY",
            "STRIPE_API_VERSION",
            "STRIPE_PRICE_BASIC_MONTHLY",
            "STRIPE_PRICE_BASIC_YEARLY",
            "STRIPE_PRICE_PREMIUM_MONTHLY",
            "STRIPE_PRICE_PREMIUM_YEARLY",
            "STRIPE_PRICE_ULTRA_MONTHLY",
            "STRIPE_PRICE_ULTRA_YEARLY",
            "STRIPE_PORTAL_CONFIG_ID",
            "STRIPE_AUTOMATIC_TAX",
        ]:
            lines.append(f"{key}={_shell_quote(values.get(key, ''))}")

        old_umask = os.umask(0o077)
        try:
            self.env_file.write_text("\n".join(lines) + "\n")
            self.env_file.chmod(0o600)
        finally:
            os.umask(old_umask)


def _shell_quote(value: str) -> str:
    return "'" + value.replace("'", "'\"'\"'") + "'"
