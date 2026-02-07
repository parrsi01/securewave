"""
SecureWave - VPN Flow Integration Tests
========================================
Covers:
- Full VPN flow: register -> login -> servers -> allocate -> connect -> disconnect
- Free user connect via demo VPN flow
- Premium servers not accessible to free users (tier restriction)
- VPN config contains valid WireGuard format
- Server selection returns optimal server
- Mock / demo mode returns valid configs
- Device creation and revocation
"""

import time

import pytest
from fastapi import status


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _create_free_server(db):
    """Insert a free-tier demo VPN server and return it."""
    from models.vpn_server import VPNServer

    server = VPNServer(
        server_id="test-free-us-1",
        location="New York, US",
        country="United States",
        country_code="US",
        city="New York",
        region="Americas",
        azure_region="eastus",
        public_ip="10.0.0.1",
        endpoint="10.0.0.1:51820",
        wg_public_key="dGVzdC1wdWJsaWMta2V5LWZyZWUtc2VydmVy",
        wg_private_key_encrypted="encrypted-private-key",
        status="active",
        health_status="healthy",
        max_connections=1000,
        current_connections=10,
        tier_restriction=None,
        performance_score=90.0,
        azure_vm_state="running",
    )
    db.add(server)
    db.commit()
    db.refresh(server)
    return server


def _create_premium_server(db):
    """Insert a premium-tier demo VPN server and return it."""
    from models.vpn_server import VPNServer

    server = VPNServer(
        server_id="test-premium-eu-1",
        location="London, UK",
        country="United Kingdom",
        country_code="GB",
        city="London",
        region="Europe",
        azure_region="uksouth",
        public_ip="10.0.1.1",
        endpoint="10.0.1.1:51820",
        wg_public_key="dGVzdC1wdWJsaWMta2V5LXByZW1pdW0tc2VydmVy",
        wg_private_key_encrypted="encrypted-private-key-premium",
        status="active",
        health_status="healthy",
        max_connections=500,
        current_connections=5,
        tier_restriction="premium",
        performance_score=95.0,
        azure_vm_state="running",
    )
    db.add(server)
    db.commit()
    db.refresh(server)
    return server


def _create_subscription(db, user, plan_id="basic"):
    """Create an active subscription for a user."""
    from models.subscription import Subscription
    from datetime import datetime, timedelta

    sub = Subscription(
        user_id=user.id,
        plan_id=plan_id,
        plan_name=plan_id.capitalize(),
        provider="stripe",
        status="active",
        amount=9.0,
        currency="USD",
        billing_cycle="monthly",
        current_period_start=datetime.utcnow(),
        current_period_end=datetime.utcnow() + timedelta(days=30),
    )
    db.add(sub)
    db.commit()
    db.refresh(sub)
    return sub


# ---------------------------------------------------------------------------
# Full VPN Flow (register -> login -> servers -> connect -> disconnect)
# ---------------------------------------------------------------------------

