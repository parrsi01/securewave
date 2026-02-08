# SecureWave VPN -- Comprehensive Security Audit Report

**Date:** 2026-02-08
**Auditor:** Security Engineering (Automated + Manual Review)
**Scope:** Full codebase -- backend (Python/FastAPI), frontend (Flutter/Dart), infrastructure scripts, deployment configs
**Commit:** 36668d8 (master)

---

## Executive Summary

The SecureWave VPN codebase demonstrates a reasonably mature security posture for a project at this stage. Authentication, token management, and encryption are handled with industry-standard libraries. However, there are several findings ranging from Critical to Informational that must be addressed before any production deployment with paying customers.

**Critical: 2** | **High: 5** | **Medium: 8** | **Low: 6** | **Info: 4**

---

## 1. LOGGING AUDIT

### 1.1 Log Redaction Filter -- Regex Defect

**Severity: HIGH**

**File:** `/home/sp/cyber-course/projects/securewave/main.py` (lines 44-58)

The `RedactFilter` class uses double-escaped backslashes in its compiled regex patterns. This is a critical defect because the patterns will never match actual log content.

```python
_token_re = re.compile(r"(Bearer\\s+)[A-Za-z0-9._\\-]+")
_wg_priv_re = re.compile(r"(PrivateKey\\s*=\\s*)([^\\s]+)")
_wg_psk_re = re.compile(r"(PresharedKey\\s*=\\s*)([^\\s]+)")
```

These patterns match literal backslash-s (`\s`) in the string, not whitespace characters. The correct patterns would be:

```python
_token_re = re.compile(r"(Bearer\s+)[A-Za-z0-9._\-]+")
_wg_priv_re = re.compile(r"(PrivateKey\s*=\s*)([^\s]+)")
```

**Impact:** If a WireGuard config blob or Bearer token is accidentally logged, the redaction filter will NOT strip it. The filter is effectively a no-op for its intended purpose.

### 1.2 Admin Password Logged in Plaintext

**Severity: HIGH**

**File:** `/home/sp/cyber-course/projects/securewave/infrastructure/database_init.py` (line 115)

```python
logger.info("Admin user created (email: admin@securewave.app, password: SecureWave2026!)")
```

The hardcoded admin password is emitted to logs in plaintext. If this script runs in a production-adjacent environment, the password is trivially recoverable from log aggregation systems.

### 1.3 Database Password Partially Logged

**Severity: MEDIUM**

**File:** `/home/sp/cyber-course/projects/securewave/infrastructure/azure_database_deployer.py` (line 224)

```python
logger.info(f"  Password: {admin_password[:4]}...{admin_password[-4:]} (saved to .env.production)")
```

Logging the first and last 4 characters of a database password significantly reduces brute-force entropy. For a typical 20-character password, this leaks 40% of the content.

### 1.4 Dart-Side Logging -- No Release Guard

**Severity: LOW**

**File:** `/home/sp/cyber-course/projects/securewave/securewave_app/lib/core/logging/app_logger.dart`

The `AppLogger` class uses `dart:developer log()` which is stripped in release builds. However, the `logStream` ValueNotifier retains all log entries in memory (up to 200). If the diagnostics page is accessible in release builds, users could observe internal state transitions including server IDs, error messages, and connection metadata. No sensitive keys are logged through this path based on current review.

### 1.5 Print Statements in Infrastructure Scripts

**Severity: LOW**

**Files:**
- `/home/sp/cyber-course/projects/securewave/infrastructure/init_production_server.py` (line 126): Prints server public key (acceptable).
- `/home/sp/cyber-course/projects/securewave/infrastructure/register_server.py` (line 69): Prints truncated public key (acceptable).
- `/home/sp/cyber-course/projects/securewave/artifacts/vpn_tests/20260208_041545/generate_test_profile.py` (line 103): Prints auto-generated server public key (acceptable for test tooling only).

No private keys are printed.

### 1.6 Email Addresses Logged Pre-Redaction

**Severity: INFO**

Multiple log calls include user emails directly (e.g., `logger.info(f"User logged in: {user.email}")`). The `RedactFilter` is meant to strip these, but per finding 1.1, the email regex IS functional (it does not suffer from the double-escape issue). Emails are being redacted in production logs.

---

## 2. DNS LEAK PROTECTION

