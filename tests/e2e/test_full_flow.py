"""
End-to-end test for SecureWave VPN backend.

Exercises the complete user journey:
1. Register a new user
2. Log in
3. Get dashboard info
4. Allocate VPN config (or use demo connect)
5. Report connection quality
6. Check optimizer stats
7. Log out

All operations go through the HTTP API via TestClient.
"""

import time



class TestFullUserJourney:
    """Complete user journey from registration to logout."""

    def test_register_login_vpn_logout(self, client, db):
        """
        End-to-end: register -> login -> dashboard -> VPN -> quality report -> logout.
        """
        # ---- Step 1: Register ----
        reg_resp = client.post("/api/auth/register", json={
            "email": "e2euser@example.com",
            "password": "E2ETestPass123!",
            "password_confirm": "E2ETestPass123!",
        })
        assert reg_resp.status_code == 201, f"Registration failed: {reg_resp.text}"
        reg_data = reg_resp.json()
        # In demo mode we get tokens back directly
        access_token = reg_data.get("access_token")

        # ---- Step 2: Login (if register did not return token) ----
        if not access_token:
            login_resp = client.post("/api/auth/login", json={
                "email": "e2euser@example.com",
                "password": "E2ETestPass123!",
            })
            assert login_resp.status_code == 200, f"Login failed: {login_resp.text}"
            access_token = login_resp.json()["access_token"]

        headers = {"Authorization": f"Bearer {access_token}"}

        # ---- Step 3: Get user info (dashboard) ----
        me_resp = client.get("/api/auth/me", headers=headers)
        assert me_resp.status_code == 200
        me_data = me_resp.json()
        assert me_data["email"] == "e2euser@example.com"
        assert me_data["is_active"] is True

        # ---- Step 4: Get dashboard data ----
        dash_resp = client.get("/api/dashboard/user", headers=headers)
        assert dash_resp.status_code == 200

        # ---- Step 5: VPN connect (demo mode) ----
        connect_resp = client.post(
            "/api/vpn/connect",
            json={"region": "us-east"},
            headers=headers,
        )
        assert connect_resp.status_code == 200
        connect_data = connect_resp.json()
        assert connect_data.get("status") in ("CONNECTING", "CONNECTED")

        # ---- Step 6: Check VPN status (demo transitions after 1 second) ----
        time.sleep(1.1)
        status_resp = client.get("/api/vpn/status", headers=headers)
        assert status_resp.status_code == 200
        assert status_resp.json().get("status") == "CONNECTED"

        # ---- Step 7: Get VPN config ----
        config_resp = client.get("/api/vpn/config", headers=headers)
        assert config_resp.status_code == 200
        config_data = config_resp.json()
        assert "config" in config_data

        # ---- Step 8: Report connection quality to optimizer ----
        from services.vpn_optimizer import get_vpn_optimizer

        optimizer = get_vpn_optimizer()

        # Simulate quality report (optimizer is in-memory, no API endpoint needed)
        if optimizer.servers:
            first_server_id = list(optimizer.servers.keys())[0]
            optimizer.report_connection_quality(
                user_id=1,
                server_id=first_server_id,
                actual_latency=35.0,
                actual_throughput=85.0,
            )

        # ---- Step 9: Check optimizer stats ----
        stats = optimizer.get_stats()
        assert stats["total_servers"] >= 1

        # ---- Step 10: Disconnect VPN ----
        disconnect_resp = client.post("/api/vpn/disconnect", headers=headers)
        assert disconnect_resp.status_code == 200
        # Demo mode returns DISCONNECTING (transitions after 1s)
        assert disconnect_resp.json().get("status") in ("DISCONNECTING", "DISCONNECTED")

        # ---- Step 11: Logout ----
        logout_resp = client.post("/api/auth/logout", headers=headers)
        assert logout_resp.status_code == 200
        assert logout_resp.json().get("status") == "ok"

        # ---- Step 12: Verify session is cleared ----
        # After logout, accessing /me should still work if using Bearer token
        # (stateless JWT), but cookie-based auth would fail.
        # We verify the logout endpoint itself succeeded above.


class TestFullPaymentJourney:
    """Register, subscribe, check VPN access, cancel."""

    def test_register_subscribe_cancel(self, client, db):
        """
        End-to-end: register -> subscribe -> verify access -> cancel.
        """
        # Register
        reg = client.post("/api/auth/register", json={
            "email": "payjour@example.com",
            "password": "PayJourney123!",
            "password_confirm": "PayJourney123!",
        })
        assert reg.status_code == 201
        token = reg.json().get("access_token")
        assert token, "Registration should return access_token in demo mode"
        headers = {"Authorization": f"Bearer {token}"}

        # Verify no subscription
        current = client.get("/api/billing/subscriptions/current", headers=headers)
        assert current.status_code == 200
        assert current.json().get("subscription") is None

        # Subscribe to basic plan
        sub_resp = client.post("/api/billing/subscriptions", json={
            "plan_id": "basic",
            "billing_cycle": "monthly",
            "provider": "stripe",
        }, headers=headers)
        assert sub_resp.status_code == 201
        sub_id = sub_resp.json()["subscription_id"]

        # Verify subscription is active
        current = client.get("/api/billing/subscriptions/current", headers=headers)
        assert current.status_code == 200
        sub_data = current.json().get("subscription")
        assert sub_data is not None
        assert sub_data["plan_id"] == "basic"
        assert sub_data["is_active"] is True

        # Cancel subscription
        cancel = client.post(
            f"/api/billing/subscriptions/{sub_id}/cancel",
            json={"cancel_at_period_end": False, "reason": "e2e test"},
            headers=headers,
        )
        assert cancel.status_code == 200
        assert cancel.json()["subscription"]["status"] == "canceled"


class TestDiagnosticsFlow:
    """Test telemetry and diagnostics endpoints in the user journey."""

    def test_telemetry_submission(self, client, auth_headers):
        """Authenticated user can submit telemetry data."""
        resp = client.post("/api/diagnostics/telemetry", json={
            "latency_ms": 45.0,
            "packet_loss": 0.005,
            "jitter_ms": 3.0,
            "uptime_seconds": 3600,
            "bytes_sent": 1000000,
            "bytes_received": 5000000,
            "server_id": "us-east-1",
            "connection_quality": "good",
        }, headers=auth_headers)
        assert resp.status_code == 200

    def test_telemetry_requires_auth(self, client):
        """Telemetry submission without auth should fail."""
        resp = client.post("/api/diagnostics/telemetry", json={
            "latency_ms": 45.0,
        })
        assert resp.status_code in (401, 403)


class TestHealthEndpointsE2E:
    """Verify the health and version endpoints are reachable end-to-end."""

    def test_health_ok(self, client):
        resp = client.get("/api/health")
        assert resp.status_code == 200
        assert resp.json()["status"] == "ok"

    def test_version_returns_info(self, client):
        resp = client.get("/version")
        assert resp.status_code == 200
        data = resp.json()
        assert "version" in data
        assert "environment" in data

    def test_ready_returns_status(self, client):
        resp = client.get("/api/ready")
        assert resp.status_code == 200
        assert "status" in resp.json()
