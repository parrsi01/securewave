# SecureWave VPN — Security Architecture Audit

**Date:** 2026-03-17
**Auditor:** Claude Opus 4.6 (Senior Application Security Architect)
**Branch:** `ui-repair-before-rebuild`
**Scope:** Full stack — authentication, device provisioning, admin access, VPN config generation, API exposure, Stripe payments, logging/telemetry, deployment topology
**Method:** Static analysis of all backend source, infrastructure configs, and deployment scripts
**Confidence:** 85/100

---

## Executive Summary

**70 unique findings** across authentication, device provisioning, payments, API exposure, and infrastructure.

| Severity | Count | Description |
|----------|-------|-------------|
| CRITICAL | 3 | Root-level RCE path, global SSH exposure, unauthenticated metrics |
| HIGH | 17 | Shell injection, encryption bypass, token leakage, admin escalation |
| MEDIUM | 20 | Race conditions, CSRF gaps, log injection, config drift |
| LOW | 18 | Entropy weaknesses, privacy leaks, operational footguns |
| INFO | 12 | Architectural notes, positive observations |

**Top 3 immediate risks:**
1. Gunicorn runs as root — any RCE = full server compromise (C-2)
2. SSH open to internet by default in Terraform (C-1)
3. WireGuard private keys stored as base64 (not encrypted) when `WG_ENCRYPTION_KEY` absent (WG-02/WG-03)

---

## System Threat Model

### Assets (by value)

| Asset | CIA Impact | Location |
|-------|-----------|----------|
| WireGuard private keys (all users) | C: Critical, I: Critical | `wireguard_peers.private_key_encrypted` (DB) |
| WireGuard server private key | C: Critical, I: Critical | `vpn_servers.wg_private_key_encrypted` (DB) |
| User credentials (password hashes) | C: High | `users.password_hash` (DB) |
| TOTP secrets | C: High | `users.totp_secret` (DB, Fernet or base64) |
| JWT signing secrets | C: Critical, I: Critical | Environment variables |
| Stripe webhook secret | C: High | Environment variable |
| User real IP addresses | C: Medium (PII) | `vpn_connections.public_ip` (DB) |
| Subscription/billing state | I: High, A: High | `subscriptions` table (DB) |

### Threat Actors

| Actor | Capability | Goal |
|-------|-----------|------|
| External attacker (unauthenticated) | Network access, web scanner | Account takeover, free VPN access, data exfil |
| Authenticated basic user | Valid JWT, API access | Privilege escalation, device limit bypass, other users' data |
| Compromised CI/CD | Env var write, artifact injection | Persistent admin access, supply chain attack |
| Network-path attacker (BGP/ARP) | MITM between backend↔VPN server | SSH session hijack, WG key theft |
| Insider/compromised DBA | DB read access | Mass key extraction, billing manipulation |

### Attack Surfaces

```
Internet
  │
  ├── :80/:443 (Nginx) ──→ :8080 (Gunicorn/FastAPI)
  │     │                      │
  │     │                      ├── /api/auth/* (login, register, 2FA, reset)
  │     │                      ├── /api/vpn/* (connect, config, devices)
  │     │                      ├── /api/billing/* (checkout, webhooks)
  │     │                      ├── /api/payments/* (duplicate Stripe stack)
  │     │                      ├── /api/admin/* (peer mgmt, server mgmt)
  │     │                      ├── /api/diagnostics/* (audit logs, telemetry)
  │     │                      ├── /metrics (Prometheus — UNAUTHED)
  │     │                      ├── /version (env+commit — UNAUTHED)
  │     │                      └── /health, /api/health, /api/ready (UNAUTHED)
  │     │
  │     └── Static assets (HTML/CSS/JS)
  │
  ├── :22 (SSH) ──→ VPS management
  ├── :51820/udp (WireGuard)
  ├── :1194/udp (OpenVPN)
  └── :500,:4500/udp (IKEv2/IPsec)

Backend ──SSH──→ VPN Server(s) (peer add/remove, key rotation, cert provisioning)
Backend ──HTTP──→ VPN Server(s) (management API — plaintext)
Backend ──HTTPS──→ Stripe API (checkout, webhooks)
```

