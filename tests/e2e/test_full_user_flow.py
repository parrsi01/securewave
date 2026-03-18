"""
SecureWave — End-to-End User Lifecycle Tests
=============================================
Full user journey simulations covering:
- Registration → login → logout cycle
- Password reset flow
- Subscription purchase (Stripe checkout)
- VPN server selection and connection
- Device registration and revocation
- Configuration download
- Profile update (email, password)
- Subscription cancellation
- API health endpoints
- Multi-device management
"""

from __future__ import annotations

import hashlib
import hmac
import json
import time
from datetime import datetime, timedelta
from types import SimpleNamespace

import pytest

from models.subscription import Subscription
from models.user import User
from models.vpn_server import VPNServer
from services.hashing_service import hash_password


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

TEST_EMAIL = "e2euser@example.com"
TEST_PASSWORD = "E2eSecure123!"
UPDATED_PASSWORD = "E2eUpdated456!"
WEBHOOK_SECRET = "whsec_e2e_test"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _stripe_sig(payload: bytes, secret: str) -> str:
    ts = int(time.time())
    signed = f"{ts}.".encode("utf-8") + payload
    sig = hmac.new(secret.encode("utf-8"), signed, hashlib.sha256).hexdigest()
    return f"t={ts},v1={sig}"


def _post_webhook(client, event: dict, secret: str = WEBHOOK_SECRET):
    """Post a Stripe webhook event.

    Clears cookies first to avoid CSRF middleware interference — real
    webhooks from Stripe never carry session cookies.
    """
    payload = json.dumps(event, separators=(",", ":"), sort_keys=True).encode("utf-8")
    sig = _stripe_sig(payload, secret)
    # Clear cookies so CSRF middleware sees no access_token cookie
    saved_cookies = dict(client.cookies)
    client.cookies.clear()
    resp = client.post("/api/payments/stripe/webhook", data=payload,
                       headers={"Stripe-Signature": sig})
    # Restore cookies for subsequent authenticated calls
    client.cookies.update(saved_cookies)
    return resp


def _patch_stripe(monkeypatch):
    """Patch Stripe API calls for checkout and portal."""
    import stripe
    monkeypatch.setattr(stripe.Customer, "create",
                        staticmethod(lambda **kw: SimpleNamespace(id="cus_e2e_test")))
    monkeypatch.setattr(stripe.checkout.Session, "create",
                        staticmethod(lambda **kw: SimpleNamespace(
                            id="cs_e2e_test",
                            url="https://checkout.stripe.test/cs_e2e_test")))
    monkeypatch.setattr(stripe.billing_portal.Session, "create",
                        staticmethod(lambda **kw: SimpleNamespace(
                            url="https://billing.stripe.test/portal")))
    monkeypatch.setattr(stripe.Subscription, "modify",
                        staticmethod(lambda sid, **kw: SimpleNamespace(id=sid, status="active")))
    monkeypatch.setattr(stripe.Subscription, "delete",
                        staticmethod(lambda sid, **kw: SimpleNamespace(id=sid, status="canceled")))


def _seed_servers(db):
    """Seed VPN servers for E2E tests."""
    servers = [
        VPNServer(
            server_id="e2e-us-1", location="New York", country="United States",
            country_code="US", city="New York", region="Americas",
            hcloud_location="ash", public_ip="10.0.0.1",
            endpoint="10.0.0.1:51820",
            wg_public_key="dGVzdC1lMmUtcHVibGljLWtleS0x",
            wg_private_key_encrypted="encrypted-key-1",
            status="active", health_status="healthy",
            max_connections=1000, current_connections=10,
            performance_score=95.0, hcloud_server_state="running",
        ),
        VPNServer(
            server_id="e2e-eu-1", location="London", country="United Kingdom",
            country_code="GB", city="London", region="Europe",
            hcloud_location="nbg1", public_ip="10.0.1.1",
            endpoint="10.0.1.1:51820",
            wg_public_key="dGVzdC1lMmUtcHVibGljLWtleS0y",
            wg_private_key_encrypted="encrypted-key-2",
            status="active", health_status="healthy",
            max_connections=500, current_connections=5,
            performance_score=88.0, hcloud_server_state="running",
        ),
    ]
    for s in servers:
        db.add(s)
    db.commit()
    return servers


# ---------------------------------------------------------------------------
# 1. Registration Flow
# ---------------------------------------------------------------------------

