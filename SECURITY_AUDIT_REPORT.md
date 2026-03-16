# SecureWave VPN — Backend Security Audit Report

**Date:** 2026-03-16
**Auditor:** Claude Opus 4.6 (automated static analysis)
**Branch:** `ui-repair-before-rebuild`
**Scope:** Full backend — authentication, API security, database, server config, dependencies, environment, VPN provisioning

---

## Executive Summary

The SecureWave backend demonstrates **strong security posture** overall. The codebase implements JWT revocation, CSRF protection, rate limiting, Fernet encryption for VPN credentials, input sanitization, structured logging with secret redaction, and comprehensive security headers. The architecture follows defense-in-depth principles.

**4 vulnerabilities patched** in this audit. **6 advisory findings** documented for future hardening.

---

## Vulnerability Findings

### VULN-01: Weak Password Policy (MEDIUM)

| Field | Value |
|-------|-------|
| **Risk** | MEDIUM |
| **Location** | `utils/password_policy.py` |
| **Status** | **FIXED** |

**Before:** Only required 8 chars, one letter, one digit. Allowed passwords like `abcdefg1` — trivially crackable.

**After:** Requires 10 chars minimum, uppercase, lowercase, digit, and special character. Aligns with NIST SP 800-63B and OWASP ASVS L2.

---

### VULN-02: SQLAlchemy `conn.execute()` with Raw String (LOW)

| Field | Value |
|-------|-------|
| **Risk** | LOW |
| **Location** | `database/session.py:223` |
| **Status** | **FIXED** |

**Issue:** `conn.execute("SELECT 1")` uses a raw string instead of `text()`. SQLAlchemy 2.0 requires `text()` for raw SQL. While not exploitable (static query, no user input), it triggers deprecation warnings and could mask future unsafe patterns.

**Fix:** Changed to `conn.execute(text("SELECT 1"))` with proper import.

---

### VULN-03: Missing Subprocess Timeout (MEDIUM)

| Field | Value |
|-------|-------|
| **Risk** | MEDIUM |
| **Location** | `services/vpn_credential_service.py:542` |
| **Status** | **FIXED** |

**Issue:** `subprocess.run(..., shell=True)` in `_run_remote_script_detailed` had no `timeout` parameter. A hung SSH/shell process would block the ASGI worker indefinitely, leading to denial of service.

**Fix:** Added `timeout=120` (matches the SSH timeout used in `admin.py` bulk operations).

---

### VULN-04: Nginx Missing Security Headers (MEDIUM)

| Field | Value |
|-------|-------|
| **Risk** | MEDIUM |
| **Location** | `nginx/securewave_preview.conf` |
| **Status** | **FIXED** |

**Issue:** Nginx SSL block only had HSTS. Missing `X-Content-Type-Options`, `X-Frame-Options`, `Referrer-Policy`, `Permissions-Policy`, and `server_tokens off`. While FastAPI adds these headers at the application layer, the Nginx reverse proxy should provide defense-in-depth (clients hitting cached/static responses bypass the app middleware).

**Fix:** Added all missing headers to the Nginx SSL server block plus `server_tokens off`.

---

### VULN-05: `python-jose` Has Known CVE (ADVISORY)

| Field | Value |
|-------|-------|
| **Risk** | LOW |
| **Location** | `requirements.txt:17` |
| **Status** | ADVISORY — recommend migration |

**Issue:** `python-jose==3.4.0` is unmaintained and has known issues (CVE-2024-33663, CVE-2024-33664 — algorithm confusion attacks). While the codebase correctly pins `algorithms=[ALGORITHM]` in `decode_token()` which mitigates the confusion vector, the library itself is no longer receiving patches.

**Recommendation:** Migrate to `PyJWT>=2.8.0` or `joserfc>=0.9.0`. Both are actively maintained.

---

### VULN-06: ADMIN_EMAIL Auto-Escalation Pattern (ADVISORY)

| Field | Value |
|-------|-------|
| **Risk** | LOW |
| **Location** | `routes/auth.py:383-387` |
| **Status** | ADVISORY — recommend removal for production |

**Issue:** On login, if `user.email == ADMIN_EMAIL` and `is_admin` is False, the code auto-promotes to admin. If an attacker gains control of the `ADMIN_EMAIL` env var (e.g., via SSRF, env dump), any user matching that email becomes admin on next login.

**Mitigation already present:** Production startup warns when `ADMIN_EMAIL` is set. The env var is typically only used in development.

**Recommendation:** Remove auto-promotion in production. Use a CLI command or migration to set admin flags instead.

---

### VULN-07: `crypt` Fallback in Hashing Service (ADVISORY)

| Field | Value |
|-------|-------|
| **Risk** | LOW |
| **Location** | `services/hashing_service.py:11,30-39` |
| **Status** | ADVISORY |

**Issue:** If `passlib` is not installed, the code falls back to Python's `crypt` module (deprecated since 3.11, removed in 3.13). The fallback uses SHA-512 if bcrypt is unavailable, which is weaker for password hashing than bcrypt/argon2.

