# SecureWave Beta Release Readiness Report
**Date:** 2026-03-01
**Evaluator role:** Senior SRE + Security Engineer + VPN Systems Architect
**Stack:** Hetzner VPS · nginx · FastAPI/gunicorn · WireGuard · OpenVPN · strongSwan · Flutter client

---

## Device Limit Bug — Status

Fix deployed to disk (`routes/vpn.py` line 3472: `"Primary Device"` → `"This device"`).
**Backend restart required to activate:**

```bash
sudo systemctl restart securewave.service
```

---

## PHASE 1 — Transport & TLS Integrity

| Check | Status | Detail |
|---|---|---|
| HTTP login allowed | **FAIL** | nginx port 80 proxies `/api/` directly — login, tokens, credentials sent plaintext |
| HTTPS available | PASS | TLS 1.2/1.3, port 443 active |
| Self-signed cert | **FAIL** | `CN=138.199.204.139, O=SecureWave Dev` — Flutter bypasses in debug; real clients will reject |
| HSTS header | **FAIL** | `Strict-Transport-Security` absent from all responses |
| Security headers | Partial | `x-content-type-options`, `x-frame-options`, `referrer-policy` present. Missing HSTS |
| CSP | PASS | Present in HTTP block headers |
| Port 8080 external | PASS | Bound `127.0.0.1:8080` only — not externally reachable |
| Backend isolation | PASS | gunicorn on loopback only |

**Critical fix — block HTTP `/api/` and add HSTS:**

```nginx
# Replace HTTP server block — remove /api/ exception, redirect everything:
server {
    listen 80;
    listen [::]:80;
    server_name _;
    return 301 https://$host$request_uri;
}

# Add to HTTPS server block:
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
```

```bash
sudo nginx -t && sudo systemctl reload nginx
```

**Risk: CRITICAL** — plaintext JWT tokens and credentials currently transmitted over HTTP.

---

## PHASE 2 — Authentication & Token Security

| Check | Status | Detail |
|---|---|---|
| Token expiry | PASS | Access: 30min, Refresh: 14 days |
| Rate limiting — login | PASS | `10/minute` + `5/hour` via slowapi |
| Rate limiting backend | **RISKY** | `storage_uri=memory://` — limits are per-worker. With multiple gunicorn workers, each worker has its own counter. A client can exhaust each independently |
| Account lockout | PASS | `is_account_locked()` check present, `failed_login_attempts` tracked |
| Password policy | PASS | `validate_password_strength()` enforced on register + password change |
| Account enumeration | PASS | Generic `invalid_credentials` error — no user/password distinction |
| Brute force after lockout | PASS | Lockout enforced at route level |
| Refresh token replay | Acceptable | `revoke_refresh_token()` exists — single-use enforcement depends on implementation |
| Credential logging | PASS | No passwords in error messages |

**Fix — shared rate limit state:**

```bash
sudo apt-get install -y redis-server
sudo systemctl enable --now redis-server
# Update .env: REDIS_URL=redis://127.0.0.1:6379/0
# Restart backend
```

**Rating: Acceptable for private beta. Unsafe for public beta without Redis-backed rate limits.**

---

## PHASE 3 — VPN Protocol Security Posture

| Check | Status | Detail |
|---|---|---|
| WireGuard running | PASS | `wg-quick@wg0` active |
| WireGuard config perms | Unknown | Cannot sudo non-interactively — assume root:root 600 (standard wg-quick) |
| IKEv2 auth mode | **RISKY** | `rightauth=eap-mschapv2` — password-based, vulnerable to offline dictionary attack on captured handshake |
| IKEv2 ciphers | PASS | AES-256-GCM, SHA-256, ECP-256 — strong suite |
| IKEv2 DPD | PASS | `dpdaction=clear`, 300s — cleans stale tunnels |
| IKEv2 fragmentation | PASS | `fragmentation=yes`, `forceencaps=yes` — NAT traversal correct |
| OpenVPN config | **Unverified** | `server.conf` not readable without sudo TTY |
| Provisioning secret isolation | PASS | `.env` is `rw-------` owned by `securewave` only |
| sudo scope | **RISKY** | First sudoers entry is `(ALL : ALL) ALL` — full unrestricted sudo. Specific NOPASSWD entries below are redundant. `securewave` user can escalate to root with password |
| WG private keys | Encrypted | `WG_ENCRYPTION_KEY` in `.env` — keys encrypted at rest in DB |