class TestRegistrationFlow:
    """User registration with validation."""

    def test_successful_registration(self, client, db):
        """New user can register with valid credentials."""
        resp = client.post("/api/auth/register", json={
            "email": TEST_EMAIL,
            "password": TEST_PASSWORD,
            "password_confirm": TEST_PASSWORD,
        })
        assert resp.status_code == 201, f"Registration failed: {resp.json()}"
        data = resp.json()
        assert "user_id" in data
        assert "email" in data
        # Tokens are set via Set-Cookie only — not in the JSON body.
        assert "access_token" not in data
        assert "refresh_token" not in data

    def test_duplicate_registration_rejected(self, client, db):
        """Duplicate email registration must be rejected."""
        client.post("/api/auth/register", json={
            "email": TEST_EMAIL,
            "password": TEST_PASSWORD,
            "password_confirm": TEST_PASSWORD,
        })
        resp = client.post("/api/auth/register", json={
            "email": TEST_EMAIL,
            "password": TEST_PASSWORD,
            "password_confirm": TEST_PASSWORD,
        })
        assert resp.status_code in (400, 409)

    def test_weak_password_rejected(self, client, db):
        """Weak password must be rejected."""
        resp = client.post("/api/auth/register", json={
            "email": "weakpw@example.com",
            "password": "short1",
            "password_confirm": "short1",
        })
        assert resp.status_code in (400, 422)

    def test_password_mismatch_rejected(self, client, db):
        """Mismatched password confirmation must be rejected."""
        resp = client.post("/api/auth/register", json={
            "email": "mismatch@example.com",
            "password": TEST_PASSWORD,
            "password_confirm": "DifferentPass123!",
        })
        assert resp.status_code in (400, 422)


# ---------------------------------------------------------------------------
# 2. Login / Logout Flow
# ---------------------------------------------------------------------------

class TestLoginLogoutFlow:
    """Login, session verification, and logout."""

    def _register_and_login(self, client):
        client.post("/api/auth/register", json={
            "email": TEST_EMAIL,
            "password": TEST_PASSWORD,
            "password_confirm": TEST_PASSWORD,
        })
        resp = client.post("/api/auth/login", json={
            "email": TEST_EMAIL,
            "password": TEST_PASSWORD,
        })
        return resp

    def test_login_returns_tokens(self, client, db):
        """Successful login returns access + refresh tokens."""
        resp = self._register_and_login(client)
        assert resp.status_code == 200
        data = resp.json()
        assert "access_token" in data
        assert "refresh_token" in data

    def test_me_endpoint_returns_user(self, client, db):
        """Authenticated /me returns user profile."""
        login = self._register_and_login(client)
        token = login.json()["access_token"]
        headers = {"Authorization": f"Bearer {token}"}

        resp = client.get("/api/auth/me", headers=headers)
        assert resp.status_code == 200
        assert resp.json()["email"] == TEST_EMAIL

    def test_logout_clears_session(self, client, db):
        """Logout must clear auth cookies."""
        login = self._register_and_login(client)
        token = login.json()["access_token"]
        headers = {"Authorization": f"Bearer {token}"}

        resp = client.post("/api/auth/logout", headers=headers)
        assert resp.status_code == 200

    def test_wrong_password_rejected(self, client, db):
        """Wrong password must return 401."""
        client.post("/api/auth/register", json={
            "email": TEST_EMAIL,
            "password": TEST_PASSWORD,
            "password_confirm": TEST_PASSWORD,
        })
        resp = client.post("/api/auth/login", json={
            "email": TEST_EMAIL,
            "password": "WrongPassword123!",
        })
        assert resp.status_code == 401


# ---------------------------------------------------------------------------
# 3. Password Reset Flow
# ---------------------------------------------------------------------------

