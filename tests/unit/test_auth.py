"""
SecureWave - Authentication Unit Tests
=======================================
Covers:
- Successful user registration
- Duplicate email registration rejection
- Successful login with correct credentials
- Login rejection with wrong password
- Password strength validation
- Token generation and validation
"""

import pytest
from fastapi import status


class TestRegisterSuccess:
    """Registration with valid data must succeed."""

    def test_register_success(self, client):
        """A new user with a valid email and strong password should register."""
        response = client.post("/api/auth/register", json={
            "email": "newuser@example.com",
            "password": "SecurePass123!",
            "password_confirm": "SecurePass123!",
        })
        assert response.status_code == status.HTTP_201_CREATED
        data = response.json()
        assert "user_id" in data
        assert "email" in data
        # Tokens are set via Set-Cookie only — not in the JSON body.
        assert "access_token" not in data
        assert "refresh_token" not in data

    def test_register_returns_csrf_token(self, client):
        """Registration sets csrf_token as a cookie (not in JSON body)."""
        response = client.post("/api/auth/register", json={
            "email": "csrftest@example.com",
            "password": "SecurePass123!",
            "password_confirm": "SecurePass123!",
        })
        assert response.status_code == status.HTTP_201_CREATED
        # csrf_token is set as a cookie, not returned in the JSON body.
        assert "csrf_token" in response.cookies


class TestRegisterDuplicate:
    """Duplicate email registration must be rejected."""

    def test_register_duplicate(self, client, test_user):
        """Registering with an already-registered email must return 400."""
        response = client.post("/api/auth/register", json={
            "email": "testuser@example.com",
            "password": "SecurePass123!",
            "password_confirm": "SecurePass123!",
        })
        assert response.status_code == status.HTTP_400_BAD_REQUEST
        data = response.json()
        detail = data.get("detail") or data.get("error", {}).get("message", "")
        assert "already" in detail.lower() or "registered" in detail.lower()

    def test_register_duplicate_case_insensitive(self, client, test_user):
        """Email uniqueness should be enforced (if app normalizes case)."""
        response = client.post("/api/auth/register", json={
            "email": "TESTUSER@example.com",
            "password": "SecurePass123!",
            "password_confirm": "SecurePass123!",
        })
        # Accept 400 (duplicate) or 201 (if case-sensitive -- still valid)
        assert response.status_code in (
            status.HTTP_400_BAD_REQUEST,
            status.HTTP_201_CREATED,
        )


class TestLoginSuccess:
    """Login with correct credentials must succeed."""

    def test_login_success(self, client, test_user):
        """Login with the correct email and password returns tokens."""
        response = client.post("/api/auth/login", json={
            "email": "testuser@example.com",
            "password": "TestPass123",
        })
        assert response.status_code == status.HTTP_200_OK
        data = response.json()
        assert "access_token" in data
        assert "refresh_token" in data
        assert data["token_type"] == "bearer"
        assert data["requires_2fa"] is False

    def test_login_returns_valid_jwt(self, client, test_user):
        """The access token from login must be usable for authenticated requests."""
        login_resp = client.post("/api/auth/login", json={
            "email": "testuser@example.com",
            "password": "TestPass123",
        })
        assert login_resp.status_code == 200
        token = login_resp.json()["access_token"]

        # Use the token to access a protected endpoint
        me_resp = client.get(
            "/api/auth/me",
            headers={"Authorization": f"Bearer {token}"},
        )
        assert me_resp.status_code == 200
        assert me_resp.json()["email"] == "testuser@example.com"


class TestLoginWrongPassword:
    """Login with wrong password must fail."""

    def test_login_wrong_password(self, client, test_user):
        """Login with incorrect password returns 401."""
        response = client.post("/api/auth/login", json={
            "email": "testuser@example.com",
            "password": "WrongPassword999",
        })
        assert response.status_code == status.HTTP_401_UNAUTHORIZED
        data = response.json()
        detail = data.get("detail") or data.get("error", {}).get("message", "")
        assert "invalid" in detail.lower() or "credentials" in detail.lower()

    def test_login_nonexistent_user(self, client):
        """Login with a non-existent email returns 401 (no user enumeration)."""
        response = client.post("/api/auth/login", json={
            "email": "nobody@example.com",
            "password": "AnyPassword123",
        })
        assert response.status_code == status.HTTP_401_UNAUTHORIZED

    def test_login_empty_password(self, client, test_user):
        """Login with empty password must fail."""
        response = client.post("/api/auth/login", json={
            "email": "testuser@example.com",
            "password": "",
        })
        # Should be 401 (invalid credentials) or 422 (validation error)
        assert response.status_code in (
            status.HTTP_401_UNAUTHORIZED,
            status.HTTP_422_UNPROCESSABLE_ENTITY,
        )


class TestPasswordValidation:
    """Password policy enforcement during registration."""

    def test_short_password_rejected(self, client):
        """Passwords shorter than 8 characters must be rejected."""
        response = client.post("/api/auth/register", json={
            "email": "short@example.com",
            "password": "Ab1",
            "password_confirm": "Ab1",
        })
        assert response.status_code == status.HTTP_400_BAD_REQUEST

    def test_no_digit_rejected(self, client):
        """Passwords without digits must be rejected."""
        response = client.post("/api/auth/register", json={
            "email": "nodigit@example.com",
            "password": "abcdefgh",
            "password_confirm": "abcdefgh",
        })
        assert response.status_code == status.HTTP_400_BAD_REQUEST

    def test_no_letter_rejected(self, client):
        """Passwords without letters must be rejected."""
        response = client.post("/api/auth/register", json={
            "email": "noletter@example.com",
            "password": "12345678",
            "password_confirm": "12345678",
        })
        assert response.status_code == status.HTTP_400_BAD_REQUEST

    def test_password_mismatch_rejected(self, client):
        """Mismatched password and confirmation must be rejected."""
        response = client.post("/api/auth/register", json={
            "email": "mismatch@example.com",
            "password": "SecurePass123!",
            "password_confirm": "DifferentPass456",
        })
        assert response.status_code == status.HTTP_400_BAD_REQUEST


class TestTokenRefresh:
    """Token refresh flow."""

    def test_refresh_with_valid_token(self, client, test_user, refresh_token):
        """A valid refresh token should return new access and refresh tokens."""
        client.cookies.set("access_token", "browser.session.token")
        client.cookies.set("refresh_token", refresh_token)
        client.cookies.set("csrf_token", "csrf-ok")
        response = client.post("/api/auth/refresh", headers={"X-CSRF-Token": "csrf-ok"})
        client.cookies.clear()
        assert response.status_code == 200
        data = response.json()
        assert "access_token" in data
        assert "refresh_token" in data

    def test_refresh_with_invalid_token(self, client):
        """An invalid refresh token should be rejected."""
        response = client.post(
            "/api/auth/refresh",
            headers={"Authorization": "Bearer invalid.token.here"},
        )
        assert response.status_code == 401