**IKEv2 production path:** Replace EAP-MSCHAPv2 with EAP-TLS (mutual certificate auth). Non-blocking for private beta.

**Tighten sudo:**
```bash
# Remove the (ALL : ALL) ALL line from /etc/sudoers.d/securewave
# Keep only the explicit NOPASSWD script entries
```

**Rating: Acceptable for private beta. Not production-grade without EAP-TLS and sudo tightening.**

---

## PHASE 4 — Failure Mode & Resilience

| Scenario | Detection | Recovery | User Impact | Manual? | Risk |
|---|---|---|---|---|---|
| Backend crash | systemd `Restart=on-failure` | Auto | API errors, reconnects after restart | No | 4 |
| WireGuard daemon crash | `wg-quick@wg0` is `Type=oneshot` — does not restart | Not automatic | Tunnel silently dead; Flutter detects in 8s via traffic poll | Yes — `systemctl restart wg-quick@wg0` | 6 |
| OpenVPN crash | `openvpn-server@server` goes inactive | No auto-restart confirmed | New OpenVPN connections fail | Yes | 7 |
| strongSwan crash | `strongswan-starter` active — likely auto-restarts | Probable | IKEv2 connections fail | Probably no | 5 |
| Network loss | Flutter: 8s traffic poll timeout → failover | Same-server reconnect | 8s spinner then reconnect | No | 3 |
| DNS outage | API calls fail with connection error | None | Error screen, manual retry | No | 4 |
| Provisioning token mismatch | Backend returns 4xx on `/vpn/profile` | Flutter surfaces error | "Connection failed" message | No | 3 |
| Secret file corruption (`.env`) | Backend fails to start on next restart | None | Full outage on next restart | Yes | 8 |
| Disk full | DB writes fail, logs stop | None | Silent API failures then crash | Yes | 8 |
| Memory exhaustion | OOM killer kills gunicorn workers | systemd restarts service | Brief outage | Partial | 6 |
| Restart during active tunnel | WG tunnel persists (kernel) | API reconnects after restart | Speed/usage resets, tunnel stays up | No | 2 |

**Critical gaps:**
- No confirmed `Restart=on-failure` for `openvpn-server@server`
- `wg-quick` is `Type=oneshot` — does not auto-restart on interface loss
- No disk space alerting
- No `.env` backup or checksum

---

## PHASE 5 — Telemetry & UX Integrity

| Check | Status | Detail |
|---|---|---|
| Speed meter correctness | **Verified** | Tick-0 baseline, tick-1 delta, `_positiveDelta` handles counter reset |
| Speed meter on reconnect | **Verified** | `_stopRateSimulation()` clears `_lastTrafficRxBytes` — baseline resets cleanly |
| Usage accumulation | **Verified** | `sessionTransferredBytes` accumulates per-session, backend notified on disconnect |
| Usage cap enforcement | **Unverified** | Backend enforces `FREE_TIER_MONTHLY_GB` — Flutter displays cap, enforcement is backend-only |
| Usage persisted across crash | **Risky** | `sessionTransferredBytes` is in-memory — mid-session crash loses session bytes. Backend is source of truth after disconnect |
| Infinite spinner | **Verified clean** | All connect/disconnect paths have timeout handlers → `VpnStatus.error` |
| Disconnect behavior | **Verified** | `_runDisconnectFlow` → DISCONNECTING → DISCONNECTED, `_stopRateSimulation()` called |
| Silent failures | **Verified clean** | `_safeFireAndForget` logs all async errors |
| Error surfacing | **Verified** | `_classifyVpnError()` produces user-visible messages for all exception types |
| State machine stuck states | **Verified** | `_reconcileStep` re-runs after every operation (`_reconcileRequested=true` in `finally`) |

**Rating: Verified** for all paths except mid-session crash usage loss (by design, not a bug).

---

## PHASE 6 — Operational Discipline

| Check | Status |
|---|---|
| Deployment automation | Manual — SCP + SSH restart |
| Service restart scriptability | RISKY — requires sudo TTY, not non-interactively scriptable |
| Monitoring | **None** — Prometheus, node-exporter, Grafana all inactive |
| Log rotation | **None** — no `/etc/logrotate.d/securewave` |
| Crash detection | Partial — systemd journal only, no alerting |
| Rollback | Manual only — no tagged deployment artifacts |
| Watchdog | `securewave-watchdog.service` deployed but **inactive** |