---

## CRITICAL Findings (3)

### C-1 — Gunicorn Runs as Root

| Field | Value |
|-------|-------|
| File | `gunicorn.conf.py:29-30` |
| Impact | Any RCE → full root on VPN server → all WireGuard private keys |

```python
user = None   # inherits launching process owner
group = None
```

The systemd units correctly set `User=securewave`, but `gunicorn.conf.py` is the fallback for Docker CMD, `deploy.sh`, and `start_site.sh` paths. On the live VPS, Gunicorn runs as root.

**Kill chain:** SSRF/deserialization/path-traversal → RCE as root → read `/opt/securewave/.env` (JWT secrets, Stripe keys, DB creds) → decrypt all WG private keys → impersonate any VPN client.

**Fix:** `user = "securewave"`, `group = "securewave"` in `gunicorn.conf.py`. Verify all startup paths.

---

### C-2 — SSH Open to Entire Internet (Terraform Default)

| Field | Value |
|-------|-------|
| File | `infrastructure/hetzner/variables.tf:77` |
| Impact | Global SSH brute-force surface on every `terraform apply` |

```hcl
default = ["0.0.0.0/0", "::/0"]
```

Any operator who runs `terraform apply` without explicit CIDR override exposes port 22 globally. Fail2ban is a mitigation, not a control.

**Fix:** Default to `[]`, require explicit CIDR. Add validation block rejecting `0.0.0.0/0`.

---

### C-3 — Unauthenticated Prometheus `/metrics` Endpoint

| Field | Value |
|-------|-------|
| File | `main.py:666` |
| Impact | Zero-cost reconnaissance of fleet capacity, session counts, server health |

```python
@app.get("/metrics", include_in_schema=False)  # no auth
```

Returns `active_sessions`, `active_tunnels`, `total_servers`, `healthy_servers`, `avg_load_score`. The `/api/metrics/*` endpoints require auth — this one is the outlier.

**Fix:** Add `Depends(get_current_user)` + `is_admin` check, or move behind Nginx basic auth.

---

## HIGH Findings (17)

### Authentication & Session Management (4)

| ID | Finding | File | Line |
|----|---------|------|------|
| H-AUTH-1 | Login-time admin promotion via `ADMIN_EMAIL` env var — permanent, no demotion path | `routes/auth.py` | 383-387 |
| H-AUTH-2 | 2FA check returns HTTP 200 + `requires_2fa=True` before TOTP verified — password oracle for 2FA accounts, no lockout on correct-password path | `routes/auth.py` | 350-355 |
| H-AUTH-3 | `update-email` leaks new tokens in JSON body, doesn't set cookies, doesn't revoke old tokens — XSS captures fresh credentials | `routes/auth.py` | 663-671 |
| H-AUTH-4 | `logout` deletes cookies only, no server-side token revocation; `logout-all` is a complete no-op returning `{"status":"ok"}` | `routes/auth.py` | 484-490, 728-731 |

### WireGuard & Device Provisioning (6)

| ID | Finding | File | Line |
|----|---------|------|------|
| H-WG-1 | `StrictHostKeyChecking=no` + `UserKnownHostsFile=/dev/null` on ALL SSH calls to VPN servers — MITM intercepts peer provisioning | `wireguard_server_manager.py` | 472-473 |
| H-WG-2 | Base64 fallback when Fernet key absent — WG private keys stored unencrypted in staging/dev | `wireguard_service.py` | 83-93 |
| H-WG-3 | Same base64 fallback for OpenVPN/IKEv2 credential passwords | `vpn_credential_service.py` | 136-153 |
| H-WG-4 | `_remove_peer_via_ssh` skips `_validate_peer_inputs` — shell injection via crafted DB public key | `wireguard_server_manager.py` | 538 |
| H-WG-5 | `_should_run_local` + `shell=True` — local RCE if attacker writes VPNServer with `public_ip=127.0.0.1` | `vpn_credential_service.py` | 538-549 |
| H-WG-6 | Provisioning secret passed via `sudo env VAR=value` — visible in `/proc/*/environ` and `ps auxe` | `vpn_credential_service.py` | 716-727 |

### Payments & API Exposure (4)

