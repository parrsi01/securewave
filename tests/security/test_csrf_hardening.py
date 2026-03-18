"""
CSRF hardening tests for SecureWave.

Covers:
- Pure M2M API client (Bearer only, no cookie) is CSRF-exempt.
- Browser session (cookie only, no Bearer) requires valid CSRF token.
- Dual-credential request (cookie + Bearer) is treated as browser — CSRF applies.
- Correct double-submit pair passes; mismatched pair is rejected.
- Safe HTTP methods (GET, HEAD, OPTIONS) are always exempt.
- Exempt paths (login, register, etc.) bypass CSRF unconditionally.
"""

import pytest


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

PROTECTED_PATH = "/api/vpn/connect"
EXEMPT_PATH = "/api/auth/login"

_VALID_CSRF = "valid-csrf-token-abc123"
_WRONG_CSRF = "wrong-csrf-token-xyz999"


def _post(client, path, *, cookies=None, headers=None, json=None):
    """Thin wrapper to keep test bodies clean."""
    return client.post(path, cookies=cookies or {}, headers=headers or {}, json=json or {})


# ---------------------------------------------------------------------------
# M2M: Bearer-only (no session cookie) — must be CSRF-exempt
# ---------------------------------------------------------------------------

class TestBearerOnlyIsExempt:
    """Pure API clients authenticating via Bearer token have no browser session
    cookie and therefore are not subject to CSRF enforcement."""

    def test_bearer_no_cookie_passes_csrf_gate(self, client):
        """A request with Authorization header but no cookie must NOT be blocked
        by the CSRF middleware (it may still fail auth, but not with 403 csrf_failed)."""
        resp = _post(
            client,
            PROTECTED_PATH,
            headers={"Authorization": "Bearer some.jwt.token"},
        )
        # 401 (auth failed) or 403 (auth forbidden) are acceptable —
        # but the error code must NOT be "csrf_failed".
        assert resp.status_code in (400, 401, 403, 422)
        if resp.status_code == 403:
            data = resp.json()
            assert data.get("error", {}).get("code") != "csrf_failed", (
                "Bearer-only request was incorrectly blocked by CSRF middleware"
            )

    def test_bearer_no_cookie_no_csrf_header_passes_gate(self, client):
        """Bearer request with no X-CSRF-Token header must not be csrf_failed."""
        resp = _post(
            client,
            PROTECTED_PATH,
            headers={"Authorization": "Bearer token", "X-CSRF-Token": ""},
        )
        if resp.status_code == 403:
            assert resp.json().get("error", {}).get("code") != "csrf_failed"


# ---------------------------------------------------------------------------
# Cookie session (no Bearer) — CSRF required
# ---------------------------------------------------------------------------

class TestCookieSessionRequiresCSRF:
    """Browser sessions use access_token cookies. Any state-changing request
    must carry a matching X-CSRF-Token / csrf_token double-submit pair."""

    def test_cookie_no_csrf_header_is_rejected(self, client):
        """Session cookie present but no CSRF header → 403 csrf_failed."""
        resp = _post(
            client,
            PROTECTED_PATH,
            cookies={"access_token": "fake.session.token"},
        )
        assert resp.status_code == 403
        assert resp.json().get("error", {}).get("code") == "csrf_failed"

    def test_cookie_missing_csrf_cookie_is_rejected(self, client):
        """CSRF header present but no csrf_token cookie → 403 csrf_failed."""
        resp = _post(
            client,
            PROTECTED_PATH,
            cookies={"access_token": "fake.session.token"},
            headers={"X-CSRF-Token": _VALID_CSRF},
        )
        assert resp.status_code == 403
        assert resp.json().get("error", {}).get("code") == "csrf_failed"

    def test_cookie_mismatched_csrf_is_rejected(self, client):
        """Header/cookie pair present but values differ → 403 csrf_failed."""
        resp = _post(
            client,
            PROTECTED_PATH,
            cookies={"access_token": "fake.session.token", "csrf_token": _VALID_CSRF},
            headers={"X-CSRF-Token": _WRONG_CSRF},
        )
        assert resp.status_code == 403
        assert resp.json().get("error", {}).get("code") == "csrf_failed"

    def test_cookie_matching_csrf_passes_gate(self, client):
        """Matching double-submit pair must not produce 403 csrf_failed.
        The downstream handler may still reject the request (401/403 for auth),
        but it must not be blocked at the CSRF gate."""
        resp = _post(
            client,
            PROTECTED_PATH,
            cookies={"access_token": "fake.session.token", "csrf_token": _VALID_CSRF},
            headers={"X-CSRF-Token": _VALID_CSRF},
        )
        # Must not be csrf_failed — any other rejection is acceptable.
        if resp.status_code == 403:
            assert resp.json().get("error", {}).get("code") != "csrf_failed"


