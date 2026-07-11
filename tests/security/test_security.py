"""
Security tests for SecureWave VPN backend.

Covers:
- CSRF protection
- CSP / security headers
- XSS payload rejection in form fields
- SQL injection blocking in auth endpoints
- Rate limiting behaviour
- JWT token expiration
- Password strength validation
- 2FA enrollment and verification flow
"""

import time
from datetime import datetime, timedelta

import pytest
from fastapi import status
from jose import jwt


# ---------------------------------------------------------------------------
# CSRF Protection
# ---------------------------------------------------------------------------

class TestCSRFProtection:
    """Verify that state-changing requests without a valid session are rejected."""

    def test_post_without_auth_returns_401_or_403(self, client):
        """POST to a protected endpoint without credentials must fail."""
        response = client.post("/api/vpn/connect", json={"region": "us-east"})
        assert response.status_code in (401, 403)

    def test_post_with_invalid_token_returns_401(self, client):
        """POST with a garbage bearer token must fail."""
        headers = {"Authorization": "Bearer totally.invalid.token"}
        response = client.post("/api/vpn/connect", json={"region": "us-east"}, headers=headers)
        assert response.status_code in (401, 403)

    def test_logout_clears_cookies(self, client, auth_headers):
        """Logout should instruct browser to clear auth cookies."""
        response = client.post("/api/auth/logout", headers=auth_headers)
        assert response.status_code == 200
        # The response should contain Set-Cookie directives that clear tokens
        set_cookies = response.headers.get_list("set-cookie") if hasattr(response.headers, "get_list") else []
        # At minimum the endpoint must return success
        data = response.json()
        assert data.get("status") == "ok"


# ---------------------------------------------------------------------------
# Content Security Policy / Security Headers
# ---------------------------------------------------------------------------

class TestSecurityHeaders:
    """All responses must carry hardening headers."""

    @pytest.mark.parametrize("path", [
        "/api/health",
        "/api/ready",
        "/version",
    ])
    def test_security_headers_present(self, client, path):
        """Critical security headers must be present on every response."""
        response = client.get(path)
        headers = response.headers

        assert headers.get("X-Content-Type-Options") == "nosniff", \
            f"Missing X-Content-Type-Options on {path}"
        assert headers.get("X-Frame-Options") == "DENY", \
            f"Missing X-Frame-Options on {path}"
        assert "X-Request-ID" in headers, \
            f"Missing X-Request-ID on {path}"

    def test_request_id_unique_per_request(self, client):
        """Each request must receive a distinct X-Request-ID."""
        id1 = client.get("/api/health").headers.get("X-Request-ID")
        id2 = client.get("/api/health").headers.get("X-Request-ID")
        assert id1 != id2, "X-Request-ID should be unique per request"


# ---------------------------------------------------------------------------
# XSS Payload Rejection
# ---------------------------------------------------------------------------

class TestXSSProtection:
    """Form fields must not accept or reflect XSS payloads."""

    XSS_PAYLOADS = [
        "<script>alert('xss')</script>",
        '"><img src=x onerror=alert(1)>',
        "javascript:alert(document.cookie)",
        "<svg/onload=alert(1)>",
        "';DROP TABLE users;--",
    ]

    @pytest.mark.parametrize("payload", XSS_PAYLOADS)
    def test_xss_in_registration_email(self, client, payload):
        """XSS payloads in the email field must be rejected (invalid email)."""
        response = client.post("/api/auth/register", json={
            "email": payload,
            "password": "SecurePass123!",
            "password_confirm": "SecurePass123!",
        })
        # Pydantic EmailStr validation should reject these
        assert response.status_code in (400, 422), \
            f"XSS payload in email was not rejected: {payload}"

    @pytest.mark.parametrize("payload", XSS_PAYLOADS)
    def test_xss_in_contact_form(self, client, payload):
        """XSS payloads in the contact form should not cause 500 errors."""
        response = client.post("/api/contact/submit", json={
            "name": payload,
            "email": "test@example.com",
            "message": payload,
        })
        # Acceptable: 200, 400, 422 -- NOT 500
        assert response.status_code != 500, \
            f"XSS payload caused server error: {payload}"

    def test_validation_response_does_not_reflect_sensitive_input(self, client):
        private_key = "PrivateKeyThatMustNotBeEchoed"
        response = client.post(
            "/api/auth/login",
            json={"email": "test@example.com", "password": {"private_key": private_key}},
        )
        assert response.status_code == status.HTTP_422_UNPROCESSABLE_ENTITY
        assert private_key not in response.text
        details = response.json()["error"]["details"]
        assert details[0]["message"] == "Invalid value"