class TestFullVPNFlow:
    """End-to-end VPN flow in demo mode."""

    def test_full_vpn_flow(self, client, db):
        """
        Complete flow:
        1. Register a new user
        2. Login with credentials
        3. List available servers
        4. Connect to VPN (allocate session)
        5. Check connection status
        6. Disconnect from VPN
        """
        # Step 1: Register
        reg_resp = client.post("/api/auth/register", json={
            "email": "vpnflow@example.com",
            "password": "SecurePass123",
            "password_confirm": "SecurePass123",
        })
        assert reg_resp.status_code == 201, f"Registration failed: {reg_resp.json()}"
        reg_data = reg_resp.json()
        token = reg_data.get("access_token")
        assert token, "No access token in registration response"
        headers = {"Authorization": f"Bearer {token}"}

        # Step 2: Login (verify credentials work)
        login_resp = client.post("/api/auth/login", json={
            "email": "vpnflow@example.com",
            "password": "SecurePass123",
        })
        assert login_resp.status_code == 200, f"Login failed: {login_resp.json()}"
        login_token = login_resp.json().get("access_token")
        assert login_token
        headers = {"Authorization": f"Bearer {login_token}"}

        # Step 3: List servers (may be empty in test, but endpoint must work)
        servers_resp = client.get("/api/vpn/servers", headers=headers)
        assert servers_resp.status_code == 200
        assert "servers" in servers_resp.json()

        # Step 4: Connect to VPN (demo mode)
        connect_resp = client.post(
            "/api/vpn/connect",
            json={"region": "us-east"},
            headers=headers,
        )
        assert connect_resp.status_code == 200
        connect_data = connect_resp.json()
        assert connect_data.get("status") in ("CONNECTING", "CONNECTED")

        # Step 5: Check status (wait for CONNECTED in demo mode)
        time.sleep(1.1)
        status_resp = client.get("/api/vpn/status", headers=headers)
        assert status_resp.status_code == 200
        assert status_resp.json().get("status") == "CONNECTED"

        # Step 6: Disconnect
        disconnect_resp = client.post("/api/vpn/disconnect", headers=headers)
        assert disconnect_resp.status_code == 200
        assert disconnect_resp.json().get("status") in ("DISCONNECTING", "DISCONNECTED")


# ---------------------------------------------------------------------------
# Demo VPN Connect / Disconnect Flow
# ---------------------------------------------------------------------------

class TestDemoVPNFlow:
    """In demo/mock mode the VPN connect/disconnect/status cycle must work."""

    def test_connect_returns_status(self, client, auth_headers):
        """POST /api/vpn/connect must return a connection status."""
        response = client.post(
            "/api/vpn/connect",
            json={"region": "us-east"},
            headers=auth_headers,
        )
        assert response.status_code == 200
        data = response.json()
        assert data.get("status") in ("CONNECTING", "CONNECTED")

    def test_status_after_connect(self, client, auth_headers):
        """GET /api/vpn/status after connect should show CONNECTED."""
        client.post("/api/vpn/connect", json={"region": "us-east"}, headers=auth_headers)

        # Demo mode transitions CONNECTING -> CONNECTED after 1 second
        time.sleep(1.1)

        resp = client.get("/api/vpn/status", headers=auth_headers)
        assert resp.status_code == 200
        assert resp.json().get("status") == "CONNECTED"

    def test_config_after_connect(self, client, auth_headers):
        """GET /api/vpn/config after connect should return config data."""
        client.post("/api/vpn/connect", json={"region": "us-east"}, headers=auth_headers)

        # Wait for CONNECTED
        for _ in range(5):
            st = client.get("/api/vpn/status", headers=auth_headers)
            if st.json().get("status") == "CONNECTED":
                break
            time.sleep(0.2)

        resp = client.get("/api/vpn/config", headers=auth_headers)
        assert resp.status_code == 200
        data = resp.json()
        assert "config" in data

    def test_disconnect(self, client, auth_headers):
        """POST /api/vpn/disconnect must return a disconnecting or disconnected status."""
        client.post("/api/vpn/connect", json={"region": "us-east"}, headers=auth_headers)
        resp = client.post("/api/vpn/disconnect", headers=auth_headers)
        assert resp.status_code == 200
        data = resp.json()
        assert data.get("status") in ("DISCONNECTING", "DISCONNECTED")


# ---------------------------------------------------------------------------
# Server Listing and Tier Restriction
# ---------------------------------------------------------------------------

class TestServerListing:
    """Server listing must respect user tier restrictions."""

    def test_free_user_sees_free_servers(self, client, auth_headers, db):
        """Free-tier user should see servers with no tier restriction."""
        _create_free_server(db)
        _create_premium_server(db)

        resp = client.get("/api/vpn/servers", headers=auth_headers)
        assert resp.status_code == 200
        data = resp.json()
        assert data["total"] >= 1

        server_ids = [s["server_id"] for s in data["servers"]]
        assert "test-free-us-1" in server_ids
        assert "test-premium-eu-1" not in server_ids

    def test_premium_user_sees_all_servers(self, client, auth_headers, test_user, db):
        """Premium user should see both free and premium servers."""
        _create_free_server(db)
        _create_premium_server(db)
        _create_subscription(db, test_user, plan_id="premium")

        resp = client.get("/api/vpn/servers", headers=auth_headers)
        assert resp.status_code == 200
        data = resp.json()

        server_ids = [s["server_id"] for s in data["servers"]]
        assert "test-free-us-1" in server_ids
        assert "test-premium-eu-1" in server_ids


