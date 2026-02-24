# SecureWave Security Whitepaper

**Version:** 1.0
**Date:** February 2026
**Audience:** Security researchers, enterprise evaluators, compliance teams

> This document summarizes SecureWave's security architecture, encryption standards, data handling practices, and operational security controls. It is intended for technical review and trust evaluation.

---

## 1. Executive Summary

SecureWave is a multi-platform VPN service providing encrypted network tunnels using WireGuard as its primary protocol. The system is designed with the following security principles:

- **Minimal data collection** — only what is required to operate the service
- **No-logs by design** — browsing activity, DNS queries, and traffic content are structurally absent from our systems
- **Defense in depth** — multiple independent security controls at each layer
- **Open protocol stack** — WireGuard is an audited, open-source protocol with a minimal codebase (~4,000 lines)

---

## 2. VPN Protocol and Cryptography

### 2.1 Primary Protocol: WireGuard

SecureWave uses WireGuard as its primary VPN protocol across all platforms.

| Property | Specification |
|----------|--------------|
| Key exchange | Noise Protocol Framework (Noise_IKpsk2_25519_ChaChaPoly_BLAKE2s) |
| Public key algorithm | Curve25519 (ECDH) |
| Symmetric encryption | ChaCha20-Poly1305 (AEAD) |
| MAC | Poly1305 |
| Hash function | BLAKE2s |
| Session key rotation | Every ~180 seconds (handshake renegotiation) |
| Replay protection | Sliding window counter (2,000 packets) |

WireGuard's cryptographic design provides forward secrecy: past session traffic cannot be decrypted even if a long-term private key is later compromised.

### 2.2 Protocol Selector

SecureWave supports fallback protocols for network environments that block WireGuard:

| Protocol | Encryption | Use case |
|----------|-----------|---------|
| WireGuard (primary) | ChaCha20-Poly1305 | Default, all platforms |
| OpenVPN | AES-256-GCM | Compatibility mode |
| IKEv2/IPsec | AES-256-GCM | Mobile reconnect resilience |
| L2TP/IPsec | AES-256-CBC | Legacy environments |
| TCP Fallback | TLS 1.3 wrap | Firewall bypass |

Protocol selection is automatic (auto-detect) or user-configurable.

### 2.3 DNS

DNS queries made through the VPN tunnel are resolved by SecureWave's own DNS servers using DNS-over-HTTPS (DoH) or DNS-over-TLS (DoT). DNS queries are not logged and do not leave the encrypted tunnel.

---

## 3. Authentication and Access Control

### 3.1 User Authentication

| Component | Implementation |
|-----------|---------------|
| Password hashing | bcrypt, cost factor 12 |
| Token format | JSON Web Token (JWT), signed with HS256 |
| Access token lifetime | 30 minutes |
| Refresh token lifetime | 14 days |
| Token binding | Refresh tokens are bound to IP address and User-Agent; reuse from a different context invalidates the session |
| Token revocation | JTI (JWT ID) blacklisting; revocation checked on every request |
| Two-factor authentication | TOTP (RFC 6238 / Google Authenticator compatible); backup codes generated at enrollment |
| Session lockout | Account locked for 15 minutes after 5 consecutive failed login attempts |

### 3.2 API Security

| Control | Implementation |
|---------|---------------|
| HTTPS enforcement | TLS 1.3 enforced in production; HTTP rejected with 400 |
| CSRF protection | Double-submit cookie pattern (X-CSRF-Token header + csrf_token cookie) |
| Rate limiting | Login: 10 requests/minute; Registration: 5 requests/hour; API: endpoint-specific limits |
| Input validation | Pydantic schema validation on all request bodies; custom sanitization for WireGuard keys, device names, IP ranges |
| SQL injection | SQLAlchemy ORM exclusively; no raw SQL query construction |
| CORS | Origin allowlist; no wildcards in production |

### 3.3 Security Headers

| Header | Value |
|--------|-------|
| Content-Security-Policy | `default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; object-src 'none'; frame-ancestors 'none'` |
| Strict-Transport-Security | `max-age=63072000; includeSubDomains; preload` (2 years) |
| X-Content-Type-Options | `nosniff` |
| X-Frame-Options | `DENY` |
| Referrer-Policy | `strict-origin-when-cross-origin` |
| Permissions-Policy | `geolocation=(), microphone=(), camera=()` |

---

## 4. WireGuard Peer Key Management

### 4.1 Key Generation

Each device registered to a user account receives a unique WireGuard key pair:
- Private key is generated client-side or server-side (platform-dependent) using cryptographically secure random number generation
- Public key is registered with the server and stored in the VPN server configuration

### 4.2 Key Storage — Server Side

| Data | Storage method |
|------|---------------|
| WireGuard server private key | Fernet encryption (AES-128-CBC + HMAC-SHA256) using `WG_ENCRYPTION_KEY` |
| WireGuard peer public keys | Stored in plaintext (public keys are not secret) |
| OpenVPN/IKEv2/L2TP credentials | Fernet encryption at rest |
| TOTP secrets | Fernet encryption at rest |

`WG_ENCRYPTION_KEY` is a Fernet key stored as an environment variable, never committed to version control. The application will refuse to start in production if this key is absent.

### 4.3 Key Rotation

- **Session key rotation:** WireGuard re-handshakes every ~180 seconds automatically
- **Device key rotation:** Users may force-rotate their device key pair at any time via account settings
- **Server key rotation:** Scheduled server-side key rotation policy is configurable via `SERVER_KEY_ROTATION_DAYS` [TODO: enforce rotation schedule in automation — see architecture review]

### 4.4 VPN Profile Delivery

WireGuard configuration profiles are delivered over TLS 1.3. Profiles have a configurable TTL (default: 3,600 seconds). Expired profiles are rejected by the server.

