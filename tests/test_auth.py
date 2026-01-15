"""
Authentication tests
"""

import pytest
from fastapi import status


class TestRegistration:
    """Test user registration"""

    def test_register_success(self, client):
        """Test successful registration"""
        response = client.post(
            "/api/auth/register",
            json={
                "email": "newuser@example.com",
                "password": "SecurePass123!",
                "password_confirm": "SecurePass123!"
            }
        )
        assert response.status_code == status.HTTP_201_CREATED
        data = response.json()
        assert "access_token" in data

    def test_register_duplicate_email(self, client, test_user):
        """Test registration with duplicate email"""
        response = client.post(
            "/api/auth/register",
            json={
                "email": "test@example.com",
                "password": "SecurePass123!",
                "password_confirm": "SecurePass123!"
            }
        )
        assert response.status_code == status.HTTP_400_BAD_REQUEST

    def test_register_weak_password(self, client):
        """Test registration with weak password"""
        response = client.post(
            "/api/auth/register",
            json={
                "email": "weak@example.com",
                "password": "123",
                "password_confirm": "123"
            }
        )
        assert response.status_code == status.HTTP_400_BAD_REQUEST


class TestLogin:
    """Test user login"""

    def test_login_success(self, client, test_user):
        """Test successful login"""
        response = client.post(
            "/api/auth/login",
            json={
                "email": "test@example.com",
                "password": "testpassword123"
            }
        )
        assert response.status_code == status.HTTP_200_OK
        data = response.json()
        assert "access_token" in data
        assert "refresh_token" in data

    def test_login_invalid_credentials(self, client, test_user):
        """Test login with invalid credentials"""
        response = client.post(
            "/api/auth/login",
            json={
                "email": "test@example.com",
                "password": "wrongpassword"
            }
        )
        assert response.status_code == status.HTTP_401_UNAUTHORIZED

    def test_login_nonexistent_user(self, client):
        """Test login with nonexistent user"""
        response = client.post(
            "/api/auth/login",
            json={
                "email": "nonexistent@example.com",
                "password": "password123"
            }
        )
        assert response.status_code == status.HTTP_401_UNAUTHORIZED


class TestPasswordReset:
    """Test password reset"""

    def test_password_reset_request(self, client, test_user):
        """Test password reset request"""
        response = client.post(
            "/api/auth/password-reset/request",
            json={"email": "test@example.com"}
        )
        assert response.status_code == status.HTTP_200_OK
        assert "message" in response.json()

    def test_password_reset_invalid_email(self, client):
        """Test password reset with invalid email"""
        response = client.post(
            "/api/auth/password-reset/request",
            json={"email": "invalid@example.com"}
        )
        # Should return 200 to prevent email enumeration
        assert response.status_code == status.HTTP_200_OK


class TestTwoFactorAuth:
    """Test 2FA"""

    def test_2fa_setup(self, client, auth_headers):
        """Test 2FA setup"""
        response = client.post(
            "/api/auth/2fa/setup",
            headers=auth_headers
        )
        assert response.status_code == status.HTTP_200_OK
        data = response.json()
        assert "secret" in data
        assert "qr_code_url" in data
        assert "backup_codes" in data

    def test_2fa_verify(self, client, auth_headers, test_user, db):
        """Test 2FA verification"""
        # Setup 2FA first
        setup_response = client.post(
            "/api/auth/2fa/setup",
            headers=auth_headers
        )
        secret = setup_response.json()["secret"]

        # Generate TOTP code
        import pyotp
        totp = pyotp.TOTP(secret)
        code = totp.now()

        # Verify code
        response = client.post(
            "/api/auth/2fa/verify",
            headers=auth_headers,
            json={"totp_code": code}
        )
        assert response.status_code == status.HTTP_200_OK

    def test_2fa_disable(self, client, auth_headers, test_user, db):
        """Test 2FA disable"""
        # Enable 2FA first
        setup_response = client.post(
            "/api/auth/2fa/setup",
            headers=auth_headers
        )
        secret = setup_response.json()["secret"]

        import pyotp
        totp = pyotp.TOTP(secret)
        code = totp.now()

        client.post(
            "/api/auth/2fa/verify",
            headers=auth_headers,
            json={"totp_code": code}
        )

        # Disable 2FA
        response = client.post(
            "/api/auth/2fa/disable",
            headers=auth_headers,
            json={"totp_code": code}
        )
        assert response.status_code == status.HTTP_200_OK