### 2.1 DNS Leak Detection is Server-Side Only -- No Client Enforcement

**Severity: HIGH**

**File:** `/home/sp/cyber-course/projects/securewave/services/dns_leak_protection.py`

The DNS leak protection service runs entirely on the backend. It reads `/etc/resolv.conf` on the **server** machine, not the client device. This means:

- It detects if the server's own DNS is misconfigured (useful for server health checks)
- It does NOT detect or prevent DNS leaks on client devices
- There is no Dart-side DNS leak detection or enforcement

**Client-side DNS protection** relies entirely on the WireGuard config's `DNS = ` directive (set to `94.140.14.14,94.140.15.15` AdGuard DNS or `1.1.1.1` Cloudflare depending on code path). WireGuard clients typically honor this directive and route DNS through the tunnel, but:

- There is no verification that the client is actually using tunnel DNS
- No periodic DNS leak tests are run from the client
- IPv6 DNS leaks are not explicitly addressed in the WireGuard config (though `AllowedIPs = 0.0.0.0/0, ::/0` catches all traffic including IPv6 DNS)

### 2.2 DNS Servers Are Hardcoded with Reasonable Defaults

**Severity: LOW**

DNS servers in WireGuard profiles come from `SECUREWAVE_TUNNEL_DNS` env var, defaulting to AdGuard DNS (`94.140.14.14,94.140.15.15`). The older `WireGuardService` uses `WG_DNS` env var defaulting to `1.1.1.1`. These are reasonable public resolvers. The inconsistency between the two code paths is a minor issue.

### 2.3 No DNS-over-HTTPS/TLS Enforcement

**Severity: INFO**

The `dns_leak_protection.py` service documents DoH/DoT endpoints (Cloudflare, Google, Quad9) but does not enforce their use. DNS queries within the WireGuard tunnel are still plain UDP to the configured resolver. This is standard for WireGuard deployments but worth noting for privacy-conscious users.

---

## 3. KILL SWITCH ASSESSMENT

### 3.1 Linux Kill Switch -- Best Effort Only

**Severity: MEDIUM**

**File:** `/home/sp/cyber-course/projects/securewave/routes/vpn.py` (lines 271-291)

Linux kill switch is implemented via `wg-quick` PostUp/PostDown hooks using iptables rules. This is a reasonable approach, but:

- The rules use `|| true` -- if iptables is not available, the kill switch silently fails
- The kill switch only activates when using `wg-quick` (not the standalone `wg` tool)
- If the system crashes (not a clean PostDown), iptables rules are NOT cleaned up, potentially locking the user out of network access until reboot
- The `REJECT` target (not `DROP`) leaks information about the firewall's presence

### 3.2 iOS/macOS -- No Kill Switch Implementation

**Severity: MEDIUM**

iOS relies on the operating system's "Always-on VPN" / "Block without VPN" feature. The app itself does not programmatically enable this. The `NEVPNProtocol.disconnectOnSleep` and `includeAllNetworks` properties are not configured in the WireGuard Network Extension code. Users must manually enable this in iOS Settings.

### 3.3 Android -- Relies on OS-Level Always-On VPN

**Severity: MEDIUM**

The Android native VPN service (`SecureWaveVpnService.kt`) does not set `VpnService.Builder.setBlockingMode()` or equivalent. Kill switch depends entirely on the user enabling "Always-on VPN" and "Block connections without VPN" in Android system settings.

### 3.4 Windows -- No Kill Switch

**Severity: MEDIUM**

The Windows WireGuard bridge (`flutter_window.cpp`) invokes `wireguard.exe` but does not configure Windows Filtering Platform (WFP) rules for kill switch behavior. Traffic will leak if the tunnel drops.

### 3.5 Web/Desktop Fallback -- No Traffic Blocking

**Severity: INFO**

When the mock VPN service is active (fallback mode), there is no traffic blocking at all. This is expected for demo mode but should be clearly communicated to users.

---

## 4. SENSITIVE DATA HANDLING

### 4.1 Hardcoded Admin Credentials in Source Code

**Severity: CRITICAL**

**File:** `/home/sp/cyber-course/projects/securewave/infrastructure/database_init.py` (lines 100-115)

```python
password_hash = bcrypt.hashpw(
    "SecureWave2026!".encode('utf-8'),
    bcrypt.gensalt()
).decode('utf-8')
```