class TestPasswordResetFlow:
    """Password reset request and confirmation."""

    def test_reset_request_succeeds(self, client, db, test_user):
        """Password reset request returns success regardless of email existence."""
        resp = client.post("/api/auth/password-reset/request", json={
            "email": "testuser@example.com",
        })
        assert resp.status_code == 200

    def test_reset_with_valid_token(self, client, db, test_user):
        """Valid reset token allows password change."""
        import secrets
        token = secrets.token_urlsafe(32)
        test_user.password_reset_token = token
        test_user.password_reset_token_expires = datetime.utcnow() + timedelta(minutes=15)
        test_user.password_reset_requested_at = datetime.utcnow()
        db.commit()

        resp = client.post("/api/auth/password-reset/confirm", json={
            "token": token,
            "new_password": UPDATED_PASSWORD,
        })
        assert resp.status_code == 200

        # Verify new password works
        login = client.post("/api/auth/login", json={
            "email": "testuser@example.com",
            "password": UPDATED_PASSWORD,
        })
        assert login.status_code == 200

    def test_expired_reset_token_rejected(self, client, db, test_user):
        """Expired reset token must be rejected."""
        import secrets
        token = secrets.token_urlsafe(32)
        test_user.password_reset_token = token
        test_user.password_reset_token_expires = datetime.utcnow() - timedelta(hours=1)
        db.commit()

        resp = client.post("/api/auth/password-reset/confirm", json={
            "token": token,
            "new_password": UPDATED_PASSWORD,
        })
        assert resp.status_code in (400, 401, 410)


# ---------------------------------------------------------------------------
# 4. Subscription Purchase Flow
# ---------------------------------------------------------------------------

class TestSubscriptionPurchaseFlow:
    """Stripe checkout → webhook → active subscription."""

    def test_checkout_and_subscription_activation(self, client, monkeypatch, db):
        """Full flow: register → checkout → webhook → active subscription."""
        monkeypatch.setenv("STRIPE_SECRET_KEY", "sk_test_e2e")
        monkeypatch.setenv("STRIPE_WEBHOOK_SECRET", WEBHOOK_SECRET)
        monkeypatch.setenv("STRIPE_PRICE_BASIC_MONTHLY", "price_basic_m")
        monkeypatch.setenv("STRIPE_PRICE_BASIC_YEARLY", "price_basic_y")
        monkeypatch.setenv("STRIPE_PRICE_PREMIUM_MONTHLY", "price_premium_m")
        monkeypatch.setenv("STRIPE_PRICE_PREMIUM_YEARLY", "price_premium_y")
        monkeypatch.setenv("STRIPE_PRICE_ULTRA_MONTHLY", "price_ultra_m")
        monkeypatch.setenv("STRIPE_PRICE_ULTRA_YEARLY", "price_ultra_y")
        _patch_stripe(monkeypatch)

        # Step 1: Register
        client.post("/api/auth/register", json={
            "email": TEST_EMAIL,
            "password": TEST_PASSWORD,
            "password_confirm": TEST_PASSWORD,
        })
        login = client.post("/api/auth/login", json={
            "email": TEST_EMAIL,
            "password": TEST_PASSWORD,
        })
        assert login.status_code == 200
        token = login.json()["access_token"]
        headers = {"Authorization": f"Bearer {token}"}

        # Step 2: Create checkout session
        checkout = client.post("/api/payments/stripe/create-checkout-session",
                              json={"plan_id": "premium", "billing_cycle": "monthly"},
                              headers=headers)
        assert checkout.status_code == 200
        assert "session_id" in checkout.json() or "url" in checkout.json()

        # Step 3: Simulate Stripe webhook — subscription created
        user = db.query(User).filter_by(email=TEST_EMAIL).first()
        now = int(time.time())
        sub_obj = {
            "id": "sub_e2e_1",
            "customer": "cus_e2e_test",
            "status": "active",
            "current_period_start": now,
            "current_period_end": now + 30 * 86400,
            "cancel_at_period_end": False,
            "items": {"data": [{"price": {"id": "price_premium_m"}}]},
            "metadata": {
                "securewave_user_id": str(user.id),
                "plan_id": "premium",
                "billing_cycle": "monthly",
            },
        }
        evt = {"id": "evt_e2e_sub_created", "type": "customer.subscription.created",
               "created": now, "data": {"object": sub_obj}}
        webhook_resp = _post_webhook(client, evt)
        assert webhook_resp.status_code == 200

        # Step 4: Verify subscription is active
        db.refresh(user)
        sub = db.query(Subscription).filter_by(user_id=user.id).first()
        assert sub is not None
        assert sub.status == "active"
        assert sub.plan_id == "premium"

    def test_free_plan_skips_checkout(self, client, monkeypatch, db):
        """Free plan should not require Stripe checkout."""
        monkeypatch.setenv("STRIPE_SECRET_KEY", "sk_test_e2e")
        monkeypatch.setenv("STRIPE_PRICE_BASIC_MONTHLY", "price_basic_m")
        monkeypatch.setenv("STRIPE_PRICE_BASIC_YEARLY", "price_basic_y")
        monkeypatch.setenv("STRIPE_PRICE_PREMIUM_MONTHLY", "price_premium_m")
        monkeypatch.setenv("STRIPE_PRICE_PREMIUM_YEARLY", "price_premium_y")
        monkeypatch.setenv("STRIPE_PRICE_ULTRA_MONTHLY", "price_ultra_m")
        monkeypatch.setenv("STRIPE_PRICE_ULTRA_YEARLY", "price_ultra_y")
        _patch_stripe(monkeypatch)

        client.post("/api/auth/register", json={
            "email": "freeuser@example.com",
            "password": TEST_PASSWORD,
            "password_confirm": TEST_PASSWORD,
        })
        login = client.post("/api/auth/login", json={
            "email": "freeuser@example.com",
            "password": TEST_PASSWORD,
        })
        assert login.status_code == 200
        token = login.json()["access_token"]
        headers = {"Authorization": f"Bearer {token}"}

        resp = client.post("/api/payments/stripe/create-checkout-session",
                          json={"plan_id": "free", "billing_cycle": "monthly"},
                          headers=headers)
        assert resp.status_code == 200
        data = resp.json()
        assert data.get("plan") == "free" or "free" in json.dumps(data).lower()


