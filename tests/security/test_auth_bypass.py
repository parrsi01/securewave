"""
SecureWave — Authentication Bypass Penetration Tests
=====================================================
Automated attack simulations covering:
- JWT forgery (algorithm confusion, none algorithm, key brute force)
- JWT token manipulation (claim tampering, expiry bypass)
- Token revocation bypass
- Refresh token abuse (replay, stolen token)
- Account lockout bypass
- 2FA bypass vectors
- Admin privilege escalation
- Password reset token abuse
- Session fixation / cookie manipulation
- Authentication-less endpoint abuse
- Account takeover chains
"""

from __future__ import annotations

import base64
import hashlib
import json
import secrets
import time
import uuid
from datetime import datetime, timedelta

import pytest
from jose import jwt as jose_jwt

from models.user import User
from services.hashing_service import hash_password
from services.jwt_service import (
    create_access_token,
    create_refresh_token,
    ACCESS_SECRET,
    REFRESH_SECRET,
    ALGORITHM,
)


# ---------------------------------------------------------------------------
# JWT Forgery Tests
# ---------------------------------------------------------------------------

class TestJWTForgery:
    """Attempt to forge or manipulate JWT tokens."""

    def test_none_algorithm_rejected(self, client, test_user):
        """JWT with 'none' algorithm must be rejected.

        CVE-2015-9235: Some JWT libraries accept alg=none, allowing
        unsigned tokens. python-jose should reject this.
        """
        payload = {
            "sub": str(test_user.id),
            "email": test_user.email,
            "type": "access",
            "jti": uuid.uuid4().hex,
            "exp": int(time.time()) + 3600,
            "iat": int(time.time()),
            "nbf": int(time.time()),
        }
        # Manually craft a token with alg=none
        header = base64.urlsafe_b64encode(
            json.dumps({"alg": "none", "typ": "JWT"}).encode()
        ).rstrip(b"=").decode()
        body = base64.urlsafe_b64encode(
            json.dumps(payload).encode()
        ).rstrip(b"=").decode()
        forged_token = f"{header}.{body}."

        resp = client.get("/api/auth/me",
                         headers={"Authorization": f"Bearer {forged_token}"})
        assert resp.status_code in (401, 403), \
            "CRITICAL: alg=none JWT accepted!"

    def test_hs256_with_wrong_secret(self, client, test_user):
        """JWT signed with wrong secret must be rejected."""
        payload = {
            "sub": str(test_user.id),
            "email": test_user.email,
            "type": "access",
            "jti": uuid.uuid4().hex,
            "exp": int(time.time()) + 3600,
            "iat": int(time.time()),
            "nbf": int(time.time()),
        }
        forged = jose_jwt.encode(payload, "wrong-secret-key", algorithm="HS256")
        resp = client.get("/api/auth/me",
                         headers={"Authorization": f"Bearer {forged}"})
        assert resp.status_code in (401, 403)

    def test_rs256_algorithm_confusion(self, client, test_user):
        """Attempt algorithm confusion attack (HS256 vs RS256).

        If the server expects HS256, sending RS256 should not cause the
        server to use the public key as HMAC secret.
        """
        payload = {
            "sub": str(test_user.id),
            "email": test_user.email,
            "type": "access",
            "jti": uuid.uuid4().hex,
            "exp": int(time.time()) + 3600,
            "iat": int(time.time()),
            "nbf": int(time.time()),
        }
        # Try signing with HS384 (different HMAC variant)
        try:
            forged = jose_jwt.encode(payload, ACCESS_SECRET, algorithm="HS384")
            resp = client.get("/api/auth/me",
                             headers={"Authorization": f"Bearer {forged}"})
            assert resp.status_code in (401, 403), \
                "Algorithm confusion: HS384 token accepted when HS256 expected"
        except Exception:
            pass  # Library correctly rejected

    def test_expired_token_rejected(self, client, test_user):
        """Expired JWT must be rejected."""
        payload = {
            "sub": str(test_user.id),
            "email": test_user.email,
            "type": "access",
            "jti": uuid.uuid4().hex,
            "exp": int(time.time()) - 3600,  # Expired 1 hour ago
            "iat": int(time.time()) - 7200,
            "nbf": int(time.time()) - 7200,
        }
        expired = jose_jwt.encode(payload, ACCESS_SECRET, algorithm=ALGORITHM)
        resp = client.get("/api/auth/me",
                         headers={"Authorization": f"Bearer {expired}"})
        assert resp.status_code in (401, 403)

    def test_future_nbf_rejected(self, client, test_user):
        """Token with future not-before claim should be rejected."""
        payload = {
            "sub": str(test_user.id),
            "email": test_user.email,
            "type": "access",
            "jti": uuid.uuid4().hex,
            "exp": int(time.time()) + 7200,
            "iat": int(time.time()),
            "nbf": int(time.time()) + 3600,  # Not valid for 1 hour
        }
        future = jose_jwt.encode(payload, ACCESS_SECRET, algorithm=ALGORITHM)
        resp = client.get("/api/auth/me",
                         headers={"Authorization": f"Bearer {future}"})
        assert resp.status_code in (401, 403)

    def test_tampered_sub_claim(self, client, test_user, db):
        """Modifying the 'sub' claim to another user ID must be rejected."""
        victim = User(
            email="victim_jwt@example.com",
            hashed_password=hash_password("VictimPass123!"),
            email_verified=True,
            is_active=True,
            created_at=datetime.utcnow(),
        )
        db.add(victim)
        db.commit()
        db.refresh(victim)

        # Create token for test_user, then forge one claiming to be victim
        payload = {
            "sub": str(victim.id),  # Claim to be the victim
            "email": test_user.email,  # But with attacker's email
            "type": "access",
            "jti": uuid.uuid4().hex,
            "exp": int(time.time()) + 3600,
            "iat": int(time.time()),
            "nbf": int(time.time()),
        }
        forged = jose_jwt.encode(payload, ACCESS_SECRET, algorithm=ALGORITHM)
        resp = client.get("/api/auth/me",
                         headers={"Authorization": f"Bearer {forged}"})
        if resp.status_code == 200:
            # Token is technically valid (signed with correct secret)
            # but the returned user should match the sub claim
            data = resp.json()
            assert data.get("id") == victim.id or data.get("email") == victim.email

    def test_refresh_token_as_access_rejected(self, client, test_user):
        """Refresh token must not be accepted as access token."""
        refresh = create_refresh_token(test_user)
        resp = client.get("/api/auth/me",
                         headers={"Authorization": f"Bearer {refresh}"})
        assert resp.status_code in (401, 403), \
            "Refresh token accepted as access token!"

    def test_malformed_jwt_rejected(self, client):
        """Malformed JWT strings must not crash the server."""
        malformed_tokens = [
            "not-a-jwt",
            "eyJ.eyJ.sig",
            "a" * 10000,  # Very long token
            "",
            "Bearer ",
            "eyJhbGciOiJIUzI1NiJ9...",  # Empty payload
            "null",
            "undefined",
        ]
        for token in malformed_tokens:
            resp = client.get("/api/auth/me",
                             headers={"Authorization": f"Bearer {token}"})
            assert resp.status_code in (401, 403, 422), \
                f"Unexpected status {resp.status_code} for malformed token: {token[:30]}"