| ID | Finding | File | Line |
|----|---------|------|------|
| H-PAY-1 | Two active Stripe webhook endpoints (`/api/payments/stripe/webhook` + `/api/billing/webhooks/stripe`) — doubles attack surface | `payment_stripe.py` + `billing.py` | 203, 827 |
| H-PAY-2 | PayPal webhook has no pre-flight guard for credentials being configured — may process unverified events | `routes/billing.py` | 892 |
| H-PAY-3 | `/api/diagnostics/events` returns ALL users' audit logs to any authenticated user | `routes/diagnostics.py` | 204-215 |
| H-PAY-4 | `/version` endpoint leaks `ENVIRONMENT=production` and `GIT_SHA` to unauthenticated callers | `main.py` | 657-663 |

### Infrastructure & Deployment (3)

| ID | Finding | File | Line |
|----|---------|------|------|
| H-INF-1 | `load_hetzner_env.sh` uses `export $(grep | xargs)` — classic shell injection via env values | `load_hetzner_env.sh` | 5-6 |
| H-INF-2 | Dockerfile runs `alembic upgrade head` inline in CMD — concurrent container starts corrupt schema | `Dockerfile` | 48 |
| H-INF-3 | Pre-commit hook skips ALL test files for secret scanning — real secrets in test fixtures pass undetected | `pre-commit-hook.sh` | 55-56 |

---

## MEDIUM Findings (20)

### Authentication (4)

| ID | Finding | File |
|----|---------|------|
| M-AUTH-1 | Lockout check runs AFTER password verification; non-existent users never locked | `routes/auth.py:302-338` |
| M-AUTH-2 | Fernet decrypt silently falls back to base64 — TOTP secrets unencrypted if key absent | `auth_service.py:269-280` |
| M-AUTH-3 | Refresh token accepted in JSON body (XSS-extractable), not just HttpOnly cookie | `routes/auth.py:429-441` |
| M-AUTH-4 | CSRF exempt list includes `password-reset/confirm` — state-changing endpoint without CSRF | `main.py:317-324` |

### Device Provisioning (4)

| ID | Finding | File |
|----|---------|------|
| M-WG-1 | TOCTOU race on device limit check — concurrent requests bypass plan limits | `routes/devices.py:227-244` |
| M-WG-2 | Management API calls use HTTP not HTTPS | `wireguard_server_manager.py:318` |
| M-WG-3 | IP allocator has no row lock — concurrent allocation can assign same IP | `vpn_peer_manager.py:500-537` |
| M-WG-4 | `rotate_server_key` embeds private key directly in shell heredoc | `wireguard_server_manager.py:238-262` |

### Payments & API (5)

| ID | Finding | File |
|----|---------|------|
| M-PAY-1 | Rate limiting disabled globally when `TESTING=true` — no startup warning | `billing.py:39-44` |
| M-PAY-2 | `/api/billing/stripe-status` unauthenticated — leaks Stripe config, test/live mode | `billing.py:810-820` |
| M-PAY-3 | `/api/tools/ip` leaks full `X-Forwarded-For` proxy chain unauthenticated | `routes/tools.py:12-26` |
| M-PAY-4 | Telemetry batch endpoint has no `max_length` on records list — unbounded memory | `diagnostics.py:100-137` |
| M-PAY-5 | Admin billing endpoints use inline `if not is_admin` instead of dependency injection | `billing.py:932,956` |

### Infrastructure (7)

| ID | Finding | File |
|----|---------|------|
| M-INF-1 | Rate limiter uses `memory://` — per-worker, resets on restart, effective limit × workers | `main.py:180-182` |
| M-INF-2 | CSRF middleware bypassed by ANY `Authorization` header value, not just valid JWT | `main.py:335-336` |
| M-INF-3 | `X-Request-ID` accepted from client without sanitization — log injection | `main.py:268` |
| M-INF-4 | Nginx config has no `limit_req_zone` — fail2ban `nginx-limit-req` jail can never trigger | `securewave_preview.conf` |
| M-INF-5 | `ProtectSystem=full` (not `strict`) on API service — `/etc` writable | `securewave-api.service:24` |
| M-INF-6 | `umask = 0` in gunicorn.conf.py — WG key files created world-readable | `gunicorn.conf.py:31` |
| M-INF-7 | `deploy_backend.sh` silently falls back to `.env.example.backend` with placeholder secrets | `deploy_backend.sh:23-27` |