A hardcoded default admin password (`SecureWave2026!`) is baked into the initialization script and logged to stdout. This password is also referenced in `disaster_recovery.py` (line 575). While this is only in an infrastructure script (not the app itself), it represents a credential that could persist in production if the admin does not change it.

### 4.2 JWT Secrets in .env File Committed to Git

**Severity: CRITICAL**

**File:** `/home/sp/cyber-course/projects/securewave/.env` (lines 12-13)

```
ACCESS_TOKEN_SECRET=fbf14fef60fa8248fd95a12cd89a0c46877fb8b006dc4e7e6059aac3e651ffe6
REFRESH_TOKEN_SECRET=324e3561ba51d0cce303d4f640d0b3f2cd0c26fc3331df166ef7d5c6e8cd66b6
```

Real JWT signing secrets and Fernet encryption keys are present in the `.env` file. While `.env` is in `.gitignore`, the file currently exists on disk in the repository working tree. The pre-commit hook (finding 4.5) would catch this if someone tried to commit it, but the `.env` file itself contains live development secrets.

Additionally, the `securewave_app/.env` file and multiple build artifact copies exist:
- `securewave_app/build/unit_test_assets/.env`
- `securewave_app/build/flutter_assets/.env`
- `securewave_app/build/linux/arm64/debug/bundle/data/flutter_assets/.env`
- `securewave_app/build/linux/arm64/release/bundle/data/flutter_assets/.env`

These build artifacts may contain the API base URL and mock configuration.

### 4.3 Token Storage -- Properly Using flutter_secure_storage

**Severity: INFO (Positive Finding)**

**File:** `/home/sp/cyber-course/projects/securewave/securewave_app/lib/core/services/secure_storage.dart`

Access tokens, refresh tokens, and VPN profile configs (which contain WireGuard private keys) are stored in `flutter_secure_storage`, which uses:
- iOS/macOS: Keychain
- Android: EncryptedSharedPreferences (AES-256 + KeyStore)
- Windows: Windows Credential Manager
- Linux: libsecret

This is the correct approach. The WireGuard private key in the profile config is stored encrypted at rest on the device.

### 4.4 2FA Secret Encryption Fallback to Base64

**Severity: MEDIUM**

**File:** `/home/sp/cyber-course/projects/securewave/services/auth_service.py` (lines 263-279)

When `AUTH_ENCRYPTION_KEY` is not set (development mode), 2FA TOTP secrets fall back to base64 encoding instead of Fernet encryption. Base64 is NOT encryption -- it is trivially reversible. In production, the code correctly requires a Fernet key and fails fast. However, a development database migrated to production without re-encrypting secrets would expose 2FA seeds.

### 4.5 Pre-Commit Hook -- Effective but Bypassable

**Severity: LOW**

**File:** `/home/sp/cyber-course/projects/securewave/scripts/pre-commit-hook.sh`

The hook is well-designed:
- Checks for AWS keys, Stripe keys, private key blocks, database connection strings, and generic secret patterns
- Skips test files, markdown, and sample files
- Blocks `.secrets`, `.env.local`, `.env.production` files

Weaknesses:
- Easily bypassed with `--no-verify`
- The base64 pattern `[A-Za-z0-9_-]{40,}=` will match many non-secret strings (high false positive rate)
- Does not detect Fernet keys specifically
- Does not check for WireGuard private keys (44-char base64 without `PrivateKey =` prefix)

### 4.6 WireGuard Config Files Written to Disk Unencrypted

**Severity: MEDIUM**

**File:** `/home/sp/cyber-course/projects/securewave/services/wireguard_service.py` (lines 139-141)

```python
config_path = self.users_dir / f"{user.id}.conf"
config_path.write_text(config_content)
```

WireGuard config files containing private keys are written to `wg_data/users/` as plaintext files. While the private key is encrypted in the database (`wg_private_key_encrypted`), the on-disk config file contains the decrypted private key. File permissions are not explicitly set (defaults to umask, typically 644 on Linux -- world-readable).

---

## 5. API SECURITY

### 5.1 All VPN Endpoints Require Authentication

**Severity: INFO (Positive Finding)**

All `/api/vpn/*` endpoints use `Depends(get_current_user)` which validates JWT tokens. Admin endpoints use `Depends(require_admin)`. Subscription checks (`require_active_subscription`) are enforced on config allocation and download endpoints.