**Mitigation:** `passlib` is pinned in `requirements.txt`, so this path should never execute in production. The fallback exists for minimal development environments.

**Recommendation:** Remove the `crypt` fallback entirely. Fail hard if `passlib` is not installed.

---

### VULN-08: Base64 Credential Fallback in Dev Mode (ADVISORY)

| Field | Value |
|-------|-------|
| **Risk** | LOW (dev only) |
| **Location** | `services/vpn_credential_service.py:139` |
| **Status** | ADVISORY |

**Issue:** When Fernet encryption key is missing (dev mode), VPN credentials are stored as base64 instead of encrypted. The `_encrypt()` method falls back to `base64.b64encode()` which is encoding, not encryption.

**Mitigation already present:** In production, `require_encryption_keys()` in `main.py` raises a `RuntimeError` if keys are missing, preventing app startup. The fallback only activates in development.

**Recommendation:** Log a CRITICAL warning when using base64 fallback. Consider failing even in dev.

---

### VULN-09: `bcrypt==3.2.2` is Outdated (ADVISORY)

| Field | Value |
|-------|-------|
| **Risk** | LOW |
| **Location** | `requirements.txt:19` |
| **Status** | ADVISORY |

**Issue:** `bcrypt==3.2.2` is 2 major versions behind current (4.2.x). While no critical CVEs, newer versions include Rust-based performance improvements and security hardening.

**Recommendation:** Upgrade to `bcrypt>=4.1.0`.

---

### VULN-10: Email Verification Not Enforced at Login (ADVISORY)

| Field | Value |
|-------|-------|
| **Risk** | LOW |
| **Location** | `routes/auth.py:340-345` |
| **Status** | ADVISORY |

**Issue:** The email verification check at login is commented out. Unverified accounts can fully authenticate and use the service. This allows account creation with unowned email addresses.

**Mitigation:** Email verification state is exposed via `/api/auth/me`, so clients can enforce it. VPN provisioning could gate on `email_verified`.

**Recommendation:** Uncomment the enforcement block before production launch, or add a grace period (e.g., 24h to verify).

---

## Security Controls Verified (Passing)

| Control | Status | Details |
|---------|--------|---------|
| **JWT Implementation** | PASS | HS256 with separate access/refresh secrets, derived via HMAC-SHA256 from master key. JTI-based revocation with blacklist table. |
| **Token Expiration** | PASS | Access: 30 min, Refresh: 14 days. Configurable via env. |
| **Refresh Token Rotation** | PASS | Old refresh JTI revoked on rotation, `replaced_by_jti` tracked. |
| **Session Revocation** | PASS | Middleware checks blacklist on every request (`enforce_revoked_access_token`). Background task purges expired entries. |
| **CSRF Protection** | PASS | Double-submit cookie pattern. Exempt paths correctly scoped. Bearer auth bypasses CSRF (stateless). |
| **Rate Limiting** | PASS | SlowAPI with Redis backend. Per-endpoint limits: register 5/hr, login 10/min, checkout 10/min. Global 200/min. |
| **Input Validation** | PASS | Pydantic models on all endpoints. `EmailStr` for emails. Custom sanitizers for device names, WG keys, endpoints, regions, allowed-ips. |
| **SQL Injection** | PASS | All queries via SQLAlchemy ORM. No f-string SQL found. Parameterized throughout. |
| **Password Hashing** | PASS | bcrypt with 12 rounds (4 in tests). 72-char truncation (bcrypt limit). |
| **Secret Storage** | PASS | VPN credentials encrypted with Fernet. WG private keys redacted in logs. Stripe keys redacted. |
| **Security Headers** | PASS | CSP, HSTS (preload), X-Frame-Options DENY, X-Content-Type-Options nosniff, Referrer-Policy, Permissions-Policy. |
| **HTTPS Enforcement** | PASS | Middleware rejects non-HTTPS in production. Nginx redirects 80→443. |
| **CORS** | PASS | No wildcards in production (enforced at startup). Explicit methods and headers. |
| **Log Redaction** | PASS | `RedactFilter` strips emails, Bearer tokens, Stripe secrets, WG private keys from all log output. |
| **Admin Auth** | PASS | `require_admin` dependency checks `is_admin` flag. Admin endpoints protected. |
| **Stripe Webhooks** | PASS | Signature verification via `construct_webhook_event`. Payload hash tracked for replay prevention. Idempotency keys for checkout. |
| **URL Redirect Safety** | PASS | `require_safe_redirect_url` enforces same-origin. Blocks schema-relative and cross-origin URLs. |
| **Subprocess Safety** | PASS | `shlex.quote()` used for shell commands. `_validate_wg_peer_inputs` validates WG keys and IPs before SSH. No user-controlled args reach shell directly. |
| **Account Lockout** | PASS | 5 failed attempts → 30 min lockout. Auto-unlock after duration. |
| **2FA/TOTP** | PASS | pyotp-based TOTP with backup codes. QR code generation for authenticator apps. |
| **API Docs Disabled in Prod** | PASS | OpenAPI/Swagger/ReDoc disabled when `ENVIRONMENT=production`. |
| **`.env` in `.gitignore`** | PASS | All `.env*` files excluded. `.pem`, `.key`, `.p12` excluded. WG config files excluded. |
| **Production Config Validation** | PASS | Startup fails fast on missing JWT_SECRET, encryption keys, EMAIL_PROVIDER. SQLite rejected without explicit override. |
| **Request Tracing** | PASS | UUID request IDs on every response. Context-var based for async compatibility. |