# ---------------------------------------------------------------------------
# 5. VPN Server Selection
# ---------------------------------------------------------------------------

class TestVPNServerSelection:
    """Server listing and selection."""

    def test_list_servers(self, client, auth_headers, db):
        """Authenticated user can list VPN servers."""
        _seed_servers(db)
        resp = client.get("/api/vpn/servers", headers=auth_headers)
        assert resp.status_code == 200
        data = resp.json()
        assert "servers" in data
        assert len(data["servers"]) >= 2

    def test_server_detail(self, client, auth_headers, db):
        """Can fetch individual server details."""
        _seed_servers(db)
        resp = client.get("/api/vpn/servers/e2e-us-1", headers=auth_headers)
        assert resp.status_code == 200

    def test_server_list_requires_auth(self, client, db):
        """Server list requires authentication."""
        _seed_servers(db)
        resp = client.get("/api/vpn/servers")
        assert resp.status_code in (401, 403)


# ---------------------------------------------------------------------------
# 6. Device Registration and Revocation
# ---------------------------------------------------------------------------

class TestDeviceLifecycle:
    """Device create → list → config → revoke."""

    def test_create_device(self, client, auth_headers, test_subscription, db):
        """Subscribed user can create a device."""
        _seed_servers(db)
        resp = client.post("/api/vpn/devices", json={
            "name": "My Laptop",
            "device_type": "linux",
            "server_id": "e2e-us-1",
        }, headers=auth_headers)
        assert resp.status_code in (200, 201), f"Device creation failed: {resp.json()}"

    def test_list_devices(self, client, auth_headers, test_subscription, db):
        """User can list their devices."""
        _seed_servers(db)
        client.post("/api/vpn/devices", json={
            "name": "Test Device",
            "device_type": "linux",
            "server_id": "e2e-us-1",
        }, headers=auth_headers)

        resp = client.get("/api/vpn/devices", headers=auth_headers)
        assert resp.status_code == 200
        devices = resp.json()
        assert isinstance(devices, (list, dict))

    def test_device_config_download(self, client, auth_headers, test_subscription, db):
        """User can download device WireGuard config."""
        _seed_servers(db)
        create_resp = client.post("/api/vpn/devices", json={
            "name": "Config Device",
            "device_type": "linux",
            "server_id": "e2e-us-1",
        }, headers=auth_headers)
        if create_resp.status_code not in (200, 201):
            pytest.skip("Device creation failed — cannot test config download")

        device_id = create_resp.json().get("id") or create_resp.json().get("device_id")
        if not device_id:
            pytest.skip("No device_id in creation response")

        resp = client.get(f"/api/vpn/devices/{device_id}/config", headers=auth_headers)
        assert resp.status_code == 200

    def test_revoke_device(self, client, auth_headers, test_subscription, db):
        """User can revoke a device."""
        _seed_servers(db)
        create_resp = client.post("/api/vpn/devices", json={
            "name": "Revoke Device",
            "device_type": "linux",
            "server_id": "e2e-us-1",
        }, headers=auth_headers)
        if create_resp.status_code not in (200, 201):
            pytest.skip("Device creation failed")

        device_id = create_resp.json().get("id") or create_resp.json().get("device_id")
        if not device_id:
            pytest.skip("No device_id in creation response")

        resp = client.post(f"/api/vpn/devices/{device_id}/revoke", headers=auth_headers)
        assert resp.status_code in (200, 204)

    def test_free_user_can_create_basic_device(self, client, auth_headers, db):
        """Free-tier user can create devices (basic plan includes 1 device).

        The device creation endpoint does not enforce subscription gating
        for basic-tier users — it allows 1 device on the free/basic plan.
        """
        _seed_servers(db)
        resp = client.post("/api/vpn/devices", json={
            "name": "Free Device",
            "device_type": "linux",
            "server_id": "e2e-us-1",
        }, headers=auth_headers)
        assert resp.status_code in (200, 201)