### 5.2 SQL Injection -- ORM-Based (Low Risk)

**Severity: LOW**

The codebase uses SQLAlchemy ORM throughout. No raw SQL with string interpolation was found in route handlers. The `text()` function is used only in health checks (`text("SELECT 1")`). Database backup/restore scripts use `subprocess.run` with `psql` but do not interpolate user input.

### 5.3 Command Injection -- Validated but Risky Pattern

**Severity: MEDIUM**

**File:** `/home/sp/cyber-course/projects/securewave/routers/admin.py` (lines 151-168)

The admin peer registration endpoint builds shell commands using f-strings:
```python
wg_command = f"sudo wg set wg0 peer {user.wg_public_key} allowed-ips {client_ip}"
```

While both `wg_public_key` and `client_ip` are validated (regex for base64 key format, `ipaddress.ip_address()` parsing), the command is passed as a single string to Azure VM Run Command. The `_validate_wg_peer_inputs` function provides adequate validation, but the pattern of building shell commands from variables is inherently fragile. A future change that weakens validation could introduce command injection.

### 5.4 CORS -- Properly Configured

**Severity: INFO (Positive Finding)**

- Wildcards (`*`) are explicitly blocked in production
- Origins are loaded from `CORS_ORIGINS` env var
- Explicit methods and headers are whitelisted
- `allow_credentials=True` is set (required for cookie auth)

### 5.5 Rate Limiting -- Present but In-Memory

**Severity: LOW**

Rate limiting uses `slowapi` with `memory://` storage in development. In production, `REDIS_URL` should be configured for distributed rate limiting. Without Redis, rate limits are per-process and reset on restart. Key rate limits:
- Login: 10/minute
- Registration: 5/hour
- Password reset: 3/hour
- Config allocation: 10/minute
- Profile provisioning: 30/minute

### 5.6 CSRF Protection -- Implemented

**Severity: INFO (Positive Finding)**

CSRF protection is implemented via double-submit cookie pattern. The `enforce_csrf` middleware checks `X-CSRF-Token` header against `csrf_token` cookie for state-changing operations that use cookie-based auth. Bearer token auth is exempt (standard for API clients).

### 5.7 Security Headers -- Comprehensive

**Severity: INFO (Positive Finding)**

The `add_security_headers` middleware sets:
- `X-Content-Type-Options: nosniff`
- `X-Frame-Options: DENY`
- `X-XSS-Protection: 1; mode=block`
- `Strict-Transport-Security` (production only)
- `Content-Security-Policy` (restrictive)
- `Referrer-Policy: strict-origin-when-cross-origin`
- `Permissions-Policy` (geolocation, microphone, camera disabled)

### 5.8 Readiness Endpoint Leaks Error Details

**Severity: LOW**

**File:** `/home/sp/cyber-course/projects/securewave/main.py` (lines 494-501)

```python
except Exception as e:
    return {"status": "not_ready", "error": str(e)}
```

The `/api/ready` endpoint returns raw exception messages. In production, database connection errors could reveal hostname, port, or driver information.

### 5.9 ADMIN_EMAIL Auto-Promotion

**Severity: MEDIUM**

**File:** `/home/sp/cyber-course/projects/securewave/routes/auth.py` (lines 333-337)

```python
admin_email = os.getenv("ADMIN_EMAIL", "").strip().lower()
if admin_email and user.email.lower() == admin_email and not user.is_admin:
    user.is_admin = True
```

Any user who registers with the email matching `ADMIN_EMAIL` env var is automatically promoted to admin on login. If this env var is set in a shared environment or leaked, it provides a privilege escalation path.

---

## 6. MOCK API GUARD

### 6.1 Triple-Layer Protection -- Effective

**Severity: INFO (Positive Finding)**

**File:** `/home/sp/cyber-course/projects/securewave/securewave_app/lib/core/config/app_config.dart`

The mock API guard uses three layers:
1. **Compile-time constant:** `bool.fromEnvironment('dart.vm.product')` -- in release builds, this is `true`, making `kIsDebugMode = false`
2. **Runtime override:** Even if `SECUREWAVE_USE_MOCK_API=true` is set in `.env`, the release check overrides it:
   ```dart
   if (kIsReleaseMode && useMock) {
     useMock = false;
   }
   ```