---

## LOW Findings (18)

| ID | Finding | File |
|----|---------|------|
| L-1 | bcrypt 72-byte truncation not blocked — passwords >72 bytes hash identically | `password_policy.py` |
| L-2 | Email verification gate commented out — unverified users have full access | `routes/auth.py:341-345` |
| L-3 | TOTP codes reusable within 90s window, not single-use | `auth_service.py:380,416` |
| L-4 | No upper bound validation on token expiry config | `config/settings.py:362-375` |
| L-5 | Backup code entropy 32 bits (below NIST SP 800-63B) | `auth_service.py:299` |
| L-6 | Device name duplicate check case-inconsistent (create vs rename) | `routes/devices.py:247,345` |
| L-7 | `/config/download` falls back to any active server without health filter | `routes/devices.py:603-605` |
| L-8 | `add_device` doesn't call `sanitize_device_name()` (unlike `DeviceCreateRequest`) | `routes/devices.py:291-292` |
| L-9 | Legacy config flow writes WG private key to disk in plaintext | `wireguard_service.py:174-176` |
| L-10 | Singleton `_test_mode` persists across requests if singleton reused | `wireguard_server_manager.py:52,71` |
| L-11 | `subscription.is_canceled` returns True for active+pending-cancel subscriptions | `models/subscription.py:96` |
| L-12 | Pydantic validation errors return full field paths/types to client | `main.py:1025-1029` |
| L-13 | OCSP resolver uses public Cloudflare DNS — discloses cert usage | `securewave_preview.conf:59` |
| L-14 | CSP allows `style-src 'unsafe-inline'` | `main.py:228` |
| L-15 | Access log format logs Referer and User-Agent (privacy concern for VPN product) | `gunicorn.conf.py:20` |
| L-16 | fail2ban `banaction = ufw` silently fails if ufw not active | `jail.local:9` |
| L-17 | No systemd `WatchdogSec` — hung async loop not detected | `securewave-api.service` |
| L-18 | No Terraform remote state backend — local state contains API token in plaintext | `versions.tf` |

---

## INFO / Positive Observations (12)

| # | Observation |
|---|-------------|
| 1 | `RedactFilter` in `main.py:52-73` redacts emails, Bearer tokens, Stripe keys, WG PrivateKey/PresharedKey — well-implemented |
| 2 | JWT secrets HMAC-derived from master key — cryptographically sound key separation |
| 3 | SQL statement_timeout=60s + lock_timeout=10s per PostgreSQL connection |
| 4 | CORS wildcard `*` blocked at runtime in production (dual check in settings.py + main.py) |
| 5 | OpenAPI docs disabled in production (`docs_enabled = not is_production`) |
| 6 | Token revocation middleware checks JWT blacklist on every authenticated request |
| 7 | CSRF middleware present and functional for cookie-based sessions |
| 8 | Systemd units use `NoNewPrivileges=true`, `PrivateTmp=true`, empty `CapabilityBoundingSet` |
| 9 | Terraform server type restricted to cx23/cx33 only — prevents expensive provisioning |
| 10 | Webhook event deduplication via `UniqueConstraint("provider", "event_id")` — sound design |
| 11 | Subscription state machine enforces allowed transitions with stale-event detection |
| 12 | Security headers complete: HSTS, X-Content-Type-Options, X-Frame-Options, CSP, Referrer-Policy, Permissions-Policy |

---

## Recommended Hardening Plan

### P0 — Fix Immediately (< 1 hour total)