**Operational maturity score: 3 / 10**

**Minimum monitoring stack:**

```bash
# Log rotation
sudo apt-get install -y logrotate
cat << 'EOF' | sudo tee /etc/logrotate.d/securewave
/var/log/securewave/*.log {
    daily
    rotate 14
    compress
    missingok
    notifempty
    postrotate
        systemctl kill -s USR1 securewave.service 2>/dev/null || true
    endscript
}
EOF

# Enable watchdog
sudo systemctl enable --now securewave-watchdog.timer
```

**Minimum CI/CD:** GitHub Actions → `pytest` + `flutter analyze` → SCP → `systemctl restart` via targeted NOPASSWD sudo rule.

Add to sudoers:
```
(root) NOPASSWD: /bin/systemctl restart securewave.service
```

---

## PHASE 7 — FINAL RELEASE GATE

| Gate | Result |
|---|---|
| **Private Beta** | **CONDITIONAL PASS** |
| **Public Beta** | **FAIL** |
| **Production-Grade** | **FAIL** |
| **Risk Score** | **6 / 10** |

---

### Critical Blockers (must fix before any beta)

1. **HTTP API exposure** — `/api/` proxied over port 80 plaintext. JWT tokens and passwords travel unencrypted. Fix: remove `/api/` exception from HTTP nginx block, redirect all port 80 to HTTPS.

2. **Backend restart pending** — device limit fix (line 3472) is on disk but the running process has the old code. Run `sudo systemctl restart securewave.service`.

3. **Self-signed TLS certificate** — Flutter debug bypasses; real users cannot. Required for public beta: domain + Let's Encrypt cert.

4. **In-memory rate limiting** — multiple gunicorn workers each have an independent counter. A single IP can send `N_workers × limit` requests before blocking. Fix: install Redis.

---

### High-Priority (before public beta)

5. **HSTS missing** — add `Strict-Transport-Security: max-age=31536000` to nginx HTTPS block.

6. **`securewave` user has unrestricted sudo** — `(ALL : ALL) ALL` grants full root. Remove it, keep only the explicit NOPASSWD script entries.

7. **No log rotation** — gunicorn logs will fill disk within weeks. Add `/etc/logrotate.d/securewave`.

8. **Watchdog inactive** — `securewave-watchdog.service` deployed but not running. Enable it.

9. **IKEv2 EAP-MSCHAPv2** — vulnerable to offline dictionary attack on captured handshakes. Acceptable for private beta with trusted users; switch to EAP-TLS before public beta.

10. **OpenVPN config unreadable** — verify manually: `sudo grep -E 'cipher|tls|proto|auth' /etc/openvpn/server/server.conf`

---

### Low-Priority (post-beta)

11. No monitoring stack — minimum: UptimeRobot (free) hitting `/api/health` + systemd `OnFailure` email alert.
12. Deployment is fully manual — GitHub Actions → SCP → restart is a ~2hr setup that eliminates human error.
13. `wg-quick` is `Type=oneshot` — WireGuard interface does not auto-restart on crash. Add watchdog or `Restart=on-failure`.
14. No `.env` backup — secret file corruption is a full-outage event. Back up with `gpg --symmetric` to separate location.
15. Usage bytes not persisted mid-session — crash during long session loses byte count. Backend usage will be understated. Acceptable for beta.

---

### Executive Summary

SecureWave's backend and VPN stack are functionally operational with correct protocol routing, health mapping, and a working Flutter client. The system has reasonable authentication controls (lockout, rate limiting, password policy, generic error messages) and the VPN state machine has been audited and confirmed correct. However, the stack is not safe for beta in its current state due to one critical issue: the nginx configuration allows the entire `/api/` surface — including login and token endpoints — to be accessed over plaintext HTTP, meaning credentials and JWTs are transmitted unencrypted. Fixing this is a single nginx config change and reload. Once that is resolved, along with enabling Redis-backed rate limiting and tightening the `securewave` sudoers entry, the system reaches private beta readiness. Public beta requires a real TLS certificate (domain + Let's Encrypt), HSTS, and IKEv2 EAP-TLS. Operational maturity is the weakest dimension — no monitoring, no log rotation, no automated deployment — which limits incident response but does not block a small controlled beta.