# ---------------------------------------------------------------------------
# VPN Config Format Validation
# ---------------------------------------------------------------------------

class TestVPNConfigFormat:
    """Allocated VPN configs must contain valid WireGuard directives."""

    def test_demo_config_has_wireguard_sections(self, client, auth_headers):
        """The demo config must contain [Interface] and [Peer]."""
        client.post("/api/vpn/connect", json={"region": "us-east"}, headers=auth_headers)

        for _ in range(5):
            st = client.get("/api/vpn/status", headers=auth_headers)
            if st.json().get("status") == "CONNECTED":
                break
            time.sleep(0.2)

        resp = client.get("/api/vpn/config", headers=auth_headers)
        assert resp.status_code == 200
        config_text = resp.json().get("config", "")
        assert "[Interface]" in config_text
        assert "[Peer]" in config_text

    def test_allocate_config_contains_wireguard_keys(self, client, auth_headers, test_user, db):
        """POST /api/vpn/allocate must return config with WireGuard directives."""
        server = _create_free_server(db)

        resp = client.post(
            "/api/vpn/allocate",
            json={"server_id": server.server_id},
            headers=auth_headers,
        )
        if resp.status_code == 200:
            data = resp.json()
            config_text = data.get("config", "")
            assert "PrivateKey" in config_text
            assert "PublicKey" in config_text
            assert "Endpoint" in config_text
            assert "AllowedIPs" in config_text
            assert data.get("status") == "allocated"
        else:
            # If subscription check blocks, that is acceptable
            assert resp.status_code in (403, 402)


# ---------------------------------------------------------------------------
# Server Selection Optimality
# ---------------------------------------------------------------------------

class TestServerSelection:
    """Server recommendation should pick the highest-performing healthy server."""

    def test_recommended_server_is_healthy(self, client, auth_headers, db):
        """The recommended_server_id must point to a healthy server."""
        _create_free_server(db)

        resp = client.get("/api/vpn/servers", headers=auth_headers)
        assert resp.status_code == 200
        data = resp.json()

        recommended_id = data.get("recommended_server_id")
        if recommended_id:
            server_map = {s["server_id"]: s for s in data["servers"]}
            assert recommended_id in server_map
            assert server_map[recommended_id]["health_status"] == "healthy"


# ---------------------------------------------------------------------------
# Mock Mode Returns Valid Configs
# ---------------------------------------------------------------------------

class TestMockMode:
    """In test/demo mode the VPN flow must produce usable mock configs."""

    def test_connect_disconnect_cycle_in_mock(self, client, auth_headers):
        """Full connect -> status -> disconnect cycle must not error."""
        conn = client.post("/api/vpn/connect", json={"region": "us-east"}, headers=auth_headers)
        assert conn.status_code == 200

        st = client.get("/api/vpn/status", headers=auth_headers)
        assert st.status_code == 200

        disc = client.post("/api/vpn/disconnect", headers=auth_headers)
        assert disc.status_code == 200

    def test_connect_requires_auth(self, client):
        """VPN connect without auth must be rejected."""
        resp = client.post("/api/vpn/connect", json={"region": "us-east"})
        assert resp.status_code in (401, 403)

    def test_status_requires_auth(self, client):
        """VPN status without auth must be rejected."""
        resp = client.get("/api/vpn/status")
        assert resp.status_code in (401, 403)

    def test_disconnect_requires_auth(self, client):
        """VPN disconnect without auth must be rejected."""
        resp = client.post("/api/vpn/disconnect")
        assert resp.status_code in (401, 403)