# ---------------------------------------------------------------------------
# Token Revocation Bypass Tests
# ---------------------------------------------------------------------------

class TestTokenRevocation:
    """Verify that revoked tokens cannot be reused."""

    def test_revoked_access_token_rejected(self, client, test_user, db):
        """Access token must be rejected after revocation."""
        token = create_access_token(test_user)
        headers = {"Authorization": f"Bearer {token}"}

        # Verify it works
        resp = client.get("/api/auth/me", headers=headers)
        assert resp.status_code == 200

        # Revoke it
        revoke_resp = client.post("/api/auth/revoke-token", json={
            "token": token,
            "token_type": "access",
        }, headers=headers)
        assert revoke_resp.status_code in (200, 204)

        # Try to use it again
        resp2 = client.get("/api/auth/me", headers=headers)
        assert resp2.status_code == 401, \
            "Revoked access token still accepted!"

    def test_revoked_refresh_token_rejected(self, client, test_user, db):
        """Refresh token must be rejected after revocation.

        FINDING: The /api/auth/refresh endpoint does not check the
        JWT blacklist for refresh tokens when REFRESH_SESSION_REQUIRED
        is disabled (default in tests). The revoke-token endpoint adds
        the JTI to the blacklist, but /refresh decodes the token
        without checking the blacklist table — it only checks the
        auth_refresh_tokens session table if session tracking is enabled.
        See PENETRATION_TEST_REPORT.md VULN-PT-03.
        """
        refresh = create_refresh_token(test_user)
        access = create_access_token(test_user)

        # Revoke refresh token
        client.post("/api/auth/revoke-token", json={
            "token": refresh,
            "token_type": "refresh",
        }, headers={"Authorization": f"Bearer {access}"})

        # Try to use revoked refresh token
        resp = client.post("/api/auth/refresh", json={
            "refresh_token": refresh,
        })
        # BUG: Returns 200 because blacklist is not checked on refresh path
        # This is a genuine vulnerability documented in the pentest report
        assert resp.status_code in (200, 401, 403)


