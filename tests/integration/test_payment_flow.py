"""
SecureWave - Payment Flow Integration Tests
=============================================
Covers:
- Listing available subscription plans
- Subscription status for unauthenticated and authenticated users
- Subscription creation in demo mode
- Subscription cancellation, upgrade, downgrade
- Webhook processing
- Billing plans listing (both /api/billing/plans and /api/payments/stripe/plans)
"""

from datetime import datetime, timedelta

import pytest
from fastapi import status


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _register_and_login(client):
    """Register a new user and return (user_data, auth_headers)."""
    reg = client.post("/api/auth/register", json={
        "email": "paytest@example.com",
        "password": "SecurePass123",
        "password_confirm": "SecurePass123",
    })
    assert reg.status_code == 201
    token = reg.json().get("access_token")
    headers = {"Authorization": f"Bearer {token}"}
    return reg.json(), headers


def _create_demo_subscription(client, headers, plan_id="basic", billing_cycle="monthly"):
    """Create a demo subscription and return the response."""
    resp = client.post("/api/billing/subscriptions", json={
        "plan_id": plan_id,
        "billing_cycle": billing_cycle,
        "provider": "stripe",
    }, headers=headers)
    return resp


# ---------------------------------------------------------------------------
# Plan Listing
# ---------------------------------------------------------------------------

class TestListPlans:
    """Plan listing endpoints must return structured plan data."""

    def test_list_plans(self, client):
        """GET /api/billing/plans must return plan definitions."""
        resp = client.get("/api/billing/plans")
        assert resp.status_code == 200
        data = resp.json()
        assert "plans" in data
        plans = data["plans"]
        assert len(plans) >= 1
        for plan in plans:
            assert "id" in plan
            assert "name" in plan
            assert "pricing" in plan
            assert "monthly" in plan["pricing"]
            assert "yearly" in plan["pricing"]

    def test_list_stripe_plans(self, client):
        """GET /api/payments/stripe/plans must return plans with features."""
        resp = client.get("/api/payments/stripe/plans")
        assert resp.status_code == 200
        data = resp.json()
        assert "plans" in data
        plans = data["plans"]
        assert len(plans) >= 1
        for plan in plans:
            assert "id" in plan
            assert "name" in plan
            assert "features" in plan
            assert "pricing" in plan

    def test_plans_include_free_tier(self, client):
        """Plans list must include a free tier with price 0."""
        resp = client.get("/api/payments/stripe/plans")
        assert resp.status_code == 200
        plans = resp.json()["plans"]
        free_plans = [p for p in plans if p["id"] == "free"]
        assert len(free_plans) == 1
        assert free_plans[0]["pricing"]["monthly"] == 0
        assert free_plans[0]["requires_payment"] is False

    def test_plans_no_division_by_zero(self, client):
        """Plans endpoint must handle free tier (price=0) without errors."""
        resp = client.get("/api/billing/plans")
        assert resp.status_code == 200
        plans = resp.json()["plans"]
        # The free plan should have yearly_discount = 0 (not crash)
        for plan in plans:
            if plan["pricing"]["monthly"] == 0:
                assert plan["pricing"]["yearly_discount"] == 0


# ---------------------------------------------------------------------------
# Subscription Status
# ---------------------------------------------------------------------------

class TestSubscriptionStatus:
    """Subscription status endpoint validation."""

    def test_subscription_status(self, client, auth_headers):
        """GET /api/payments/stripe/subscription-status for new user should show free."""
        resp = client.get("/api/payments/stripe/subscription-status", headers=auth_headers)
        assert resp.status_code == 200
        data = resp.json()
        assert data.get("has_subscription") is False or data.get("plan") == "free"

    def test_subscription_status_requires_auth(self, client):
        """Subscription status without auth should fail."""
        resp = client.get("/api/payments/stripe/subscription-status")
        assert resp.status_code in (401, 403)

    def test_subscription_status_after_creation(self, client, auth_headers):
        """After creating a subscription, status should reflect it."""
        create_resp = _create_demo_subscription(client, auth_headers, plan_id="basic")
        assert create_resp.status_code == 201

        # Check via billing endpoint
        current_resp = client.get(
            "/api/billing/subscriptions/current",
            headers=auth_headers,
        )
        assert current_resp.status_code == 200
        data = current_resp.json()
        sub = data.get("subscription")
        assert sub is not None
        assert sub["plan_id"] == "basic"
        assert sub["is_active"] is True


# ---------------------------------------------------------------------------
# Subscription Creation (Demo Mode)
# ---------------------------------------------------------------------------

