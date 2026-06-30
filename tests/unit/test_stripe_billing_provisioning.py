from pathlib import Path
from types import SimpleNamespace

import pytest

from services.stripe_provisioning import (
    WEBHOOK_EVENTS,
    StripeBillingProvisioner,
)


class ListResponse:
    def __init__(self, data):
        self.data = data


class FakeProducts:
    def __init__(self):
        self.items = []

    def list(self, **kwargs):
        return ListResponse(self.items)

    def create(self, **kwargs):
        product = SimpleNamespace(id=f"prod_{len(self.items) + 1}", **kwargs)
        self.items.append(product)
        return product


class FakePrices:
    def __init__(self):
        self.items = []

    def list(self, **kwargs):
        prices = self.items
        lookup_keys = kwargs.get("lookup_keys")
        product = kwargs.get("product")
        if lookup_keys:
            prices = [price for price in prices if price.lookup_key in lookup_keys]
        if product:
            prices = [price for price in prices if price.product == product]
        return ListResponse(prices[: kwargs.get("limit", 100)])

    def create(self, **kwargs):
        price = SimpleNamespace(id=f"price_{len(self.items) + 1}", **kwargs)
        self.items.append(price)
        return price


class FakeWebhookEndpoints:
    def __init__(self):
        self.items = []

    def list(self, **kwargs):
        return ListResponse(self.items)

    def create(self, **kwargs):
        endpoint = SimpleNamespace(id=f"we_{len(self.items) + 1}", secret="whsec_generated", **kwargs)
        self.items.append(endpoint)
        return endpoint

    def modify(self, endpoint_id, **kwargs):
        for endpoint in self.items:
            if endpoint.id == endpoint_id:
                for key, value in kwargs.items():
                    setattr(endpoint, key, value)
                return endpoint
        raise AssertionError(f"unknown endpoint {endpoint_id}")


class FakePortalConfigurations:
    def __init__(self):
        self.items = []

    def list(self, **kwargs):
        return ListResponse(self.items)

    def create(self, **kwargs):
        config = SimpleNamespace(id=f"bpc_{len(self.items) + 1}", **kwargs)
        self.items.append(config)
        return config

    def retrieve(self, config_id):
        for config in self.items:
            if config.id == config_id:
                return config
        raise AssertionError(f"unknown portal config {config_id}")

    def modify(self, config_id, **kwargs):
        config = self.retrieve(config_id)
        for key, value in kwargs.items():
            setattr(config, key, value)
        return config


class FakeStripe:
    def __init__(self):
        self.api_key = None
        self.api_version = None
        self.Product = FakeProducts()
        self.Price = FakePrices()
        self.WebhookEndpoint = FakeWebhookEndpoints()
        self.billing_portal = SimpleNamespace(Configuration=FakePortalConfigurations())


def test_stripe_billing_provisioner_creates_resources_and_private_env(tmp_path: Path):
    fake_stripe = FakeStripe()
    env_file = tmp_path / "billing_release.env"

    provisioner = StripeBillingProvisioner(
        app_url="https://securewaveapp.com",
        secret_key="sk_live_unit",
        publishable_key="pk_live_unit",
        env_file=env_file,
        stripe_client=fake_stripe,
    )

    result = provisioner.provision()

    assert result.blockers == []
    assert len(result.products) == 3
    assert len(fake_stripe.Product.items) == 3
    assert len(fake_stripe.Price.items) == 6
    assert result.webhook_secret == "whsec_generated"
    assert result.portal_config_id.startswith("bpc_")
    assert "checkout.session.completed" in fake_stripe.WebhookEndpoint.items[0].enabled_events
    assert sorted(fake_stripe.WebhookEndpoint.items[0].enabled_events) == sorted(WEBHOOK_EVENTS)

    env_text = env_file.read_text()
    assert "STRIPE_SECRET_KEY='sk_live_unit'" in env_text
    assert "STRIPE_WEBHOOK_SECRET='whsec_generated'" in env_text
    assert "STRIPE_PRICE_BASIC_MONTHLY='price_" in env_text
    assert "STRIPE_PORTAL_CONFIG_ID='bpc_" in env_text
    assert oct(env_file.stat().st_mode & 0o777) == "0o600"


def test_stripe_billing_provisioner_reuses_existing_webhook_but_reports_secret_blocker(tmp_path: Path):
    fake_stripe = FakeStripe()
    fake_stripe.WebhookEndpoint.items.append(
        SimpleNamespace(
            id="we_existing",
            url="https://securewaveapp.com/api/billing/webhooks/stripe",
            enabled_events=["invoice.paid"],
            metadata={},
        )
    )

    provisioner = StripeBillingProvisioner(
        app_url="https://securewaveapp.com",
        secret_key="sk_live_unit",
        publishable_key="pk_live_unit",
        env_file=tmp_path / "billing_release.env",
        stripe_client=fake_stripe,
    )

    result = provisioner.provision()

    assert result.webhook_endpoint_id == "we_existing"
    assert result.webhook_created is False
    assert result.webhook_secret is None
    assert result.blockers == [
        "STRIPE_WEBHOOK_SECRET cannot be read for an existing Stripe webhook endpoint; copy it from the Stripe Dashboard or create a new endpoint."
    ]
    assert sorted(fake_stripe.WebhookEndpoint.items[0].enabled_events) == sorted(WEBHOOK_EVENTS)


def test_stripe_billing_provisioner_requires_live_keys_by_default():
    provisioner = StripeBillingProvisioner(
        app_url="https://securewaveapp.com",
        secret_key="sk_test_unit",
        publishable_key="pk_test_unit",
    )

    with pytest.raises(ValueError, match="live-mode key"):
        provisioner.validate()