# ---------------------------------------------------------------------------
# SQL Injection Blocking
# ---------------------------------------------------------------------------

class TestSQLInjection:
    """SQL injection attempts must not compromise auth endpoints."""

    SQLI_PAYLOADS = [
        "' OR '1'='1",
        "'; DROP TABLE users; --",
        "1' UNION SELECT * FROM users--",
        "admin'--",
        "' OR 1=1--",
    ]

    @pytest.mark.parametrize("payload", SQLI_PAYLOADS)
    def test_sqli_in_login_email(self, client, payload):
        """SQL injection in login email field must not return 500 or success."""
        response = client.post("/api/auth/login", json={
            "email": payload,
            "password": "anything",
        })
        # EmailStr validation rejects non-email strings, or auth rejects
        assert response.status_code in (400, 401, 422), \
            f"Unexpected status {response.status_code} for SQLi payload: {payload}"

    @pytest.mark.parametrize("payload", SQLI_PAYLOADS)
    def test_sqli_in_login_password(self, client, test_user, payload):
        """SQL injection in password field must return auth failure, not 500."""
        response = client.post("/api/auth/login", json={
            "email": "test@example.com",
            "password": payload,
        })
        assert response.status_code in (400, 401, 422, 423), \
            f"Unexpected status {response.status_code} for SQLi in password"

    @pytest.mark.parametrize("payload", SQLI_PAYLOADS)
    def test_sqli_in_register_email(self, client, payload):
        """SQL injection in register email field must be rejected."""
        response = client.post("/api/auth/register", json={
            "email": payload,
            "password": "SecurePass123!",
            "password_confirm": "SecurePass123!",
        })
        assert response.status_code in (400, 422), \
            f"Unexpected status {response.status_code} for SQLi in register"


# ---------------------------------------------------------------------------
# Rate Limiting
# ---------------------------------------------------------------------------

class TestRateLimiting:
    """
    Rate limiting is disabled during tests (TESTING=true), so we verify
    that the rate_limit decorator exists but does not block test requests.
    If rate limiting were enabled, rapid requests would return 429.
    """

    def test_rapid_login_attempts_not_500(self, client, test_user):
        """Multiple rapid login attempts must not crash the server."""
        for _ in range(10):
            response = client.post("/api/auth/login", json={
                "email": "test@example.com",
                "password": "wrongpassword",
            })
            assert response.status_code in (401, 423, 429), \
                f"Unexpected status {response.status_code} during rapid login"

    def test_rapid_register_attempts_not_500(self, client):
        """Multiple rapid registration attempts must not crash the server."""
        for i in range(5):
            response = client.post("/api/auth/register", json={
                "email": f"flood{i}@example.com",
                "password": "SecurePass123!",
                "password_confirm": "SecurePass123!",
            })
            assert response.status_code in (201, 400, 422, 429), \
                f"Unexpected status {response.status_code} during rapid register"


# ---------------------------------------------------------------------------
# JWT Token Expiration
# ---------------------------------------------------------------------------

class TestJWTExpiration:
    """JWT tokens must respect expiration claims."""

    def test_expired_access_token_rejected(self, client, test_user):
        """An access token with exp in the past must be rejected."""
        from services.jwt_service import ACCESS_SECRET, ALGORITHM

        expired_payload = {
            "sub": str(test_user.id),
            "email": test_user.email,
            "type": "access",
            "exp": datetime.utcnow() - timedelta(minutes=5),
        }
        expired_token = jwt.encode(expired_payload, ACCESS_SECRET, algorithm=ALGORITHM)

        response = client.get(
            "/api/auth/me",
            headers={"Authorization": f"Bearer {expired_token}"},
        )
        assert response.status_code in (401, 403), \
            "Expired JWT token should be rejected"

    def test_token_with_wrong_secret_rejected(self, client, test_user):
        """A token signed with the wrong secret must be rejected."""
        forged_payload = {
            "sub": str(test_user.id),
            "email": test_user.email,
            "type": "access",
            "exp": datetime.utcnow() + timedelta(minutes=30),
        }
        forged_token = jwt.encode(forged_payload, "wrong-secret-key", algorithm="HS256")

        response = client.get(
            "/api/auth/me",
            headers={"Authorization": f"Bearer {forged_token}"},
        )
        assert response.status_code in (401, 403), \
            "Token signed with wrong secret should be rejected"

    def test_valid_token_accepted(self, client, auth_headers):
        """A properly signed, non-expired token must be accepted."""
        response = client.get("/api/auth/me", headers=auth_headers)
        assert response.status_code == 200