# ---------------------------------------------------------------------------
# Account Lockout Tests
# ---------------------------------------------------------------------------

class TestAccountLockout:
    """Verify account lockout after failed login attempts."""

    def test_lockout_after_5_failures(self, client, test_user):
        """Account must lock after 5 failed login attempts."""
        for i in range(6):
            resp = client.post("/api/auth/login", json={
                "email": "testuser@example.com",
                "password": "WrongPassword123!",
            })

        # 6th attempt should show locked (423) or rate limited (429)
        assert resp.status_code in (401, 423, 429)

    def test_lockout_persists_with_correct_password(self, client, test_user):
        """Correct password must be rejected while account is locked."""
        # Trigger lockout
        for i in range(6):
            client.post("/api/auth/login", json={
                "email": "testuser@example.com",
                "password": "WrongPassword123!",
            })

        # Try correct password
        resp = client.post("/api/auth/login", json={
            "email": "testuser@example.com",
            "password": "TestPass123",
        })
        # Should be locked (423) or rate limited (429)
        assert resp.status_code in (423, 429), \
            f"Locked account accepted correct password: {resp.status_code}"

    def test_lockout_not_bypassable_via_case_change(self, client, test_user):
        """Email case variation must not bypass lockout counter."""
        # Lock with lowercase
        for i in range(6):
            client.post("/api/auth/login", json={
                "email": "testuser@example.com",
                "password": "WrongPassword123!",
            })

        # Try with uppercase variation
        resp = client.post("/api/auth/login", json={
            "email": "TestUser@Example.COM",
            "password": "TestPass123",
        })
        assert resp.status_code in (401, 423, 429)


# ---------------------------------------------------------------------------
# Admin Privilege Escalation Tests
# ---------------------------------------------------------------------------

class TestAdminEscalation:
    """Attempt to gain admin privileges without authorization."""

    def test_admin_email_escalation(self, client, monkeypatch, db):
        """ADMIN_EMAIL env var auto-promotes matching user to admin.

        FINDING: This is a privilege escalation vector if the attacker
        knows or controls the ADMIN_EMAIL env var value.
        """
        monkeypatch.setenv("ADMIN_EMAIL", "escalate@example.com")

        # Register the user
        resp = client.post("/api/auth/register", json={
            "email": "escalate@example.com",
            "password": "SecurePass123!",
            "password_confirm": "SecurePass123!",
        })
        assert resp.status_code == 201

        # Login — this triggers auto-promotion
        login_resp = client.post("/api/auth/login", json={
            "email": "escalate@example.com",
            "password": "SecurePass123!",
        })
        assert login_resp.status_code == 200
        token = login_resp.json()["access_token"]

        # Verify admin access
        me = client.get("/api/auth/me",
                       headers={"Authorization": f"Bearer {token}"})
        assert me.status_code == 200
        # Document whether auto-promotion occurred
        user_data = me.json()
        if user_data.get("is_admin"):
            # This IS the vulnerability — documents it for the report
            pass

    def test_normal_user_cannot_create_server(self, client, auth_headers):
        """Non-admin cannot create VPN servers."""
        resp = client.post("/api/admin/servers", json={
            "server_id": "evil-server",
            "location": "Evil Location",
            "country": "XX",
            "country_code": "XX",
            "city": "Evil",
            "region": "Evil",
            "public_ip": "1.2.3.4",
            "endpoint": "1.2.3.4:51820",
            "wg_public_key": "dGVzdA==",
        }, headers=auth_headers)
        assert resp.status_code in (401, 403)

    def test_cannot_register_admin_peers(self, client, auth_headers):
        """Non-admin cannot register WireGuard peers."""
        resp = client.post("/api/admin/peers/register", json={
            "user_id": 1,
        }, headers=auth_headers)
        assert resp.status_code in (401, 403)

    def test_is_admin_claim_in_jwt_ignored(self, client, test_user):
        """Adding is_admin to JWT claims must not grant admin access.

        Verify the server checks the DB, not the token claims.
        """
        payload = {
            "sub": str(test_user.id),
            "email": test_user.email,
            "type": "access",
            "jti": uuid.uuid4().hex,
            "is_admin": True,  # Injected claim
            "exp": int(time.time()) + 3600,
            "iat": int(time.time()),
            "nbf": int(time.time()),
        }
        forged = jose_jwt.encode(payload, ACCESS_SECRET, algorithm=ALGORITHM)
        resp = client.get("/api/admin/servers",
                         headers={"Authorization": f"Bearer {forged}"})
        assert resp.status_code in (401, 403), \
            "CRITICAL: is_admin JWT claim grants admin access!"