| # | Finding | Action | Effort |
|---|---------|--------|--------|
| 1 | C-1: Root Gunicorn | Set `user = "securewave"`, `group = "securewave"` in `gunicorn.conf.py` | 2 min |
| 2 | C-2: SSH CIDR | Change `ssh_allowed_cidrs` default to `[]` in `variables.tf` | 5 min |
| 3 | C-3: `/metrics` unauthed | Add `Depends(get_current_user)` + admin check | 5 min |
| 4 | H-WG-4: Shell injection in remove_peer | Add `_validate_peer_inputs` call + `shlex.quote()` | 10 min |
| 5 | H-PAY-3: Audit log IDOR | Add `is_admin` gate to `/api/diagnostics/events` | 5 min |
| 6 | H-PAY-4: `/version` leak | Gate on auth or remove `GIT_SHA`/`ENVIRONMENT` | 5 min |
| 7 | H-AUTH-4: logout no-op | Implement token revocation in `logout` and `logout-all` | 15 min |

### P1 — Fix This Sprint (< 1 day total)

| # | Finding | Action | Effort |
|---|---------|--------|--------|
| 8 | H-AUTH-1: Admin promotion | Remove login-time promotion, use management CLI | 20 min |
| 9 | H-AUTH-2: 2FA password oracle | Return 401 for all missing-second-factor states | 30 min |
| 10 | H-AUTH-3: Token leak in update-email | Add `_set_auth_cookies()`, revoke old tokens | 20 min |
| 11 | H-WG-2/WG-3: Base64 encryption fallback | Remove fallback, fail hard at startup | 15 min |
| 12 | H-WG-5: Local RCE via `_should_run_local` | Remove local path or restrict to `ENV=development` + `shell=False` | 30 min |
| 13 | H-WG-6: Secret in `sudo env` | Pipe secret via stdin to provisioning script | 30 min |
| 14 | H-PAY-1: Duplicate webhook endpoints | Remove `/api/billing/webhooks/stripe`, keep `/api/payments/stripe/webhook` | 15 min |
| 15 | H-INF-1: Shell injection in env loader | Replace with `set -a; source .env.hetzner; set +a` | 2 min |
| 16 | M-INF-4: Nginx rate limiting | Add `limit_req_zone` + `limit_req` directives | 15 min |
| 17 | M-INF-6: umask 0 | Set `umask = 0o027` in `gunicorn.conf.py` | 2 min |

### P2 — Fix This Month

| # | Finding | Action | Effort |
|---|---------|--------|--------|
| 18 | H-WG-1: SSH TOFU | Pre-populate per-server known_hosts fingerprints | 2 hr |
| 19 | M-WG-1: Device limit TOCTOU | `SELECT FOR UPDATE` or DB constraint | 1 hr |
| 20 | M-WG-2: HTTP management API | Switch to HTTPS with cert validation | 2 hr |
| 21 | M-INF-1: In-memory rate limiting | Deploy Redis, set `REDIS_URL` | 1 hr |
| 22 | M-AUTH-2: Fernet base64 fallback | Remove fallback in all environments | 30 min |
| 23 | M-AUTH-3: Refresh token in body | Accept only from HttpOnly cookie | 30 min |
| 24 | M-INF-2: CSRF Authorization bypass | Validate `Bearer <token>` format, not just header presence | 30 min |
| 25 | H-INF-3: Test file secret scanning | Remove test file exemptions from pre-commit hook | 15 min |
| 26 | H-INF-2: Migration in Docker CMD | Move to init container / pre-deploy step | 1 hr |
| 27 | M-INF-7: Silent .env fallback | Fail hard if `.env` missing, remove copy fallback | 10 min |

### P3 — Architectural (Backlog)

| # | Finding | Action | Effort |
|---|---------|--------|--------|
| 28 | WG-11: Client private keys stored server-side | Move to client-side key generation | 1-2 weeks |
| 29 | Router duplication (billing vs payments) | Consolidate into single router stack | 1 day |
| 30 | Terraform remote state | Configure S3-compatible backend with encryption | 2 hr |
| 31 | WG-12: IP allocator race | Atomic allocation with `SELECT FOR UPDATE` | 2 hr |
| 32 | Token revocation scalability | Redis-backed bloom filter for revoked JTIs | 1 day |

---

## Attack Chain Analysis

### Chain 1: Unauthenticated → Admin (3 steps)

```
1. GET /version → confirm production, get GIT_SHA
2. GET /metrics → enumerate session counts, server health
3. GET /api/billing/stripe-status → confirm payment config
4. Register account → brute-force 2FA-enrolled admin password
   (200 + requires_2fa vs 401 = password oracle, no lockout on 200 path)
5. Compromise ADMIN_EMAIL env var → login = permanent admin
```