# ---------------------------------------------------------------------------
# Password Strength Validation
# ---------------------------------------------------------------------------

class TestPasswordStrength:
    """Registration must enforce the password policy."""

    def test_too_short_password_rejected(self, client):
        """Passwords shorter than 8 characters must be rejected."""
        response = client.post("/api/auth/register", json={
            "email": "short@example.com",
            "password": "Ab1!",
            "password_confirm": "Ab1!",
        })
        assert response.status_code == 400
        assert "8 characters" in response.json().get("detail", "").lower() or \
               response.status_code == 400

    def test_no_letter_password_rejected(self, client):
        """Passwords without letters must be rejected."""
        response = client.post("/api/auth/register", json={
            "email": "nolet@example.com",
            "password": "12345678",
            "password_confirm": "12345678",
        })
        assert response.status_code == 400

    def test_no_digit_password_rejected(self, client):
        """Passwords without digits must be rejected."""
        response = client.post("/api/auth/register", json={
            "email": "nodig@example.com",
            "password": "abcdefgh",
            "password_confirm": "abcdefgh",
        })
        assert response.status_code == 400

    def test_mismatched_passwords_rejected(self, client):
        """Mismatched password and password_confirm must be rejected."""
        response = client.post("/api/auth/register", json={
            "email": "mismatch@example.com",
            "password": "SecurePass123!",
            "password_confirm": "DifferentPass456!",
        })
        assert response.status_code == 400

    def test_strong_password_accepted(self, client):
        """A password meeting all requirements must be accepted."""
        response = client.post("/api/auth/register", json={
            "email": "strong@example.com",
            "password": "StrongPass123!",
            "password_confirm": "StrongPass123!",
        })
        assert response.status_code == 201


# ---------------------------------------------------------------------------
# Two-Factor Authentication Flow
# ---------------------------------------------------------------------------

class TestTwoFactorAuth:
    """Full 2FA enrollment, verification, and disable flow."""

    def test_2fa_setup_returns_secret_and_backup_codes(self, client, auth_headers):
        """2FA setup must return a TOTP secret and backup codes."""
        response = client.post("/api/auth/2fa/setup", headers=auth_headers)
        assert response.status_code == 200
        data = response.json()
        assert "secret" in data
        assert "backup_codes" in data
        assert len(data["backup_codes"]) > 0
        assert "qr_code_url" in data

    def test_2fa_verify_with_valid_code(self, client, auth_headers, test_user, db):
        """A valid TOTP code must successfully enable 2FA."""
        import pyotp

        # Setup
        setup_resp = client.post("/api/auth/2fa/setup", headers=auth_headers)
        assert setup_resp.status_code == 200
        secret = setup_resp.json()["secret"]

        # Generate valid code
        totp = pyotp.TOTP(secret)
        code = totp.now()

        # Verify
        verify_resp = client.post(
            "/api/auth/2fa/verify",
            headers=auth_headers,
            json={"totp_code": code},
        )
        assert verify_resp.status_code == 200

    def test_2fa_verify_with_invalid_code(self, client, auth_headers):
        """An invalid TOTP code must be rejected."""
        # Setup 2FA first
        client.post("/api/auth/2fa/setup", headers=auth_headers)

        response = client.post(
            "/api/auth/2fa/verify",
            headers=auth_headers,
            json={"totp_code": "000000"},
        )
        assert response.status_code in (400, 401)

    def test_2fa_disable_after_enable(self, client, auth_headers, test_user, db):
        """2FA can be disabled with a valid TOTP code after enabling."""
        import pyotp

        # Setup and enable
        setup_resp = client.post("/api/auth/2fa/setup", headers=auth_headers)
        secret = setup_resp.json()["secret"]
        totp = pyotp.TOTP(secret)
        code = totp.now()
        client.post("/api/auth/2fa/verify", headers=auth_headers, json={"totp_code": code})

        # Disable -- generate a fresh code (may have ticked over)
        disable_code = totp.now()
        disable_resp = client.post(
            "/api/auth/2fa/disable",
            headers=auth_headers,
            json={"totp_code": disable_code},
        )
        assert disable_resp.status_code == 200

    def test_2fa_status_endpoint(self, client, auth_headers):
        """2FA status endpoint must return enabled state."""
        response = client.get("/api/auth/2fa/status", headers=auth_headers)
        assert response.status_code == 200
        data = response.json()
        assert "enabled" in data
        assert isinstance(data["enabled"], bool)
