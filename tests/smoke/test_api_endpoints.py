"""
Smoke tests for critical API endpoints.

These tests verify that essential endpoints are reachable and return
expected response structures. They do NOT verify full business logic.
"""

import pytest


class TestHealthEndpoints:
    """Health and readiness endpoints must always respond."""

    def test_health_endpoint(self, client):
        response = client.get("/api/health")
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "ok"

    def test_root_health_endpoint(self, client):
        response = client.get("/health")
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "ok"

    def test_ready_endpoint(self, client):
        response = client.get("/api/ready")
        assert response.status_code == 200
        data = response.json()
        assert "status" in data

    def test_email_health_endpoint(self, client):
        response = client.get("/api/health/email")
        # Can be 200 (configured) or 503 (not configured)
        assert response.status_code in (200, 503)
        data = response.json()
        assert "status" in data
        assert "email" in data

    def test_version_endpoint(self, client):
        response = client.get("/version")
        assert response.status_code == 200
        data = response.json()
        assert "version" in data
        assert "environment" in data


class TestAuthEndpoints:
    """Authentication endpoints must accept proper request formats."""

    def test_login_rejects_empty_body(self, client):
        response = client.post("/api/auth/login", json={})
        # Should return validation error, not 500
        assert response.status_code in (400, 422)

    def test_login_rejects_invalid_credentials(self, client):
        response = client.post("/api/auth/login", json={
            "email": "nonexistent@example.com",
            "password": "wrongpassword"
        })
        assert response.status_code in (400, 401)

    def test_register_rejects_empty_body(self, client):
        response = client.post("/api/auth/register", json={})
        assert response.status_code in (400, 422)

    def test_register_rejects_invalid_email(self, client):
        response = client.post("/api/auth/register", json={
            "email": "not-an-email",
            "password": "password123"
        })
        assert response.status_code in (400, 422)

    def test_password_reset_request_accepts_email(self, client):
        response = client.post("/api/auth/password-reset/request", json={
            "email": "test@example.com"
        })
        # Should return 200 even if email doesn't exist (security)
        assert response.status_code in (200, 400, 404)


class TestAuthenticatedEndpoints:
    """Endpoints requiring auth must reject unauthenticated requests."""

    def test_me_requires_auth(self, client):
        response = client.get("/api/auth/me")
        assert response.status_code in (401, 403)

    def test_dashboard_user_requires_auth(self, client):
        response = client.get("/api/dashboard/user")
        assert response.status_code in (401, 403)

    def test_vpn_servers_public(self, client):
        # Server list may be public for discovery
        response = client.get("/api/vpn/servers")
        assert response.status_code in (200, 401, 403)

    def test_devices_requires_auth(self, client):
        response = client.get("/api/vpn/devices")
        assert response.status_code in (401, 403)


class TestAuthenticatedUserEndpoints:
    """Test endpoints with authenticated user."""

    def test_me_returns_user_info(self, client, auth_headers):
        response = client.get("/api/auth/me", headers=auth_headers)
        assert response.status_code == 200
        data = response.json()
        assert "email" in data

    def test_dashboard_user(self, client, auth_headers):
        response = client.get("/api/dashboard/user", headers=auth_headers)
        assert response.status_code == 200
        data = response.json()
        # Should have user info
        assert isinstance(data, dict)

    def test_vpn_servers_list(self, client, auth_headers):
        response = client.get("/api/vpn/servers", headers=auth_headers)
        assert response.status_code == 200
        data = response.json()
        # Response is either a list or dict with servers
        assert isinstance(data, (list, dict))

    def test_devices_list(self, client, auth_headers):
        response = client.get("/api/vpn/devices", headers=auth_headers)
        assert response.status_code == 200
        data = response.json()
        # Response is either a list or dict with devices
        assert isinstance(data, (list, dict))


class TestVpnConfigGeneration:
    """VPN config generation smoke tests."""

    def test_connect_requires_auth(self, client):
        response = client.post("/api/vpn/connect", json={"server_id": 1})
        assert response.status_code in (401, 403)

    def test_disconnect_requires_auth(self, client):
        response = client.post("/api/vpn/disconnect")
        assert response.status_code in (401, 403)


class TestAdminEndpoints:
    """Admin endpoints must require admin privileges."""

    def test_admin_servers_requires_admin(self, client, auth_headers):
        response = client.get("/api/admin/servers", headers=auth_headers)
        # Regular user should be forbidden
        assert response.status_code in (403, 401)

    def test_admin_servers_allowed_for_admin(self, client, admin_auth_headers):
        response = client.get("/api/admin/servers", headers=admin_auth_headers)
        assert response.status_code == 200


class TestContactEndpoint:
    """Contact form endpoint."""

    def test_contact_rejects_empty_body(self, client):
        response = client.post("/api/contact/submit", json={})
        assert response.status_code in (400, 422)


class TestSecurityHeaders:
    """Verify security headers are present."""

    def test_security_headers_on_api(self, client):
        response = client.get("/api/health")
        headers = response.headers
        assert headers.get("X-Content-Type-Options") == "nosniff"
        assert headers.get("X-Frame-Options") == "DENY"
        assert "X-Request-ID" in headers

    def test_request_id_returned(self, client):
        response = client.get("/api/health")
        assert "X-Request-ID" in response.headers


class TestErrorResponses:
    """Error responses should be well-formed JSON."""

    def test_404_returns_json_for_api(self, client):
        response = client.get("/api/nonexistent-endpoint")
        assert response.status_code == 404
        data = response.json()
        assert "error" in data or "detail" in data

    def test_validation_error_includes_details(self, client):
        response = client.post("/api/auth/login", json={"invalid": "data"})
        assert response.status_code in (400, 422)
        data = response.json()
        # Should have error structure
        assert "error" in data or "detail" in data