# ---------------------------------------------------------------------------
# Dual-credential (cookie + Bearer) — CSRF must still apply
# ---------------------------------------------------------------------------

class TestDualCredentialRequiresCSRF:
    """CSRF bypass vector: an attacker tricks a logged-in browser into sending a
    request with an Authorization header that contains a DIFFERENT token than the
    session cookie (e.g. via a crafted link or injected script pointing to a
    different auth context).

    When Bearer token != access_token cookie value, the CSRF check applies because
    the caller cannot demonstrate it actually read the cookie value.

    When Bearer token == access_token cookie value, the caller demonstrably holds
    the token in JS memory (received it from a login response body), so CSRF does
    not apply — a cross-site attacker cannot read the HttpOnly cookie to mirror it.
    """

    def test_mismatched_bearer_and_cookie_no_csrf_is_rejected(self, client):
        """Bearer token differs from access_token cookie, no CSRF token → 403 csrf_failed.

        This is the bypass vector: attacker sends their own Bearer token while
        the victim's cookie is automatically attached by the browser.
        """
        resp = _post(
            client,
            PROTECTED_PATH,
            cookies={"access_token": "victim.cookie.token"},
            headers={"Authorization": "Bearer attacker.different.token"},
        )
        assert resp.status_code == 403
        assert resp.json().get("error", {}).get("code") == "csrf_failed", (
            "Mismatched-token dual-credential request bypassed CSRF middleware. "
            "Bearer exemption must NOT apply when the Bearer token differs from "
            "the access_token cookie value."
        )

    def test_mismatched_bearer_wrong_csrf_is_rejected(self, client):
        """Mismatched tokens + wrong CSRF token → 403 csrf_failed."""
        resp = _post(
            client,
            PROTECTED_PATH,
            cookies={"access_token": "victim.cookie.token", "csrf_token": _VALID_CSRF},
            headers={
                "Authorization": "Bearer attacker.different.token",
                "X-CSRF-Token": _WRONG_CSRF,
            },
        )
        assert resp.status_code == 403
        assert resp.json().get("error", {}).get("code") == "csrf_failed"

    def test_mismatched_bearer_matching_csrf_passes_gate(self, client):
        """Mismatched tokens but correct CSRF double-submit → gate passes."""
        resp = _post(
            client,
            PROTECTED_PATH,
            cookies={"access_token": "victim.cookie.token", "csrf_token": _VALID_CSRF},
            headers={
                "Authorization": "Bearer attacker.different.token",
                "X-CSRF-Token": _VALID_CSRF,
            },
        )
        if resp.status_code == 403:
            assert resp.json().get("error", {}).get("code") != "csrf_failed"

    def test_matching_bearer_and_cookie_bypasses_csrf_check(self, client):
        """When Bearer == access_token cookie, caller demonstrably holds the token
        in JS memory (not a cross-site request).  CSRF gate must NOT block this."""
        _SAME_TOKEN = "same.jwt.token.value"
        resp = _post(
            client,
            PROTECTED_PATH,
            cookies={"access_token": _SAME_TOKEN},
            headers={"Authorization": f"Bearer {_SAME_TOKEN}"},
        )
        # Must not be csrf_failed — downstream auth check may still reject.
        if resp.status_code == 403:
            assert resp.json().get("error", {}).get("code") != "csrf_failed"


# ---------------------------------------------------------------------------
# Safe methods are always exempt
# ---------------------------------------------------------------------------

class TestSafeMethodsExempt:
    """GET, HEAD, OPTIONS must never trigger CSRF validation."""

    def test_get_no_csrf_is_not_rejected(self, client):
        resp = client.get(
            "/api/health",
            cookies={"access_token": "fake.session.token"},
        )
        if resp.status_code == 403:
            assert resp.json().get("error", {}).get("code") != "csrf_failed"


# ---------------------------------------------------------------------------
# Exempt paths bypass CSRF unconditionally
# ---------------------------------------------------------------------------

class TestExemptPaths:
    """Login/register/refresh must work without CSRF tokens even with cookies."""

    @pytest.mark.parametrize("path", [
        "/api/auth/login",
        "/api/auth/register",
        "/api/auth/refresh",
        "/api/auth/revoke-token",
        # /api/auth/logout is NOT in exempt paths — it enforces CSRF for cookie
        # sessions (forces attacker to also supply CSRF token to force a logout).
        "/api/auth/password-reset/request",
        # /api/auth/password-reset/confirm is intentionally NOT exempt:
        # it changes state (sets new password) and must be CSRF-protected.
    ])
    def test_exempt_path_with_cookie_no_csrf_is_not_csrf_failed(self, client, path):
        resp = _post(
            client,
            path,
            cookies={"access_token": "fake.session.token"},
            json={"email": "x@example.com", "password": "TestPass123"},
        )
        # Must not be a CSRF rejection.
        if resp.status_code == 403:
            assert resp.json().get("error", {}).get("code") != "csrf_failed"