---

## 5. Infrastructure Security

### 5.1 Server Hardening

VPN servers (Hetzner Cloud) are provisioned with:

- Ubuntu 22.04 LTS (security patched)
- UFW firewall: only ports 22 (SSH) and 51820 (WireGuard UDP) open
- SSH: key-based authentication only; password authentication disabled
- fail2ban: SSH brute force protection
- Kernel hardening: SYN cookies, RP filter, ICMP restrictions enabled
- IP forwarding enabled only for WireGuard traffic
- NAT/masquerading for VPN egress traffic

### 5.2 API Server Hardening

- TLS termination at nginx (TLS 1.2 + 1.3, strong cipher suite, OCSP stapling)
- Application runs as unprivileged user in Docker container
- Environment secrets loaded at runtime; not baked into images
- Connection pooling with statement timeout (60s), lock timeout (10s)

### 5.3 Network Segmentation

- VPN servers do not have direct access to the API database
- API server communicates with VPN servers over SSH for peer management operations
- WireGuard server registration and key sync occurs via authenticated API calls

### 5.4 Access Controls

- Infrastructure access requires SSH key authentication
- Database access requires application credentials (no direct external database access)
- Admin API endpoints require authenticated user with `is_admin` flag [TODO: enforce role validation — see architecture review P0 items]

---

## 6. Application Security

### 6.1 Dependency Management

| Category | Practice |
|----------|---------|
| Python dependencies | Pinned versions in `requirements_production.txt` |
| Known vulnerable packages | `passlib==1.7.4` identified; replacement scheduled before GA [see architecture review] |
| Secret scanning | Gitleaks runs in CI on every push; pre-commit hook also enforces scanning |
| Dependency audit | [TODO: integrate `pip audit` or `safety` into CI pipeline] |

### 6.2 Secure Coding Practices

- All authentication and authorization logic is centralized in service classes; route handlers delegate to services
- Payment webhook signatures verified using Stripe SDK's `construct_event()` with timestamp tolerance enforcement
- Idempotency enforced for payment operations using SHA256 request fingerprinting
- Log redaction filters strip Stripe API keys, WireGuard private keys, bearer tokens, and email addresses from log output

### 6.3 Mobile Client Security

| Platform | Credential storage | Certificate pinning |
|----------|-------------------|-------------------|
| iOS | Keychain (via flutter_secure_storage) | [TODO: implement — see architecture review P0] |
| Android | EncryptedSharedPreferences (via flutter_secure_storage) | [TODO: implement — see architecture review P0] |
| Windows | Credential Manager / libsecret | [TODO: implement] |
| Linux | libsecret | [TODO: implement] |

---

## 7. No-Logs Implementation

SecureWave's no-logs commitment is implemented structurally, not merely by policy:

| What we don't log | Technical reason |
|-------------------|-----------------|
| Browsing history | No HTTP inspection at tunnel layer; WireGuard encrypts all content end-to-end |
| DNS queries | DNS resolved by our DoH/DoT servers; query logs disabled at the resolver |
| Originating IP | Connection-phase IP is used for authentication only and not persisted after tunnel establishment |
| Traffic content | WireGuard encryption prevents server from reading tunnel contents |
| Connection patterns | Session metadata is aggregated within 24 hours; individual session records are not retained |

Audit basis for no-logs claim: [TODO: third-party no-logs audit is recommended before claiming this publicly. Commission an independent auditor.]

---

## 8. Incident Response

### 8.1 Response Tiers

| Severity | Definition | Response time |
|----------|-----------|--------------|
| Critical | Confirmed breach of user data; infrastructure compromise | 2 hours containment; 72 hours user notification |
| High | Suspected breach; active vulnerability being exploited | 4 hours investigation |
| Medium | Unconfirmed vulnerability; failed attack | 24 hours |
| Low | Security advisory; no active exploitation | 7 days |

### 8.2 User Notification

In the event of a data breach affecting user personal data:
- Affected users notified by email within 72 hours of confirmation
- Regulatory notification per GDPR Article 33 where applicable
- Incident report published in trust center [PLACEHOLDER — trust center URL]

### 8.3 Responsible Disclosure

Security researchers may report vulnerabilities to: security@securewavevpn.com

[PLACEHOLDER — consider publishing a formal security.txt at /.well-known/security.txt and a bug bounty program]

---

## 9. Compliance and Certifications

| Standard / Regulation | Status |
|----------------------|--------|
| GDPR | Privacy policy addresses GDPR rights; data processing agreements with Stripe and PayPal in place |
| CCPA | Privacy policy addresses California consumer rights |
| PCI DSS | Payment card data handled exclusively by Stripe (Level 1 PCI DSS certified); SecureWave does not store card numbers |
| SOC 2 | [TODO: target for post-GA audit] |
| Independent security audit | [TODO: commission before GA; recommended annually thereafter] |
| No-logs audit | [TODO: commission before marketing "audited no-logs" claim] |

---

## 10. Known Security Gaps (Open Items)

The following items have been identified in the architecture review and are scheduled for remediation:

| Finding | Severity | Target |
|---------|----------|--------|
| `passlib==1.7.4` — abandoned dependency | Critical | Before GA |
| No certificate pinning in Flutter client | High | Before GA |
| Admin role enforcement missing on `/api/admin/*` | High | Before GA |
| Token blacklist TTL cleanup not implemented | Medium | Sprint 2 |
| No automated WireGuard key rotation schedule | Medium | Sprint 2 |
| CSP allows `img-src data:` | Medium | Sprint 2 |
| Third-party no-logs audit not commissioned | High | Before marketing claim |

---

*For security inquiries: security@securewavevpn.com*
*This document is internal-only until third-party audit is complete.*