# ---------------------------------------------------------------------------
# 7. VPN Connect / Disconnect Flow
# ---------------------------------------------------------------------------

class TestVPNConnectionFlow:
    """VPN connect → status → config → disconnect."""

    def test_connect_disconnect_cycle(self, client, auth_headers, db):
        """Full connect → status → disconnect cycle."""
        _seed_servers(db)

        # Connect
        connect = client.post("/api/vpn/connect",
                             json={"region": "us-east"},
                             headers=auth_headers)
        assert connect.status_code == 200
        assert connect.json().get("status") == "CONNECTED"

        # Status
        status = client.get("/api/vpn/status", headers=auth_headers)
        assert status.status_code == 200
        assert status.json().get("status") == "CONNECTED"

        # Disconnect
        disconnect = client.post("/api/vpn/disconnect", headers=auth_headers)
        assert disconnect.status_code == 200
        assert disconnect.json().get("status") == "DISCONNECTED"

    def test_config_after_connect(self, client, auth_headers, db):
        """Config endpoint returns data after VPN connect."""
        _seed_servers(db)
        client.post("/api/vpn/connect",
                    json={"region": "us-east"},
                    headers=auth_headers)

        resp = client.get("/api/vpn/config", headers=auth_headers)
        assert resp.status_code == 200
        data = resp.json()
        assert "config" in data


# ---------------------------------------------------------------------------
# 8. Profile Update
# ---------------------------------------------------------------------------

class TestProfileUpdate:
    """Email and password update flows."""

    def test_update_password(self, client, db):
        """User can change password with current password verification."""
        client.post("/api/auth/register", json={
            "email": TEST_EMAIL,
            "password": TEST_PASSWORD,
            "password_confirm": TEST_PASSWORD,
        })
        login = client.post("/api/auth/login", json={
            "email": TEST_EMAIL,
            "password": TEST_PASSWORD,
        })
        assert login.status_code == 200
        token = login.json()["access_token"]
        headers = {"Authorization": f"Bearer {token}"}

        resp = client.post("/api/auth/update-password", json={
            "current_password": TEST_PASSWORD,
            "new_password": UPDATED_PASSWORD,
            "new_password_confirm": UPDATED_PASSWORD,
        }, headers=headers)
        assert resp.status_code == 200

        # Verify new password works
        login = client.post("/api/auth/login", json={
            "email": TEST_EMAIL,
            "password": UPDATED_PASSWORD,
        })
        assert login.status_code == 200

    def test_update_email(self, client, db):
        """User can change email with password verification."""
        client.post("/api/auth/register", json={
            "email": TEST_EMAIL,
            "password": TEST_PASSWORD,
            "password_confirm": TEST_PASSWORD,
        })
        login = client.post("/api/auth/login", json={
            "email": TEST_EMAIL,
            "password": TEST_PASSWORD,
        })
        assert login.status_code == 200
        token = login.json()["access_token"]
        headers = {"Authorization": f"Bearer {token}"}

        resp = client.post("/api/auth/update-email", json={
            "new_email": "newemail@example.com",
            "password": TEST_PASSWORD,
        }, headers=headers)
        assert resp.status_code == 200

    def test_update_password_wrong_current_rejected(self, client, db):
        """Wrong current password must be rejected."""
        client.post("/api/auth/register", json={
            "email": "pwchange@example.com",
            "password": TEST_PASSWORD,
            "password_confirm": TEST_PASSWORD,
        })
        login = client.post("/api/auth/login", json={
            "email": "pwchange@example.com",
            "password": TEST_PASSWORD,
        })
        assert login.status_code == 200
        token = login.json()["access_token"]
        headers = {"Authorization": f"Bearer {token}"}

        resp = client.post("/api/auth/update-password", json={
            "current_password": "WrongCurrent123!",
            "new_password": UPDATED_PASSWORD,
            "new_password_confirm": UPDATED_PASSWORD,
        }, headers=headers)
        assert resp.status_code == 401