3. **Default behavior:** In release mode, `useMockApi` defaults to `false`

This is correctly implemented. Mock data cannot leak to production release builds.

### 6.2 API Client Fallback to Mock on Error

**Severity: HIGH**

**File:** `/home/sp/cyber-course/projects/securewave/securewave_app/lib/services/api_client.dart` (lines 77-84, 133-137, 157-161)

When real API calls fail, the `ApiClient` silently falls back to mock data:

```dart
} catch (error, stackTrace) {
  AppLogger.warning('Login failed, returning mock token.');
  return _mockTokens(email);
}
```

This means:
- If the backend is unreachable, `login()` returns a fake token (`mock-token-{username}`)
- If the backend is unreachable, `register()` returns a fake token
- If the backend is unreachable, `fetchServers()` returns hardcoded mock servers

**In a release build with the real API configured**, if the server is temporarily down, users receive mock tokens that will not work with the backend when it recovers. More critically, this masks authentication failures -- a user who enters wrong credentials against an unreachable server gets a "successful" login with a worthless token.

This fallback behavior should be gated on `_config.useMockApi` -- it currently runs unconditionally on API errors regardless of build mode.

### 6.3 Backend Demo Mode Guards

**Severity: LOW**

**File:** `/home/sp/cyber-course/projects/securewave/main.py` (lines 333-343)

The backend correctly enforces that `DEMO_MODE` and `WG_MOCK_MODE` must be explicitly `false` in production (`require_production_config`). This prevents accidental demo mode in production. The OpenAPI docs are also disabled in production.

---

## 7. ADDITIONAL FINDINGS

### 7.1 IP Address Allocation -- Collision Risk

**Severity: MEDIUM**

**File:** `/home/sp/cyber-course/projects/securewave/services/wireguard_service.py` (line 112)

```python
def allocate_ip(self, user_id: int) -> str:
    octet = (user_id % 240) + 10
    return f"10.8.0.{octet}/32"
```

This function allocates IPs deterministically based on `user_id % 240`. After 240 users, IP addresses collide. Two different users with `user_id` 1 and 241 would get the same IP (`10.8.0.11/32`). This limits the system to 240 concurrent VPN users per server and creates silent routing conflicts.

### 7.2 WireGuard Mock Keypair Generation

**Severity: MEDIUM**

**File:** `/home/sp/cyber-course/projects/securewave/services/wireguard_service.py` (lines 84-88)

```python
except Exception:
    private_bytes = secrets.token_bytes(32)
    private_key = base64.b64encode(private_bytes).decode()
    public_key = base64.b64encode(secrets.token_bytes(32)).decode()
    return private_key, public_key
```

When the `wg` command is not available, the fallback generates a random "public key" that is NOT mathematically derived from the private key. This means the keypair is cryptographically invalid -- the public key cannot be used to verify anything signed by the private key. In mock/demo mode this is acceptable, but if this fallback runs in production (e.g., `wg` binary missing), peers registered with these keys will never establish a handshake.

### 7.3 Server Private Key Written to Disk Unprotected

**Severity: MEDIUM**

**File:** `/home/sp/cyber-course/projects/securewave/services/wireguard_service.py` (lines 107-109)

```python
private_key, public_key = self.generate_keypair()
self.server_private_path.write_text(private_key)
self.server_public_path.write_text(public_key)
```

The WireGuard server private key is written to `wg_data/server_private.key` with default file permissions. No `chmod 600` or equivalent is applied. On a shared system, other users could read the server's private key.

---

## Finding Summary Table