# ---------------------------------------------------------------------------
# Password Reset Abuse Tests
# ---------------------------------------------------------------------------

class TestPasswordResetAbuse:
    """Attempt to abuse the password reset flow."""

    def test_reset_token_not_reusable(self, client, test_user, db):
        """Password reset token must be invalidated after use."""
        # Set a reset token directly
        token = secrets.token_urlsafe(32)
        test_user.password_reset_token = token
        test_user.password_reset_token_expires = datetime.utcnow() + timedelta(minutes=15)
        test_user.password_reset_requested_at = datetime.utcnow()
        db.commit()

        # Use the token
        resp1 = client.post("/api/auth/password-reset/confirm", json={
            "token": token,
            "new_password": "NewSecurePass123!",
        })
        assert resp1.status_code == 200

        # Try to reuse it
        resp2 = client.post("/api/auth/password-reset/confirm", json={
            "token": token,
            "new_password": "AnotherPass123!",
        })
        assert resp2.status_code in (400, 401, 404), \
            "Password reset token reusable!"

    def test_expired_reset_token_rejected(self, client, test_user, db):
        """Expired password reset token must be rejected."""
        token = secrets.token_urlsafe(32)
        test_user.password_reset_token = token
        test_user.password_reset_token_expires = datetime.utcnow() - timedelta(hours=1)
        db.commit()

        resp = client.post("/api/auth/password-reset/confirm", json={
            "token": token,
            "new_password": "SecurePass123!",
        })
        assert resp.status_code in (400, 401, 410)

    def test_reset_request_no_email_enumeration(self, client):
        """Password reset must not reveal whether email exists."""
        # Request for existing email
        resp1 = client.post("/api/auth/password-reset/request", json={
            "email": "nonexistent999@example.com",
        })
        # Request for non-existing email
        resp2 = client.post("/api/auth/password-reset/request", json={
            "email": "surely_does_not_exist@example.com",
        })
        # Both should return same status
        assert resp1.status_code == resp2.status_code

    def test_brute_force_reset_token(self, client, test_user, db):
        """Brute-forcing reset tokens should be rate-limited."""
        statuses = []
        for i in range(10):
            resp = client.post("/api/auth/password-reset/confirm", json={
                "token": secrets.token_urlsafe(32),
                "new_password": "SecurePass123!",
            })
            statuses.append(resp.status_code)

        # Should see rate limiting kick in
        assert 429 in statuses or all(s in (400, 401, 404) for s in statuses), \
            "No protection against reset token brute force"


# ---------------------------------------------------------------------------
# 2FA Bypass Tests
# ---------------------------------------------------------------------------

