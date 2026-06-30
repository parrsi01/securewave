from types import SimpleNamespace

from fastapi import status

from models.subscription import Subscription
from services.payment_webhooks import PaymentWebhookHandler
from services.stripe_service import StripeService


def _stripe_env(monkeypatch):
    values = {
        "ENVIRONMENT": "production",
        "DEMO_MODE": "false",
        "DEMO_BILLING": "false",
        "PAYMENTS_MOCK": "false",
        "PAYMENT_PROVIDER": "stripe",
        "STRIPE_SECRET_KEY": "sk_live_test",
        "STRIPE_WEBHOOK_SECRET": "whsec_test",
        "STRIPE_PUBLISHABLE_KEY": "pk_live_test",
        "STRIPE_PORTAL_CONFIG_ID": "bpc_test",
        "STRIPE_PRICE_BASIC_MONTHLY": "price_basic_monthly",
        "STRIPE_PRICE_BASIC_YEARLY": "price_basic_yearly",
        "STRIPE_PRICE_PREMIUM_MONTHLY": "price_premium_monthly",
        "STRIPE_PRICE_PREMIUM_YEARLY": "price_premium_yearly",
        "STRIPE_PRICE_ULTRA_MONTHLY": "price_ultra_monthly",
        "STRIPE_PRICE_ULTRA_YEARLY": "price_ultra_yearly",
        "APP_URL": "https://securewave.app",
    }
    for key, value in values.items():
        monkeypatch.setenv(key, value)


def test_stripe_config_status_requires_prices(monkeypatch):
    monkeypatch.setenv("STRIPE_SECRET_KEY", "sk_live_test")
    monkeypatch.setenv("STRIPE_WEBHOOK_SECRET", "whsec_test")
    monkeypatch.setenv("STRIPE_PUBLISHABLE_KEY", "pk_live_test")
    monkeypatch.delenv("STRIPE_PRICE_BASIC_MONTHLY", raising=False)

    status_payload = StripeService.config_status()

    assert status_payload["enabled"] is False
    assert "STRIPE_PRICE_BASIC_MONTHLY" in status_payload["missing"]


def test_stripe_plan_details_read_current_env(monkeypatch):
    monkeypatch.setenv("STRIPE_PRICE_BASIC_MONTHLY", "price_current_basic")

    plan = StripeService.get_plan_details("basic")

    assert plan["stripe_price_id_monthly"] == "price_current_basic"


def test_stripe_price_lookup_reads_current_env(monkeypatch):
    monkeypatch.setenv("STRIPE_PRICE_PREMIUM_YEARLY", "price_current_premium_yearly")

    plan_id, billing_cycle, plan = StripeService.find_plan_by_price_id(
        "price_current_premium_yearly",
    )

    assert plan_id == "premium"
    assert billing_cycle == "yearly"
    assert plan["name"] == "Premium Plan"


def test_billing_health_blocks_without_production_stripe_config(client, monkeypatch):
    monkeypatch.setenv("ENVIRONMENT", "production")
    monkeypatch.setenv("DEMO_MODE", "false")
    monkeypatch.setenv("DEMO_BILLING", "false")
    monkeypatch.setenv("PAYMENTS_MOCK", "false")
    monkeypatch.delenv("STRIPE_SECRET_KEY", raising=False)
    monkeypatch.delenv("STRIPE_SECRET", raising=False)

    response = client.get("/api/billing/health")

    assert response.status_code == status.HTTP_503_SERVICE_UNAVAILABLE
    assert response.json()["status"] == "not_configured"
    assert response.json()["demo_billing"] is False


def test_subscription_create_does_not_demo_fallback_in_production(client, auth_headers, monkeypatch):
    monkeypatch.setenv("ENVIRONMENT", "production")
    monkeypatch.setenv("DEMO_MODE", "false")
    monkeypatch.setenv("DEMO_BILLING", "false")
    monkeypatch.setenv("PAYMENTS_MOCK", "false")
    monkeypatch.delenv("STRIPE_SECRET_KEY", raising=False)
    monkeypatch.delenv("STRIPE_SECRET", raising=False)

    response = client.post(
        "/api/billing/subscriptions",
        json={"plan_id": "basic", "billing_cycle": "monthly", "provider": "stripe"},
        headers=auth_headers,
    )

    assert response.status_code == status.HTTP_503_SERVICE_UNAVAILABLE
    assert "not configured" in response.text


def test_subscription_create_returns_checkout_session_in_production(
    client, auth_headers, monkeypatch
):
    import routes.billing as billing_routes

    _stripe_env(monkeypatch)

    def fake_checkout(self, **kwargs):
        return SimpleNamespace(id="cs_test_ready", url="https://checkout.stripe.com/c/pay")

    monkeypatch.setattr(
        billing_routes.SubscriptionManager,
        "create_stripe_checkout_session",
        fake_checkout,
    )

    response = client.post(
        "/api/billing/subscriptions",
        json={"plan_id": "basic", "billing_cycle": "monthly", "provider": "stripe"},
        headers=auth_headers,
    )

    assert response.status_code == status.HTTP_201_CREATED
    body = response.json()
    assert body["status"] == "checkout_required"
    assert body["checkout_url"].startswith("https://checkout.stripe.com/")
    assert body["session_id"] == "cs_test_ready"


def test_checkout_completed_webhook_creates_local_subscription(db, test_user, monkeypatch):
    _stripe_env(monkeypatch)
    handler = PaymentWebhookHandler(db)
    stripe_subscription = {
        "id": "sub_live_ready",
        "customer": "cus_live_ready",
        "status": "active",
        "current_period_start": 1_800_000_000,
        "current_period_end": 1_802_592_000,
        "cancel_at_period_end": False,
        "metadata": {
            "securewave_user_id": str(test_user.id),
            "plan_id": "basic",
            "billing_cycle": "monthly",
        },
        "items": {
            "data": [{
                "price": {"id": "price_basic_monthly"},
            }],
        },
    }
    monkeypatch.setattr(
        handler.stripe,
        "get_subscription",
        lambda subscription_id: stripe_subscription,
    )

    result = handler._stripe_checkout_completed({
        "mode": "subscription",
        "subscription": "sub_live_ready",
        "customer": "cus_live_ready",
        "client_reference_id": str(test_user.id),
        "metadata": {"securewave_user_id": str(test_user.id)},
    })

    assert result["status"] == "synced"
    subscription = db.query(Subscription).filter_by(
        stripe_subscription_id="sub_live_ready",
    ).first()
    assert subscription is not None
    assert subscription.user_id == test_user.id
    assert subscription.plan_id == "basic"
    assert subscription.billing_cycle == "monthly"
    assert subscription.status == "active"
    assert subscription.stripe_price_id == "price_basic_monthly"


def test_billing_portal_session_uses_configured_portal(monkeypatch):
    import services.stripe_service as stripe_module

    captured = {}
    monkeypatch.setenv("STRIPE_SECRET_KEY", "sk_live_test")
    monkeypatch.setenv("STRIPE_PORTAL_CONFIG_ID", "bpc_test")

    def fake_create(**kwargs):
        captured.update(kwargs)
        return SimpleNamespace(id="bps_test", url="https://billing.stripe.com/session")

    monkeypatch.setattr(stripe_module.stripe.billing_portal.Session, "create", fake_create)

    session = StripeService().create_billing_portal_session(
        customer_id="cus_test",
        return_url="https://securewaveapp.com/account",
    )

    assert session.id == "bps_test"
    assert captured["customer"] == "cus_test"
    assert captured["configuration"] == "bpc_test"