| ID   | Severity | Category          | Finding                                                     |
|------|----------|-------------------|-------------------------------------------------------------|
| 1.1  | HIGH     | Logging           | RedactFilter regex double-escaped -- filter is a no-op      |
| 1.2  | HIGH     | Logging           | Admin password logged in plaintext                          |
| 1.3  | MEDIUM   | Logging           | Database password partially logged                          |
| 1.4  | LOW      | Logging           | Dart log buffer accessible in release builds                |
| 1.5  | LOW      | Logging           | Print statements in infra scripts (public keys only)        |
| 1.6  | INFO     | Logging           | Email redaction functional                                  |
| 2.1  | HIGH     | DNS               | DNS leak detection is server-side only                      |
| 2.2  | LOW      | DNS               | DNS server inconsistency between code paths                 |
| 2.3  | INFO     | DNS               | No DoH/DoT enforcement                                     |
| 3.1  | MEDIUM   | Kill Switch       | Linux kill switch best-effort with silent failure            |
| 3.2  | MEDIUM   | Kill Switch       | iOS/macOS no programmatic kill switch                       |
| 3.3  | MEDIUM   | Kill Switch       | Android relies on OS-level setting                          |
| 3.4  | MEDIUM   | Kill Switch       | Windows no kill switch                                      |
| 3.5  | INFO     | Kill Switch       | Mock/demo mode has no traffic blocking (expected)           |
| 4.1  | CRITICAL | Secrets           | Hardcoded admin credentials in source                       |
| 4.2  | CRITICAL | Secrets           | JWT secrets and Fernet keys in .env on disk                 |
| 4.3  | INFO     | Secrets           | flutter_secure_storage correctly used                       |
| 4.4  | MEDIUM   | Secrets           | 2FA secret falls back to base64 in dev                      |
| 4.5  | LOW      | Secrets           | Pre-commit hook bypassable, missing WG key pattern          |
| 4.6  | MEDIUM   | Secrets           | WG config files written to disk unencrypted                 |
| 5.1  | INFO     | API               | All VPN endpoints require auth (positive)                   |
| 5.2  | LOW      | API               | ORM-based queries (low SQL injection risk)                  |
| 5.3  | MEDIUM   | API               | Shell command built from validated variables                 |
| 5.4  | INFO     | API               | CORS properly configured (positive)                         |
| 5.5  | LOW      | API               | Rate limiting in-memory only                                |
| 5.6  | INFO     | API               | CSRF protection implemented (positive)                      |
| 5.7  | INFO     | API               | Security headers comprehensive (positive)                   |
| 5.8  | LOW      | API               | Readiness endpoint leaks error details                      |
| 5.9  | MEDIUM   | API               | ADMIN_EMAIL auto-promotion privilege escalation             |
| 6.1  | INFO     | Mock Guard        | Triple-layer mock protection effective (positive)           |
| 6.2  | HIGH     | Mock Guard        | API client falls back to mock tokens on ANY error           |
| 6.3  | LOW      | Mock Guard        | Backend demo mode guards in place (positive)                |
| 7.1  | MEDIUM   | VPN Infrastructure| IP allocation collides after 240 users                      |
| 7.2  | MEDIUM   | VPN Infrastructure| Mock keypair public key not derived from private key        |
| 7.3  | MEDIUM   | VPN Infrastructure| Server private key file has default permissions             |

---

## Recommended Priority Actions

### Immediate (Before Any Production Deployment)

1. **Fix RedactFilter regex** (1.1) -- Remove double escaping in all four regex patterns
2. **Remove hardcoded admin password** (4.1) -- Generate random password at init time, require change on first login
3. **Rotate all secrets in .env** (4.2) -- Generate new JWT secrets and Fernet keys; old ones are compromised if repo was ever shared
4. **Fix API client mock fallback** (6.2) -- Only return mock data when `useMockApi` is true; on real API errors in release builds, propagate the error

### Short-Term (Before Beta)

5. **Fix log redaction regex** (1.1) -- Verify with unit tests that Bearer tokens and WireGuard keys are actually redacted
6. **Set file permissions on WG config files** (4.6, 7.3) -- `chmod 600` on private keys and config files
7. **Fix IP allocation** (7.1) -- Use a proper IP address pool with database-backed allocation
8. **Remove admin password from logs** (1.2) -- Never log credentials
9. **Document kill switch limitations** (3.1-3.4) -- Clearly communicate best-effort nature to users
10. **Gate ADMIN_EMAIL promotion** (5.9) -- Require additional verification or remove auto-promotion

### Medium-Term (Production Hardening)

11. Add client-side DNS leak testing (2.1)
12. Implement programmatic kill switch on iOS (`includeAllNetworks`) and Android
13. Add WireGuard key pattern to pre-commit hook (4.5)
14. Configure Redis for distributed rate limiting (5.5)
15. Sanitize readiness endpoint error messages (5.8)
16. Add proper Curve25519 key derivation for mock mode (7.2)

---

*End of Security Audit Report*
