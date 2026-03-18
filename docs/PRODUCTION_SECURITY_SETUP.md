# SecureWave Production Security Setup

## Prerequisites

| Service | Min version | Notes |
|---------|-------------|-------|
| Python | 3.11+ | argon2-cffi required |
| Redis | 6.x+ | Required for multi-worker rate limiting |
| PostgreSQL | 14+ | SQLite not supported in production |
| Nginx | 1.18+ | For rate limiting zones and TLS termination |
| Gunicorn | 21+ | Must not run as root (use `securewave` user) |

---

## Required Environment Variables

All must be set in `/etc/securewave/env` (permissions: `600`, owner: `root:root`).

### Core

```
ENVIRONMENT=production
DATABASE_URL=postgresql://securewave:<password>@localhost:5432/securewave
REDIS_URL=redis://localhost:6379/0
APP_URL=https://securewaveapp.com
API_BASE_URL=https://api.securewaveapp.com/api
```

### Authentication

```
JWT_SECRET=<64+ char random hex>
ACCESS_TOKEN_SECRET=<64+ char random hex>   # optional; overrides JWT_SECRET for access tokens
REFRESH_TOKEN_SECRET=<64+ char random hex>  # optional; overrides JWT_SECRET for refresh tokens
AUTH_ENCRYPTION_KEY=<Fernet key>            # generate: python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"
WG_ENCRYPTION_KEY=<Fernet key>             # same format
SECUREWAVE_PROVISIONING_TOKEN_SECRET=<64+ char random hex>
```

### WireGuard / VPN

```
VPN_SERVER_ENDPOINT=vpn.securewaveapp.com:51820
WG_SSH_KEY_PATH=/opt/securewave/.ssh/id_ed25519
WG_API_KEY=<random hex>
WG_ENCRYPTION_KEY=<Fernet key>
```

### Stripe

```
STRIPE_SECRET_KEY=sk_live_...
STRIPE_PUBLISHABLE_KEY=pk_live_...
STRIPE_WEBHOOK_SECRET=whsec_...
STRIPE_PRICE_BASIC_MONTHLY=price_...
STRIPE_PRICE_PREMIUM_MONTHLY=price_...
STRIPE_PRICE_ULTRA_MONTHLY=price_...
PAYMENTS_MOCK=false
```

### Email

```
EMAIL_PROVIDER=smtp
SMTP_HOST=smtp.example.com
SMTP_PORT=587
SMTP_USER=noreply@securewaveapp.com
SMTP_PASSWORD=<password>
FROM_EMAIL=noreply@securewaveapp.com
```

### Security flags

```
DEMO_MODE=false
WG_MOCK_MODE=false
WG_AUTO_REGISTER_PEERS=true
ALLOW_SQLITE_PRODUCTION=   # must be absent or false
```

---

## Redis Setup

Redis is **required** in production. Memory-based rate limiting is per-process and does not work with multiple Gunicorn workers.

```bash
apt install redis-server
systemctl enable --now redis-server
# Bind to localhost only (default in Ubuntu 22.04)
grep "^bind" /etc/redis/redis.conf   # should show: bind 127.0.0.1 ::1
```

Set `REDIS_URL=redis://127.0.0.1:6379/0` in `/etc/securewave/env`.

The application will **refuse to start** in production if `REDIS_URL` is not set.

---

## Nginx Rate Limiting

The production nginx config (`infra/nginx/securewave_prod.conf`) defines three zones:

| Zone | Rule | Applies to |
|------|------|------------|
| `api_auth` | 5 req/min | `/api/auth/login`, `/api/auth/register` |
| `api_webhook` | 30 req/min | `/api/payments/stripe/webhook` |
| `api_general` | 100 req/s, burst=50 | All other `/api/` paths |

Rate-limited requests return **429** (not nginx default 503).

Deploy the nginx config:
```bash
# Render placeholders
export SERVER_NAMES="securewaveapp.com api.securewaveapp.com"
export UPSTREAM_HOST=127.0.0.1
export UPSTREAM_PORT=8080
export SSL_CERT=/etc/letsencrypt/live/securewaveapp.com/fullchain.pem
export SSL_KEY=/etc/letsencrypt/live/securewaveapp.com/privkey.pem
bash scripts/ops/render_nginx_conf.sh
nginx -t && systemctl reload nginx
```

---

## CSRF Protection

CSRF is enforced on all state-changing API endpoints when an `access_token` cookie is present.

**Exempt paths** (stateless, no cookie required):
- `POST /api/auth/login`
- `POST /api/auth/register`
- `POST /api/auth/refresh`
- `POST /api/auth/revoke-token`
- `POST /api/auth/password-reset/request`
- `POST /api/auth/password-reset/confirm`

**Bypass condition**: The request is NOT blocked if `Authorization: Bearer <token>` exactly matches the `access_token` cookie — this proves the caller can read the cookie (same-origin).

Any other `Authorization` header alone does **not** bypass CSRF.

---

## Password Hashing

- **Primary**: Argon2id via `argon2-cffi` (`time_cost=3, memory_cost=65536, parallelism=2`)
- **Fallback**: bcrypt for legacy hashes; flagged for rehash on next login
- **Input cap**: 1000 bytes — larger inputs raise `ValueError`
- **Upgrade path**: `needs_rehash(hash)` returns `True` for bcrypt hashes; rehash on successful login

---

## WireGuard Key Security

- Private keys are encrypted with Fernet (`WG_ENCRYPTION_KEY`) before DB storage
- **Production fails to start** if `WG_ENCRYPTION_KEY` is absent or invalid
- Key rotation: private key is passed via **stdin** to the SSH remote command, never embedded in the command string
- Local execution (`shell=True`) is **blocked in production** — requires `TESTING=true` or `LOCAL_WG=true`

---

## Env File Permissions

`/etc/securewave/env` must be `600` owned by `root:root`. The deploy script enforces this automatically:

```bash
bash scripts/ops/hetzner_deploy.sh
```

Manual enforcement:
```bash
chmod 600 /etc/securewave/env
chown root:root /etc/securewave/env
```

---

## Gunicorn

Must **not** run as root. Use the `securewave` system user:

```
User=securewave
Group=securewave
```

Verify: `ps aux | grep gunicorn` — UID must not be `root`.

---

## Key Generation Commands

```bash
# Fernet key (for WG_ENCRYPTION_KEY, AUTH_ENCRYPTION_KEY)
python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"

# JWT secret (64-char hex)
python3 -c "import secrets; print(secrets.token_hex(64))"

# SSH key for WireGuard peer registration
ssh-keygen -t ed25519 -f /opt/securewave/.ssh/id_ed25519 -N ""
chown securewave:securewave /opt/securewave/.ssh/id_ed25519
chmod 600 /opt/securewave/.ssh/id_ed25519
```

---

## Production Health Check

```bash
curl -fsS https://api.securewaveapp.com/api/health | python3 -m json.tool
# Expected: {"status": "healthy", ...}

# Verify rate limiting zones loaded
nginx -T 2>/dev/null | grep limit_req_zone

# Verify Redis is reachable
redis-cli ping   # Expected: PONG

# Verify no memory:// rate limiter
grep REDIS_URL /etc/securewave/env
```