**Blocked by:** Strong password policy (10+ chars, complexity), env var access control.
**Not blocked by:** Rate limiting (in-memory, per-worker), account lockout (doesn't trigger on 200 path).

### Chain 2: Authenticated User → All WG Private Keys

```
1. Register free account
2. Exploit device limit TOCTOU → register excess devices
3. Find SQLi or IDOR to read wireguard_peers table
4. If WG_ENCRYPTION_KEY absent: base64-decode private_key_encrypted
5. If WG_ENCRYPTION_KEY present: need env var access (see Chain 3)
```

**Blocked by:** SQLAlchemy ORM (parameterized queries), Fernet encryption in production.
**Not blocked by:** Base64 fallback in non-production environments.

### Chain 3: RCE → Total Compromise

```
1. Find RCE (SSRF, deserialization, path traversal in any route)
2. Gunicorn runs as root → instant root shell
3. Read /opt/securewave/.env → JWT_SECRET, WG_ENCRYPTION_KEY, STRIPE_SECRET
4. Decrypt all WG private keys from DB
5. Forge admin JWT → full API access
6. Read Stripe webhook secret → inject billing events
```

**Blocked by:** Finding the initial RCE vector.
**Not blocked by:** Gunicorn running as root (no privilege separation).

---

## Methodology

Four parallel audit streams, each analyzing a distinct domain:

1. **Authentication & Session Management** — auth routes, JWT service, CSRF middleware, password policy, lockout, 2FA, admin access
2. **Device Provisioning & VPN** — device CRUD, WireGuard key generation, SSH-based peer management, config generation, credential service
3. **Payments & API Exposure** — Stripe checkout/webhooks, subscription state machine, admin endpoints, rate limiting, CORS, error handling, unauthenticated surface
4. **Infrastructure & Deployment** — database session, nginx, systemd, Terraform, fail2ban, Dockerfiles, deployment scripts, secrets management, logging

Each stream produced a detailed sub-report with file/line references, exploitation scenarios, and prioritized remediation. This document consolidates and de-duplicates all findings.

### Files Audited

| Domain | Files |
|--------|-------|
| Auth | `routes/auth.py`, `services/auth_service.py`, `services/jwt_service.py`, `utils/password_policy.py`, `models/user.py`, `models/jwt_blacklist_token.py` |
| VPN/Devices | `routes/devices.py`, `routes/vpn.py`, `services/vpn_credential_service.py`, `services/wireguard_server_manager.py`, `services/wireguard_service.py`, `services/vpn_peer_manager.py`, `services/device_service.py`, `models/wireguard_peer.py`, `models/vpn_connection.py`, `models/vpn_server.py`, `utils/input_sanitizer.py` |
| Payments | `routers/payment_stripe.py`, `routes/billing.py`, `services/payment_webhooks.py`, `services/subscription_state_machine.py`, `models/subscription.py`, `models/payment_idempotency_key.py`, `models/webhook_event_receipt.py`, `routes/diagnostics.py`, `routes/servers.py`, `routes/tools.py`, `routers/admin.py` |
| Infra | `main.py`, `config/settings.py`, `database/session.py`, `gunicorn.conf.py`, `nginx/securewave_preview.conf`, `infrastructure/hetzner/main.tf`, `infrastructure/hetzner/variables.tf`, `infrastructure/fail2ban/jail.local`, `Dockerfile`, `Dockerfile.simple`, `scripts/deploy_backend.sh`, `scripts/pre-commit-hook.sh`, `load_hetzner_env.sh`, `start_site.sh`, systemd units |

### Not Audited

- Flutter/Dart client-side code (out of scope)
- Remote provisioning scripts on VPN servers (`securewave-openvpn-issue-client`, etc.)
- PayPal webhook signature verification internals (`services/paypal_service.py`)
- Alembic migration files for irreversible schema changes
- Live `.env` file contents on VPS
- TLS certificate pinning in mobile apps
- Backup verification / restore testing

---

*Sub-reports with full line-by-line analysis available in `artifacts/sonnet_*_security_audit*.md`*