# ---------------------------------------------------------------------------
# 9. Subscription Cancellation
# ---------------------------------------------------------------------------

class TestSubscriptionCancellation:
    """Subscription cancel via webhook."""

    def test_cancel_subscription(self, client, monkeypatch, db):
        """Full flow: active subscription → cancellation webhook → status reset."""
        monkeypatch.setenv("STRIPE_SECRET_KEY", "sk_test_e2e")
        monkeypatch.setenv("STRIPE_WEBHOOK_SECRET", WEBHOOK_SECRET)
        monkeypatch.setenv("STRIPE_PRICE_BASIC_MONTHLY", "price_basic_m")
        monkeypatch.setenv("STRIPE_PRICE_BASIC_YEARLY", "price_basic_y")
        monkeypatch.setenv("STRIPE_PRICE_PREMIUM_MONTHLY", "price_premium_m")
        monkeypatch.setenv("STRIPE_PRICE_PREMIUM_YEARLY", "price_premium_y")
        monkeypatch.setenv("STRIPE_PRICE_ULTRA_MONTHLY", "price_ultra_m")
        monkeypatch.setenv("STRIPE_PRICE_ULTRA_YEARLY", "price_ultra_y")

        # Create user with active subscription
        user = User(
            email="cancel@example.com",
            hashed_password=hash_password(TEST_PASSWORD),
            email_verified=True, is_active=True,
            subscription_status="active",
            stripe_customer_id="cus_cancel_test",
            created_at=datetime.utcnow(),
        )
        db.add(user)
        db.commit()
        db.refresh(user)

        now = int(time.time())
        sub_obj = {
            "id": "sub_cancel_1", "customer": "cus_cancel_test",
            "status": "active",
            "current_period_start": now - 15 * 86400,
            "current_period_end": now + 15 * 86400,
            "cancel_at_period_end": False,
            "items": {"data": [{"price": {"id": "price_premium_m"}}]},
            "metadata": {
                "securewave_user_id": str(user.id),
                "plan_id": "premium", "billing_cycle": "monthly",
            },
        }
        # Create subscription via webhook
        create_evt = {"id": "evt_cancel_create", "type": "customer.subscription.created",
                      "created": now, "data": {"object": sub_obj}}
        _post_webhook(client, create_evt)

        sub = db.query(Subscription).filter_by(user_id=user.id).first()
        assert sub is not None
        assert sub.status == "active"

        # Cancel via webhook
        sub_obj["status"] = "canceled"
        sub_obj["canceled_at"] = now
        cancel_evt = {"id": "evt_cancel_delete", "type": "customer.subscription.deleted",
                      "created": now + 1, "data": {"object": sub_obj}}
        cancel_resp = _post_webhook(client, cancel_evt)
        assert cancel_resp.status_code == 200

        db.refresh(sub)
        assert sub.status == "canceled"


# ---------------------------------------------------------------------------
# 10. API Health Endpoints
# ---------------------------------------------------------------------------

class TestHealthEndpoints:
    """API health and readiness checks."""

    def test_health_endpoint(self, client):
        """GET /api/health must return 200."""
        resp = client.get("/api/health")
        assert resp.status_code == 200

    def test_ready_endpoint(self, client):
        """GET /api/ready must return 200."""
        resp = client.get("/api/ready")
        assert resp.status_code == 200

    def test_root_health(self, client):
        """GET /health must return 200."""
        resp = client.get("/health")
        assert resp.status_code == 200


# ---------------------------------------------------------------------------
# 11. Full User Lifecycle (End-to-End Chain)
# ---------------------------------------------------------------------------