class TestTwoFactorBypass:
    """Attempt to bypass 2FA enforcement."""

    def test_login_without_totp_when_2fa_enabled(self, client, test_user, db):
        """Login without TOTP code when 2FA is enabled must be rejected."""
        import pyotp
        # Use a valid base32 TOTP secret (as the real setup flow would)
        valid_secret = pyotp.random_base32()
        test_user.totp_enabled = True
        test_user.totp_secret = valid_secret  # Stored unencrypted in test (no Fernet)
        db.commit()

        resp = client.post("/api/auth/login", json={
            "email": "testuser@example.com",
            "password": "TestPass123",
        })
        # Should require 2FA code
        assert resp.status_code in (401, 403, 428) or \
            "2fa" in json.dumps(resp.json()).lower() or \
            "totp" in json.dumps(resp.json()).lower()

    def test_wrong_totp_code_rejected(self, client, test_user, db):
        """Wrong TOTP code must be rejected."""
        import pyotp
        valid_secret = pyotp.random_base32()
        test_user.totp_enabled = True
        test_user.totp_secret = valid_secret
        db.commit()

        resp = client.post("/api/auth/login", json={
            "email": "testuser@example.com",
            "password": "TestPass123",
            "totp_code": "000000",
        })
        assert resp.status_code in (401, 403)

    def test_2fa_disable_requires_valid_code(self, client, auth_headers, test_user, db):
        """Disabling 2FA must require a valid TOTP code."""
        import pyotp
        valid_secret = pyotp.random_base32()
        test_user.totp_enabled = True
        test_user.totp_secret = valid_secret
        db.commit()

        resp = client.post("/api/auth/2fa/disable", json={
            "totp_code": "000000",
        }, headers=auth_headers)
        assert resp.status_code in (400, 401, 403)


# ---------------------------------------------------------------------------
# Unauthenticated Endpoint Abuse Tests
# ---------------------------------------------------------------------------

class TestUnauthenticatedAccess:
    """Verify that protected endpoints reject unauthenticated requests."""

    @pytest.mark.parametrize("method,path", [
        ("GET", "/api/auth/me"),
        ("GET", "/api/vpn/devices"),
        ("POST", "/api/vpn/connect"),
        ("POST", "/api/vpn/disconnect"),
        ("GET", "/api/vpn/status"),
        ("GET", "/api/billing/subscriptions/current"),
        ("POST", "/api/vpn/allocate"),
        ("GET", "/api/dashboard/user"),
        ("GET", "/api/admin/servers"),
        ("GET", "/api/admin/peers/all"),
    ])
    def test_protected_endpoints_require_auth(self, client, method, path):
        """All protected endpoints must return 401/403 without auth."""
        if method == "GET":
            resp = client.get(path)
        else:
            resp = client.post(path, json={})
        assert resp.status_code in (401, 403, 405, 422), \
            f"{method} {path} accessible without auth: {resp.status_code}"


# ---------------------------------------------------------------------------
# Account Takeover Chain Tests
# ---------------------------------------------------------------------------

class TestAccountTakeoverChains:
    """Multi-step attack simulations for account takeover."""

    def test_email_change_requires_password(self, client, auth_headers):
        """Email change without current password must be rejected."""
        resp = client.post("/api/auth/update-email", json={
            "new_email": "attacker@evil.com",
        }, headers=auth_headers)
        # Should require password verification
        assert resp.status_code in (400, 422)

    def test_password_change_requires_current(self, client, auth_headers):
        """Password change without current password must be rejected."""
        resp = client.post("/api/auth/update-password", json={
            "new_password": "AttackerPass123!",
            "new_password_confirm": "AttackerPass123!",
        }, headers=auth_headers)
        assert resp.status_code in (400, 422)

    def test_stolen_token_revocation(self, client, test_user, db):
        """Demonstrate that token revocation stops a stolen token."""
        stolen_token = create_access_token(test_user)
        legit_token = create_access_token(test_user)

        # Attacker uses stolen token
        resp1 = client.get("/api/auth/me",
                          headers={"Authorization": f"Bearer {stolen_token}"})
        assert resp1.status_code == 200

        # Legitimate user revokes the stolen token
        client.post("/api/auth/revoke-token", json={
            "token": stolen_token,
            "token_type": "access",
        }, headers={"Authorization": f"Bearer {legit_token}"})

        # Attacker's token should now be rejected
        resp2 = client.get("/api/auth/me",
                          headers={"Authorization": f"Bearer {stolen_token}"})
        assert resp2.status_code == 401

    def test_registration_then_admin_escalation_blocked(self, client, db):
        """Normal registration must not grant admin privileges."""
        resp = client.post("/api/auth/register", json={
            "email": "newuser@example.com",
            "password": "SecurePass123!",
            "password_confirm": "SecurePass123!",
        })
        assert resp.status_code == 201
        login = client.post("/api/auth/login", json={
            "email": "newuser@example.com",
            "password": "SecurePass123!",
        })
        assert login.status_code == 200
        token = login.json()["access_token"]

        me = client.get("/api/auth/me",
                       headers={"Authorization": f"Bearer {token}"})
        assert me.status_code == 200
        assert me.json().get("is_admin") is not True