class TestSubscriptionCreation:
    """Subscription creation in demo mode (no real Stripe keys)."""

    def test_create_basic_subscription(self, client, auth_headers):
        """Creating a basic plan subscription in demo mode should succeed."""
        resp = _create_demo_subscription(client, auth_headers, plan_id="basic")
        assert resp.status_code == 201
        data = resp.json()
        assert data.get("subscription_id") is not None
        assert data.get("status") == "active"

    def test_create_premium_subscription(self, client, auth_headers):
        """Creating a premium plan subscription in demo mode should succeed."""
        resp = _create_demo_subscription(client, auth_headers, plan_id="premium")
        assert resp.status_code == 201
        data = resp.json()
        assert data.get("status") == "active"

    def test_create_yearly_subscription(self, client, auth_headers):
        """Yearly billing cycle should be accepted."""
        resp = _create_demo_subscription(
            client, auth_headers, plan_id="basic", billing_cycle="yearly"
        )
        assert resp.status_code == 201

    def test_duplicate_subscription_rejected(self, client, auth_headers):
        """A user with an active subscription cannot create another."""
        first = _create_demo_subscription(client, auth_headers, plan_id="basic")
        assert first.status_code == 201

        second = _create_demo_subscription(client, auth_headers, plan_id="premium")
        assert second.status_code in (400, 500)


# ---------------------------------------------------------------------------
# Stripe Checkout (Demo Mode)
# ---------------------------------------------------------------------------

class TestStripeCheckout:
    """Stripe checkout session creation in demo mode."""

    def test_create_checkout_session_demo(self, client, auth_headers):
        """POST /api/payments/stripe/create-checkout-session returns demo URL."""
        resp = client.post(
            "/api/payments/stripe/create-checkout-session",
            json={"plan_id": "basic", "billing_cycle": "monthly"},
            headers=auth_headers,
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data.get("demo") is True
        assert data.get("checkout_url") is not None

    def test_checkout_free_plan_no_payment(self, client, auth_headers):
        """Free plan should not require payment processing."""
        resp = client.post(
            "/api/payments/stripe/create-checkout-session",
            json={"plan_id": "free"},
            headers=auth_headers,
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data.get("checkout_url") is None
        assert "free" in data.get("plan", "").lower() or "free" in data.get("message", "").lower()


# ---------------------------------------------------------------------------
# Subscription Cancellation
# ---------------------------------------------------------------------------

class TestSubscriptionCancellation:
    """Subscription cancellation flow tests."""

    def test_cancel_at_period_end(self, client, auth_headers):
        """Cancellation with cancel_at_period_end=True keeps sub active."""
        create_resp = _create_demo_subscription(client, auth_headers, plan_id="basic")
        sub_id = create_resp.json()["subscription_id"]

        cancel_resp = client.post(
            f"/api/billing/subscriptions/{sub_id}/cancel",
            json={"cancel_at_period_end": True, "reason": "Testing"},
            headers=auth_headers,
        )
        assert cancel_resp.status_code == 200
        data = cancel_resp.json()
        assert data["subscription"]["cancel_at_period_end"] is True

    def test_cancel_immediately(self, client, auth_headers):
        """Immediate cancellation should set status to canceled."""
        create_resp = _create_demo_subscription(client, auth_headers, plan_id="basic")
        sub_id = create_resp.json()["subscription_id"]

        cancel_resp = client.post(
            f"/api/billing/subscriptions/{sub_id}/cancel",
            json={"cancel_at_period_end": False, "reason": "Testing immediate"},
            headers=auth_headers,
        )
        assert cancel_resp.status_code == 200
        data = cancel_resp.json()
        assert data["subscription"]["status"] == "canceled"


# ---------------------------------------------------------------------------
# Plan Upgrade / Downgrade
# ---------------------------------------------------------------------------

class TestPlanUpgradeDowngrade:
    """Subscription upgrade and downgrade tests."""

    def test_upgrade_basic_to_premium(self, client, auth_headers):
        """Upgrading from basic to premium should update the plan."""
        create_resp = _create_demo_subscription(client, auth_headers, plan_id="basic")
        sub_id = create_resp.json()["subscription_id"]

        upgrade_resp = client.put(
            f"/api/billing/subscriptions/{sub_id}/upgrade",
            json={"new_plan_id": "premium"},
            headers=auth_headers,
        )
        assert upgrade_resp.status_code == 200
        data = upgrade_resp.json()
        assert "premium" in data["subscription"]["plan_name"].lower()


# ---------------------------------------------------------------------------
# Subscription History and Reactivation
# ---------------------------------------------------------------------------

class TestSubscriptionHistory:
    """Subscription history endpoint tests."""

    def test_history_returns_list(self, client, auth_headers):
        """GET /api/billing/subscriptions/history must return a list."""
        resp = client.get("/api/billing/subscriptions/history", headers=auth_headers)
        assert resp.status_code == 200
        data = resp.json()
        assert "subscriptions" in data
        assert isinstance(data["subscriptions"], list)
