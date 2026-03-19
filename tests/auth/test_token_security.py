"""
tests/auth/test_token_security.py

Security-focused tests for the auth/ package and hardened routes/auth.py.

Coverage:
  - Access token: creation, expiry, algorithm pinning, scope claims
  - Revocation list: add / check / Redis fallback (DB-only path)
  - Refresh token: rotation, replay detection, logout, logout-all
  - Argon2 hashing: hash format, verify, needs_rehash bcrypt upgrade path
  - Route fixes: logout revokes tokens, logout-all revokes all sessions,
    update-email no longer leaks tokens in JSON body
"""

import os
import uuid
from datetime import datetime, timedelta
from unittest.mock import patch

import pytest
from fastapi import status
from jose import jwt

# ─────────────────────────────────────────────────────────────────────────────
# Helpers shared by multiple test classes
# ─────────────────────────────────────────────────────────────────────────────

def _make_user(db, email=None, password="SecurePass123!", is_admin=False):
    """Create and persist a test User with an Argon2id or bcrypt hash."""
    from models.user import User
    from services.hashing_service import hash_password
    from datetime import datetime

    email = email or f"test_{uuid.uuid4().hex[:8]}@example.com"
    user = User(
        email=email,
        hashed_password=hash_password(password),
        email_verified=True,
        is_active=True,
        is_admin=is_admin,
        created_at=datetime.utcnow(),
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


# ══════════════════════════════════════════════════════════════════════════════
# 1. Token creation and structural validation
# ══════════════════════════════════════════════════════════════════════════════

class TestAccessTokenCreation:
    def test_token_contains_required_claims(self, db):
        from auth.token import create_access_token, ACCESS_SECRET, ALGORITHM
        user = _make_user(db)
        token = create_access_token(user)
        payload = jwt.decode(token, ACCESS_SECRET, algorithms=[ALGORITHM])
        assert payload["sub"] == str(user.id)
        assert payload["type"] == "access"
        assert "jti" in payload
        assert "exp" in payload
        assert "iat" in payload
        assert "nbf" in payload

    def test_token_includes_scopes_for_regular_user(self, db):
        from auth.token import create_access_token, ACCESS_SECRET, ALGORITHM
        user = _make_user(db)
        token = create_access_token(user)
        payload = jwt.decode(token, ACCESS_SECRET, algorithms=[ALGORITHM])
        assert "user" in payload["scopes"]
        assert "admin" not in payload["scopes"]

    def test_token_includes_admin_scope_for_admin(self, db):
        from auth.token import create_access_token, ACCESS_SECRET, ALGORITHM
        admin = _make_user(db, is_admin=True)
        token = create_access_token(admin)
        payload = jwt.decode(token, ACCESS_SECRET, algorithms=[ALGORITHM])
        assert "admin" in payload["scopes"]

    def test_each_token_has_unique_jti(self, db):
        from auth.token import create_access_token
        user = _make_user(db)
        tokens = [create_access_token(user) for _ in range(5)]
        from auth.token import ACCESS_SECRET, ALGORITHM
        jtis = [jwt.decode(t, ACCESS_SECRET, algorithms=[ALGORITHM])["jti"] for t in tokens]
        assert len(set(jtis)) == 5

    def test_token_expiry_is_bounded(self, db):
        from auth.token import create_access_token, ACCESS_EXPIRE_MINUTES, ACCESS_SECRET, ALGORITHM
        user = _make_user(db)
        token = create_access_token(user)
        payload = jwt.decode(token, ACCESS_SECRET, algorithms=[ALGORITHM])
        exp = datetime.utcfromtimestamp(payload["exp"])
        iat = datetime.utcfromtimestamp(payload["iat"])
        actual_minutes = (exp - iat).total_seconds() / 60
        assert actual_minutes <= ACCESS_EXPIRE_MINUTES + 1  # +1 for clock skew in test


# ══════════════════════════════════════════════════════════════════════════════
# 2. Token decode and algorithm pinning
# ══════════════════════════════════════════════════════════════════════════════

class TestAccessTokenDecoding:
    def test_valid_token_decodes_successfully(self, db):
        from auth.token import create_access_token, decode_access_token
        user = _make_user(db)
        token = create_access_token(user)
        payload = decode_access_token(token)
        assert payload["sub"] == str(user.id)

    def test_wrong_secret_raises_401(self, db):
        from auth.token import create_access_token
        from jose import jwt as jose_jwt
        from fastapi import HTTPException
        user = _make_user(db)
        # Sign with wrong secret
        payload = {"sub": str(user.id), "type": "access", "jti": "x", "exp": datetime.utcnow() + timedelta(hours=1)}
        bad_token = jose_jwt.encode(payload, "wrong-secret", algorithm="HS256")

        from auth.token import decode_access_token
        with pytest.raises(HTTPException) as exc_info:
            decode_access_token(bad_token)
        assert exc_info.value.status_code == 401

    def test_alg_none_attack_raises_401(self, db):
        """alg:none bypass must be rejected."""
        import base64, json
        from fastapi import HTTPException
        from auth.token import decode_access_token

        # Craft an unsigned token with alg=none
        header = base64.urlsafe_b64encode(json.dumps({"alg": "none", "typ": "JWT"}).encode()).rstrip(b"=")
        body = base64.urlsafe_b64encode(json.dumps({"sub": "1", "type": "access", "jti": "x"}).encode()).rstrip(b"=")
        none_token = f"{header.decode()}.{body.decode()}."

        with pytest.raises(HTTPException) as exc_info:
            decode_access_token(none_token)
        assert exc_info.value.status_code == 401

    def test_expired_token_raises_401(self, db):
        from auth.token import ACCESS_SECRET, ALGORITHM
        from fastapi import HTTPException
        from auth.token import decode_access_token
        past = datetime.utcnow() - timedelta(hours=2)
        payload = {"sub": "1", "type": "access", "jti": uuid.uuid4().hex, "exp": past, "iat": past, "nbf": past}
        token = jwt.encode(payload, ACCESS_SECRET, algorithm=ALGORITHM)
        with pytest.raises(HTTPException) as exc_info:
            decode_access_token(token)
        assert exc_info.value.status_code == 401

    def test_wrong_token_type_raises_401(self, db):
        """A refresh token must not be accepted as an access token."""
        from auth.token import ACCESS_SECRET, ALGORITHM
        from fastapi import HTTPException
        from auth.token import decode_access_token
        future = datetime.utcnow() + timedelta(hours=1)
        payload = {"sub": "1", "type": "refresh", "jti": uuid.uuid4().hex, "exp": future}
        token = jwt.encode(payload, ACCESS_SECRET, algorithm=ALGORITHM)
        with pytest.raises(HTTPException) as exc_info:
            decode_access_token(token)
        assert exc_info.value.status_code == 401


# ══════════════════════════════════════════════════════════════════════════════
# 3. Revocation list — DB-only path
# ══════════════════════════════════════════════════════════════════════════════

class TestRevocationList:
    def test_fresh_jti_is_not_revoked(self, db):
        from auth.revocation_list import is_revoked
        assert is_revoked(db, uuid.uuid4().hex) is False

    def test_add_to_revocation_list_marks_as_revoked(self, db):
        from auth.revocation_list import add_to_revocation_list, is_revoked
        jti = uuid.uuid4().hex
        add_to_revocation_list(
            db,
            jti=jti,
            token_type="access",
            expires_at=datetime.utcnow() + timedelta(minutes=15),
            user_id=None,
            reason="test",
        )
        assert is_revoked(db, jti) is True

    def test_add_is_idempotent(self, db):
        from auth.revocation_list import add_to_revocation_list, is_revoked
        jti = uuid.uuid4().hex
        exp = datetime.utcnow() + timedelta(minutes=15)
        for _ in range(3):
            add_to_revocation_list(db, jti=jti, token_type="access", expires_at=exp)
        assert is_revoked(db, jti) is True

    def test_purge_removes_expired_entries(self, db):
        from auth.revocation_list import add_to_revocation_list, purge_expired, is_revoked
        jti = uuid.uuid4().hex
        past = datetime.utcnow() - timedelta(minutes=1)
        add_to_revocation_list(db, jti=jti, token_type="access", expires_at=past)
        deleted = purge_expired(db)
        assert deleted >= 1
        assert is_revoked(db, jti) is False

    def test_revoke_access_token_adds_to_list(self, db):
        from auth.token import create_access_token, revoke_access_token, is_jti_revoked, decode_access_token
        user = _make_user(db)
        token = create_access_token(user)
        payload = decode_access_token(token)
        jti = payload["jti"]
        assert is_jti_revoked(db, jti) is False
        revoke_access_token(db, token)
        assert is_jti_revoked(db, jti) is True

    def test_revoked_token_rejected_by_get_current_user(self, client, db):
        from auth.token import create_access_token, revoke_access_token
        user = _make_user(db)
        token = create_access_token(user)
        revoke_access_token(db, token)

        resp = client.get("/api/auth/me", headers={"Authorization": f"Bearer {token}"})
        assert resp.status_code == 401

    def test_stats_returns_expected_shape(self, db):
        from auth.revocation_list import get_revocation_stats
        stats = get_revocation_stats(db)
        assert "total_revoked" in stats
        assert "revoked_last_hour" in stats
        assert "redis_enabled" in stats


# ══════════════════════════════════════════════════════════════════════════════
# 4. Refresh token rotation
# ══════════════════════════════════════════════════════════════════════════════

class TestRefreshTokenRotation:
    def test_rotate_returns_new_tokens(self, client, db):
        """POST /api/auth/refresh issues new tokens and sets cookies."""
        user = _make_user(db)
        resp = client.post("/api/auth/login", json={"email": user.email, "password": "SecurePass123!"})
        assert resp.status_code == 200
        assert "refresh_token" in resp.cookies

        csrf = resp.json()["csrf_token"]
        refresh_resp = client.post("/api/auth/refresh", headers={"X-CSRF-Token": csrf})
        assert refresh_resp.status_code == 200
        assert "access_token" in refresh_resp.cookies
        assert "refresh_token" in refresh_resp.cookies

    def test_old_refresh_token_rejected_after_rotation(self, client, db):
        """After rotation the old token must be invalidated."""
        user = _make_user(db)
        resp = client.post("/api/auth/login", json={"email": user.email, "password": "SecurePass123!"})
        assert resp.status_code == 200
        old_refresh = resp.cookies.get("refresh_token")
        csrf = resp.json()["csrf_token"]
        assert old_refresh

        client.post("/api/auth/refresh", headers={"X-CSRF-Token": csrf})

        # Try to use old token — must fail
        client.cookies.clear()
        client.cookies.set("refresh_token", old_refresh)
        replay_resp = client.post(
            "/api/auth/refresh",
            headers={"Authorization": f"Bearer {old_refresh}"},
        )
        assert replay_resp.status_code == 401

    def test_replay_detection_invalidates_chain(self, client, db):
        """Presenting a revoked refresh token triggers replay detection (401)."""
        from auth.refresh_tokens import create_refresh_token, revoke_refresh_token_by_value
        user = _make_user(db)
        refresh_token = create_refresh_token(user, db, ip_address="127.0.0.1")
        # Simulate rotation — revoke it
        revoke_refresh_token_by_value(db, refresh_token, reason="rotated")
        # Now replay should fail
        client.cookies.clear()
        resp = client.post(
            "/api/auth/refresh",
            headers={"Authorization": f"Bearer {refresh_token}"},
        )
        assert resp.status_code == 401


# ══════════════════════════════════════════════════════════════════════════════
# 5. Logout — token revocation
# ══════════════════════════════════════════════════════════════════════════════

def _login(client, email, password="SecurePass123!"):
    """Login and return (access_token, csrf_token)."""
    resp = client.post("/api/auth/login", json={"email": email, "password": password})
    data = resp.json()
    csrf = data.get("csrf_token") or resp.cookies.get("csrf_token", "")
    access = data.get("access_token") or resp.cookies.get("access_token", "")
    return access, csrf


class TestLogout:
    def test_logout_clears_cookies(self, client, db):
        user = _make_user(db)
        _, csrf = _login(client, user.email)
        resp = client.post("/api/auth/logout", headers={"X-CSRF-Token": csrf})
        assert resp.status_code == 200
        # Cookies should be deleted (empty string or absent)
        assert resp.cookies.get("access_token", "") == ""

    def test_access_token_invalid_after_logout(self, client, db):
        """After logout the access token JTI must be blacklisted."""
        user = _make_user(db)
        token, csrf = _login(client, user.email)

        client.post("/api/auth/logout", headers={"X-CSRF-Token": csrf})

        # The token is now revoked — /me must reject it
        resp = client.get("/api/auth/me", headers={"Authorization": f"Bearer {token}"})
        assert resp.status_code == 401

    def test_logout_without_token_returns_200(self, client, db):
        """Unauthenticated logout must succeed (idempotent — no cookies, no CSRF needed)."""
        client.cookies.clear()
        # No cookies → CSRF middleware passes (no access_token cookie → no CSRF enforcement)
        resp = client.post("/api/auth/logout")
        assert resp.status_code == 200


# ══════════════════════════════════════════════════════════════════════════════
# 6. Logout-all — revokes all sessions
# ══════════════════════════════════════════════════════════════════════════════

class TestLogoutAll:
    def test_logout_all_revokes_all_sessions(self, client, db):
        """All active refresh tokens must be revoked after logout-all."""
        from auth.refresh_tokens import create_refresh_token, get_active_sessions
        user = _make_user(db)

        for _ in range(3):
            create_refresh_token(user, db, ip_address="127.0.0.1")

        _, csrf = _login(client, user.email)

        resp = client.post("/api/auth/logout-all", headers={"X-CSRF-Token": csrf})
        assert resp.status_code == 200
        data = resp.json()
        assert data["sessions_revoked"] >= 1

        remaining = get_active_sessions(db, user.id)
        assert remaining == []

    def test_logout_all_requires_authentication(self, client, db):
        """logout-all must require a valid access token."""
        client.cookies.clear()
        resp = client.post("/api/auth/logout-all")
        assert resp.status_code == 401


# ══════════════════════════════════════════════════════════════════════════════
# 7. update-email — no token leak in JSON body
# ══════════════════════════════════════════════════════════════════════════════

class TestUpdateEmail:
    def test_update_email_does_not_leak_tokens_in_body(self, client, db):
        """JSON response must NOT contain access_token or refresh_token."""
        user = _make_user(db)
        _, csrf = _login(client, user.email)

        resp = client.post(
            "/api/auth/update-email",
            json={"new_email": f"updated_{uuid.uuid4().hex[:6]}@example.com", "password": "SecurePass123!"},
            headers={"X-CSRF-Token": csrf},
        )
        assert resp.status_code == 200
        body = resp.json()
        assert "access_token" not in body
        assert "refresh_token" not in body

    def test_update_email_clears_auth_cookies(self, client, db):
        """Credential changes must clear the current browser session."""
        user = _make_user(db)
        _, csrf = _login(client, user.email)

        resp = client.post(
            "/api/auth/update-email",
            json={"new_email": f"new_{uuid.uuid4().hex[:6]}@example.com", "password": "SecurePass123!"},
            headers={"X-CSRF-Token": csrf},
        )
        assert resp.status_code == 200
        assert resp.cookies.get("access_token", "") == ""
        assert resp.cookies.get("refresh_token", "") == ""

    def test_old_token_revoked_after_email_change(self, client, db):
        """The previous access token must be blacklisted after email change."""
        user = _make_user(db)
        old_token, csrf = _login(client, user.email)

        client.post(
            "/api/auth/update-email",
            json={"new_email": f"chg_{uuid.uuid4().hex[:6]}@example.com", "password": "SecurePass123!"},
            headers={"X-CSRF-Token": csrf},
        )

        # Old token must now be rejected
        resp = client.get("/api/auth/me", headers={"Authorization": f"Bearer {old_token}"})
        assert resp.status_code == 401

    def test_old_refresh_token_rejected_after_email_change(self, client, db):
        """Email changes must revoke every outstanding refresh session."""
        user = _make_user(db)
        _, csrf = _login(client, user.email)
        old_refresh = client.cookies.get("refresh_token")

        resp = client.post(
            "/api/auth/update-email",
            json={"new_email": f"chg_{uuid.uuid4().hex[:6]}@example.com", "password": "SecurePass123!"},
            headers={"X-CSRF-Token": csrf},
        )
        assert resp.status_code == 200

        client.cookies.clear()
        refresh_resp = client.post(
            "/api/auth/refresh",
            headers={"Authorization": f"Bearer {old_refresh}"},
        )
        assert refresh_resp.status_code == 401


class TestUpdatePassword:
    def test_password_change_revokes_current_access_token(self, client, db):
        user = _make_user(db)
        old_access, csrf = _login(client, user.email)

        resp = client.post(
            "/api/auth/update-password",
            json={"current_password": "SecurePass123!", "new_password": "ChangedPass123!"},
            headers={"X-CSRF-Token": csrf},
        )
        assert resp.status_code == 200

        me = client.get("/api/auth/me", headers={"Authorization": f"Bearer {old_access}"})
        assert me.status_code == 401

    def test_password_change_rejects_old_refresh_token(self, client, db):
        user = _make_user(db)
        _, csrf = _login(client, user.email)
        old_refresh = client.cookies.get("refresh_token")

        resp = client.post(
            "/api/auth/update-password",
            json={"current_password": "SecurePass123!", "new_password": "ChangedPass123!"},
            headers={"X-CSRF-Token": csrf},
        )
        assert resp.status_code == 200

        client.cookies.clear()
        refresh_resp = client.post(
            "/api/auth/refresh",
            headers={"Authorization": f"Bearer {old_refresh}"},
        )
        assert refresh_resp.status_code == 401

    def test_password_change_requires_new_login(self, client, db):
        user = _make_user(db)
        _, csrf = _login(client, user.email)

        resp = client.post(
            "/api/auth/update-password",
            json={"current_password": "SecurePass123!", "new_password": "ChangedPass123!"},
            headers={"X-CSRF-Token": csrf},
        )
        assert resp.status_code == 200

        old_login = client.post(
            "/api/auth/login",
            json={"email": user.email, "password": "SecurePass123!"},
        )
        assert old_login.status_code == 401

        new_login = client.post(
            "/api/auth/login",
            json={"email": user.email, "password": "ChangedPass123!"},
        )
        assert new_login.status_code == 200
        assert "refresh_token" in new_login.json()


# ══════════════════════════════════════════════════════════════════════════════
# 8. Admin scope enforcement
# ══════════════════════════════════════════════════════════════════════════════

class TestAdminScopeEnforcement:
    def test_require_admin_rejects_regular_user(self, db):
        from auth.token import create_access_token, require_admin, get_current_user
        from fastapi import HTTPException
        user = _make_user(db, is_admin=False)
        # Directly test the dependency
        with pytest.raises(HTTPException) as exc_info:
            require_admin(current_user=user)
        assert exc_info.value.status_code == 403

    def test_require_admin_passes_for_admin(self, db):
        from auth.token import require_admin
        admin = _make_user(db, is_admin=True)
        result = require_admin(current_user=admin)
        assert result is admin

    def test_admin_scope_in_token_for_admin_user(self, db):
        from auth.token import create_access_token, ACCESS_SECRET, ALGORITHM
        admin = _make_user(db, is_admin=True)
        token = create_access_token(admin)
        payload = jwt.decode(token, ACCESS_SECRET, algorithms=[ALGORITHM])
        assert "admin" in payload.get("scopes", [])


# ══════════════════════════════════════════════════════════════════════════════
# 9. Argon2 password hashing
# ══════════════════════════════════════════════════════════════════════════════

class TestArgon2Hashing:
    def test_hash_produces_argon2id_format(self):
        from services.hashing_service import hash_password, _HAS_ARGON2
        if not _HAS_ARGON2:
            pytest.skip("argon2-cffi not available")
        h = hash_password("SecurePass123!")
        assert h.startswith("$argon2id$") or h.startswith("$argon2")

    def test_correct_password_verifies(self):
        from services.hashing_service import hash_password, verify_password
        h = hash_password("CorrectHorse77!")
        assert verify_password("CorrectHorse77!", h) is True

    def test_wrong_password_fails_verification(self):
        from services.hashing_service import hash_password, verify_password
        h = hash_password("RightPassword1!")
        assert verify_password("WrongPassword1!", h) is False

    def test_bcrypt_hash_still_verifies(self):
        """Existing bcrypt hashes must work through the verify_password function."""
        from services.hashing_service import verify_password
        from passlib.context import CryptContext
        ctx = CryptContext(schemes=["bcrypt"], deprecated="auto", bcrypt__rounds=4)
        bcrypt_hash = ctx.hash("LegacyPass99!")
        assert verify_password("LegacyPass99!", bcrypt_hash) is True

    def test_bcrypt_hash_needs_rehash(self):
        """needs_rehash must return True for a bcrypt hash when Argon2 is available."""
        from services.hashing_service import needs_rehash, _HAS_ARGON2
        if not _HAS_ARGON2:
            pytest.skip("argon2-cffi not available")
        from passlib.context import CryptContext
        ctx = CryptContext(schemes=["bcrypt"], deprecated="auto", bcrypt__rounds=4)
        bcrypt_hash = ctx.hash("AnyPass123!")
        assert needs_rehash(bcrypt_hash) is True

    def test_argon2_hash_does_not_need_rehash(self):
        """A freshly-minted Argon2id hash must not need rehashing."""
        from services.hashing_service import hash_password, needs_rehash, _HAS_ARGON2
        if not _HAS_ARGON2:
            pytest.skip("argon2-cffi not available")
        h = hash_password("FreshArgon2Pass9!")
        assert needs_rehash(h) is False

    def test_empty_password_returns_false(self):
        from services.hashing_service import verify_password, hash_password
        h = hash_password("ValidPass1!")
        assert verify_password("", h) is False

    def test_password_over_max_length_raises(self):
        from services.hashing_service import hash_password
        with pytest.raises(ValueError):
            hash_password("a" * 1001)


# ══════════════════════════════════════════════════════════════════════════════
# 10. Refresh token lifecycle (create / active sessions / revoke-all)
# ══════════════════════════════════════════════════════════════════════════════

class TestRefreshTokenLifecycle:
    def test_create_persists_session_record(self, db):
        from auth.refresh_tokens import create_refresh_token, get_active_sessions
        user = _make_user(db)
        create_refresh_token(user, db, ip_address="10.0.0.1", user_agent="TestAgent/1.0")
        sessions = get_active_sessions(db, user.id)
        assert len(sessions) == 1
        assert sessions[0]["ip_address"] == "10.0.0.1"

    def test_get_active_sessions_excludes_revoked(self, db):
        from auth.refresh_tokens import create_refresh_token, get_active_sessions, revoke_refresh_token_by_value
        user = _make_user(db)
        token = create_refresh_token(user, db)
        revoke_refresh_token_by_value(db, token)
        sessions = get_active_sessions(db, user.id)
        assert sessions == []

    def test_revoke_all_clears_all_sessions(self, db):
        from auth.refresh_tokens import create_refresh_token, revoke_all_refresh_tokens, get_active_sessions
        user = _make_user(db)
        for _ in range(4):
            create_refresh_token(user, db)
        count = revoke_all_refresh_tokens(db, user.id)
        assert count == 4
        assert get_active_sessions(db, user.id) == []

    def test_expired_token_rejected(self, db):
        """A refresh token past its expiry must not rotate."""
        from auth.refresh_tokens import REFRESH_SECRET
        from auth.token import ALGORITHM
        from fastapi import HTTPException
        from auth.refresh_tokens import _decode_refresh_token, _load_session
        from models.auth_refresh_token import AuthRefreshToken

        # Create a token that expired in the past
        past = datetime.utcnow() - timedelta(hours=1)
        jti = uuid.uuid4().hex
        payload = {"sub": "99999", "type": "refresh", "jti": jti, "exp": past, "iat": past, "nbf": past}
        token = jwt.encode(payload, REFRESH_SECRET, algorithm=ALGORITHM)

        with pytest.raises(HTTPException) as exc_info:
            _decode_refresh_token(token)
        assert exc_info.value.status_code == 401