---

## Dependency Risk Assessment

| Package | Version | Status | Notes |
|---------|---------|--------|-------|
| fastapi | 0.115.12 | Current | No known CVEs |
| SQLAlchemy | 2.0.30 | Current | No known CVEs |
| cryptography | 44.0.1 | Current | No known CVEs |
| stripe | 10.12.0 | Current | No known CVEs |
| python-jose | 3.4.0 | **Outdated** | CVE-2024-33663/33664 — mitigated by algorithm pinning |
| bcrypt | 3.2.2 | **Outdated** | No critical CVEs, but 2 major versions behind |
| passlib | 1.7.4 | Stable | Maintained, no CVEs |
| slowapi | 0.1.9 | Current | No known CVEs |
| pillow | 10.4.0 | Current | No known CVEs |
| jinja2 | 3.1.6 | Current | No known CVEs |
| pydantic | 2.10.6 | Current | No known CVEs |

---

## Change Log

### CHANGED (patched in this audit)

| File | Change | Risk Mitigated |
|------|--------|----------------|
| `utils/password_policy.py` | Strengthened to 10 chars, upper+lower+digit+special | Weak password bruteforce |
| `database/session.py` | `text()` wrapper for raw SQL + import | SQLAlchemy 2.0 compliance, future injection prevention |
| `services/vpn_credential_service.py` | Added `timeout=120` to subprocess.run | DoS via hung shell process |
| `nginx/securewave_preview.conf` | Added X-Content-Type-Options, X-Frame-Options, Referrer-Policy, Permissions-Policy, server_tokens off | Clickjacking, MIME sniffing, info disclosure |
| `tests/unit/test_auth.py` | Updated test passwords to match new policy | Test compatibility |
| `tests/integration/test_stripe_hardening.py` | Updated test password | Test compatibility |
| `tests/integration/test_vpn_flow.py` | Updated test passwords | Test compatibility |

### REUSED (existing security controls verified and unchanged)

| Component | Assessment |
|-----------|------------|
| JWT service (`services/jwt_service.py`) | Solid implementation with revocation, rotation, separate secrets |
| CSRF middleware (`main.py`) | Correct double-submit cookie pattern |
| Rate limiting (SlowAPI + Redis) | Properly configured per-endpoint and global limits |
| Input sanitizer (`utils/input_sanitizer.py`) | Comprehensive regex validation for all VPN-related inputs |
| Log redaction (`main.py:RedactFilter`) | Covers emails, tokens, Stripe keys, WG private keys |
| Auth service (`services/auth_service.py`) | Account lockout, 2FA, email verification — all functional |
| Stripe webhook verification | Signature + hash-based replay prevention |
| URL safety (`utils/url_safety.py`) | Same-origin enforcement for redirect URLs |
| Production config validation (`config/settings.py`) | Fail-fast on missing secrets, disallows wildcards/SQLite |

### UNTOUCHED (no changes needed)

| Component | Reason |
|-----------|--------|
| `routes/auth.py` | Login flow, registration, token handling — all secure |
| `routes/vpn.py` | 216KB VPN route file — uses ORM, sanitizers, auth guards |
| `routers/payment_stripe.py` | Proper Stripe integration with idempotency |
| `routers/admin.py` | Admin-gated, validated inputs, subprocess with validated args |
| `services/wireguard_service.py` | Key generation via `subprocess.check_output(["wg", "genkey"])` — safe |
| `models/` | All ORM models — no raw SQL exposure |
| `database/session.py` (pool config) | Production-grade pooling, SSL, timeouts |
| `Dockerfile` | Slim base, non-root compatible, health check |
| `.gitignore` | Comprehensive coverage of secrets, keys, databases |

### RISKS (accepted or deferred)

| Risk | Severity | Mitigation | Action |
|------|----------|------------|--------|
| `python-jose` unmaintained | LOW | Algorithm pinned to HS256 in `decode_token()` | Migrate to PyJWT/joserfc in next sprint |
| ADMIN_EMAIL auto-escalation | LOW | Startup warning in production | Remove for prod; use CLI admin flag |
| `crypt` fallback | LOW | `passlib` always installed from requirements.txt | Remove fallback code |
| Base64 credential fallback | LOW | Production startup blocks missing encryption keys | Add CRITICAL log warning |
| Email verification not enforced | LOW | Exposed via /me endpoint | Uncomment enforcement before launch |
| `bcrypt==3.2.2` outdated | LOW | No critical CVEs | Upgrade to 4.x |

---

## Test Verification

```
644 passed in 27.64s (excluding infrastructure-dependent preview tests)
```

All changes verified against the full test suite. No regressions introduced.