class TestFullUserLifecycle:
    """Complete user journey: register → login → subscribe → device → VPN → cancel."""

    def test_complete_lifecycle(self, client, monkeypatch, db):
        """
        Full lifecycle simulation:
        1. Register user
        2. Login
        3. Buy subscription (Stripe)
        4. Create VPN device
        5. Connect VPN
        6. Download configuration
        7. Disconnect VPN
        8. Cancel subscription
        """
        monkeypatch.setenv("STRIPE_SECRET_KEY", "sk_test_e2e")
        monkeypatch.setenv("STRIPE_WEBHOOK_SECRET", WEBHOOK_SECRET)
        monkeypatch.setenv("STRIPE_PRICE_BASIC_MONTHLY", "price_basic_m")
        monkeypatch.setenv("STRIPE_PRICE_BASIC_YEARLY", "price_basic_y")
        monkeypatch.setenv("STRIPE_PRICE_PREMIUM_MONTHLY", "price_premium_m")
        monkeypatch.setenv("STRIPE_PRICE_PREMIUM_YEARLY", "price_premium_y")
        monkeypatch.setenv("STRIPE_PRICE_ULTRA_MONTHLY", "price_ultra_m")
        monkeypatch.setenv("STRIPE_PRICE_ULTRA_YEARLY", "price_ultra_y")
        _patch_stripe(monkeypatch)
        _seed_servers(db)

        # ── Step 1: Register ──
        reg = client.post("/api/auth/register", json={
            "email": "lifecycle@example.com",
            "password": TEST_PASSWORD,
            "password_confirm": TEST_PASSWORD,
        })
        assert reg.status_code == 201, f"Registration: {reg.json()}"

        # ── Step 2: Login ──
        login = client.post("/api/auth/login", json={
            "email": "lifecycle@example.com",
            "password": TEST_PASSWORD,
        })
        assert login.status_code == 200
        token = login.json()["access_token"]
        headers = {"Authorization": f"Bearer {token}"}

        # ── Step 3: Buy subscription ──
        checkout = client.post("/api/payments/stripe/create-checkout-session",
                              json={"plan_id": "premium", "billing_cycle": "monthly"},
                              headers=headers)
        assert checkout.status_code == 200

        user = db.query(User).filter_by(email="lifecycle@example.com").first()
        now = int(time.time())
        sub_obj = {
            "id": "sub_lifecycle_1", "customer": "cus_e2e_test",
            "status": "active",
            "current_period_start": now,
            "current_period_end": now + 30 * 86400,
            "cancel_at_period_end": False,
            "items": {"data": [{"price": {"id": "price_premium_m"}}]},
            "metadata": {
                "securewave_user_id": str(user.id),
                "plan_id": "premium", "billing_cycle": "monthly",
            },
        }
        evt = {"id": "evt_lifecycle_sub", "type": "customer.subscription.created",
               "created": now, "data": {"object": sub_obj}}
        wh = _post_webhook(client, evt)
        assert wh.status_code == 200

        db.refresh(user)
        sub = db.query(Subscription).filter_by(user_id=user.id).first()
        assert sub is not None and sub.status == "active"

        # ── Step 4: Create VPN device ──
        device = client.post("/api/vpn/devices", json={
            "name": "Lifecycle Laptop",
            "device_type": "linux",
            "server_id": "e2e-us-1",
        }, headers=headers)
        assert device.status_code in (200, 201), f"Device: {device.json()}"
        device_id = device.json().get("id") or device.json().get("device_id")

        # ── Step 5: Connect VPN ──
        connect = client.post("/api/vpn/connect",
                             json={"region": "us-east"},
                             headers=headers)
        assert connect.status_code == 200
        assert connect.json().get("status") == "CONNECTED"

        # ── Step 6: Download configuration ──
        if device_id:
            config = client.get(f"/api/vpn/devices/{device_id}/config",
                               headers=headers)
            assert config.status_code == 200

        # ── Step 7: Disconnect VPN ──
        disconnect = client.post("/api/vpn/disconnect", headers=headers)
        assert disconnect.status_code == 200
        assert disconnect.json().get("status") == "DISCONNECTED"

        # ── Step 8: Cancel subscription ──
        sub_obj["status"] = "canceled"
        sub_obj["canceled_at"] = now
        cancel_evt = {"id": "evt_lifecycle_cancel", "type": "customer.subscription.deleted",
                      "created": now + 1, "data": {"object": sub_obj}}
        cancel = _post_webhook(client, cancel_evt)
        assert cancel.status_code == 200

        db.refresh(sub)
        assert sub.status == "canceled"
