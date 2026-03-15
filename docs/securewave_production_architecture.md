# SecureWave Production Architecture

## System Overview

SecureWave is a multi-node VPN SaaS with a centralized control plane and
distributed WireGuard/OpenVPN/IKEv2 tunnel nodes.

```
                    ┌──────────────────────────────────────┐
                    │          Hetzner Cloud (EU)           │
                    │                                      │
  Clients ────────► │  ┌──────────────┐   ┌─────────────┐  │
  (Flutter apps,    │  │  NGINX TLS   │──►│  FastAPI     │  │
   web dashboard)   │  │  Reverse     │   │  Backend     │  │
                    │  │  Proxy       │   │  (Gunicorn)  │  │
                    │  └──────────────┘   └──────┬───────┘  │
                    │                            │          │
                    │         ┌───────────┬──────┴───────┐  │
                    │         ▼           ▼              ▼  │
                    │  ┌──────────┐ ┌──────────┐  ┌───────┐ │
                    │  │ VPN Node │ │ VPN Node │  │  DB   │ │
                    │  │ de-fra-1 │ │ de-nue-1 │  │SQLite/│ │
                    │  │ (WG+OV+  │ │ (WG+OV+  │  │PgSQL  │ │
                    │  │  IKEv2)  │ │  IKEv2)  │  └───────┘ │
                    │  └──────────┘ └──────────┘            │
                    └──────────────────────────────────────┘
```

## Components

### 1. Backend Control Plane

| Component | Technology | Purpose |
|-----------|-----------|---------|
| API Server | FastAPI + Gunicorn | REST API, profile generation, auth |
| Database | SQLite (dev) / PostgreSQL (prod) | User accounts, server registry, metrics |
| Background Tasks | `BackgroundTaskManager` | Health monitoring, peer cleanup |
| Rate Limiter | slowapi + Redis | 200 req/min default, per-IP |

**Entry point:** `main.py` → Gunicorn with `--workers 4`

**Key middleware stack (in order):**
1. GZip compression (min 500 bytes)
2. Rate limiting (slowapi)
3. CORS (origin whitelist, no wildcards in production)
4. Security headers (HSTS, CSP, X-Frame-Options, etc.)
5. HTTPS enforcement (production only)
6. Request ID tracking
7. JWT token revocation check
8. CSRF validation

### 2. Multi-Node VPN Cluster

Each VPN node runs:
- **WireGuard** on UDP 51820
- **OpenVPN** on UDP 1194
- **StrongSwan (IKEv2)** on UDP 500/4500

Nodes are registered via `POST /api/admin/servers/` with either:
- JWT admin token (human operators), or
- `X-Admin-API-Key` header (automated infrastructure scripts)

**Node registry:** `vpn_servers` table with health status, load score, latency,
geographic metadata.

**Server selection:** Weighted ranking algorithm
(`services/server_ranker.py`):
```
composite_score = 0.50 × latency_score + 0.30 × load_score_inv + 0.20 × region_score
```

See [server_selection_algorithm.md](server_selection_algorithm.md) for details.

**Failover:** Each profile response includes up to 2 backup endpoints. The
client switches on handshake failure. See
[vpn_failover_design.md](vpn_failover_design.md).

### 3. Monitoring System

#### Metrics Endpoints

| Endpoint | Auth | Format | Purpose |
|----------|------|--------|---------|
| `GET /metrics` | None | Prometheus text | Scrape target for Prometheus/Grafana |
| `GET /api/metrics` | JWT | JSON | Unified fleet dashboard (sessions, load, tunnels) |
| `GET /api/metrics/vpn` | JWT | JSON | Peer health, IP pool, runtime counters |
| `GET /api/metrics/system` | JWT | JSON | Process FDs, threads, zombie detection |
| `GET /api/admin/vpn-metrics` | Admin | JSON | Per-server latency/throughput aggregates |
| `POST /api/vpn/metrics` | JWT | JSON | Client-reported connection quality ingest |

#### Prometheus Gauges

```
securewave_active_sessions          Current active VPN sessions
securewave_active_tunnels           Current active WireGuard tunnels
securewave_fleet_total_servers      Total active VPN servers
securewave_fleet_healthy_servers    Healthy VPN servers
securewave_fleet_total_connections  Total current connections across fleet
securewave_fleet_avg_load_score     Average server load score (0.0-1.0)
securewave_vpn_profiles_issued_total    Total profile issuances (counter)
securewave_auth_failed_total            Total auth failures (counter)
securewave_system_cpu_percent           Host CPU usage
securewave_system_memory_percent        Host memory usage
securewave_process_memory_mb            Process RSS
```

#### Health Monitoring

The `VPNHealthMonitor` background task runs every 30 seconds:
1. ICMP ping to each server
2. UDP port probe on WireGuard port (51820)
3. Health state machine: healthy → degraded → unhealthy → offline
4. Updates `load_score` from CPU, memory, and connection ratio

Offline threshold: 5 consecutive failures.

#### Uptime Monitor

`UptimeMonitorService` checks:
- API endpoint availability
- Database connectivity
- Redis connectivity (optional)
- VPN server fleet health

Historical uptime percentage available via `get_uptime_stats()`.

## Authentication & Authorization

### API Authentication

| Method | Scope | Mechanism |
|--------|-------|-----------|
| JWT Bearer | User APIs | `Authorization: Bearer <token>` |
| Cookie | Web dashboard | `access_token` cookie |
| API Key | Admin server management | `X-Admin-API-Key: <key>` |

**Token lifecycle:**
- Access tokens: short-lived (configurable, default 30 min)
- Refresh tokens: stored in DB, rotated on use
- Revocation: JWT blacklist checked on every request via middleware

### Admin API Key

For automated infrastructure tooling (Hetzner bootstrap, CI/CD):

```bash
# Set in environment
export ADMIN_API_KEY="$(openssl rand -hex 32)"

# Use in API calls
curl -H "X-Admin-API-Key: $ADMIN_API_KEY" \
     -X POST https://api.securewaveapp.com/api/admin/servers/ \
     -d '{"server_id": "de-fra-2", ...}'
```

The key is validated with constant-time comparison (`hmac.compare_digest`).

### Security Middleware

- **CSRF:** `X-CSRF-Token` header required for POST/PUT/DELETE on `/api`
- **HTTPS enforcement:** Non-HTTPS requests rejected in production
- **Security headers:** HSTS, CSP, X-Frame-Options: DENY, Referrer-Policy
- **Rate limiting:** 200 req/min per IP (Redis-backed), 429 on exceed

## Deployment

### Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `DATABASE_URL` | Yes | `sqlite:///...` | Database connection string |
| `JWT_SECRET_KEY` | Yes | — | JWT signing secret |
| `ADMIN_API_KEY` | Recommended | — | Admin API key for server-to-server auth |
| `REDIS_URL` | Recommended | `memory://` | Redis for rate limiting |
| `CORS_ORIGINS` | Production | — | Comma-separated allowed origins |
| `ENVIRONMENT` | Production | `development` | Set to `production` for security enforcement |
| `STRIPE_SECRET_KEY` | Yes | — | Stripe API key |
| `STRIPE_WEBHOOK_SECRET` | Yes | — | Stripe webhook verification |
| `VPN_RANK_W_LATENCY` | No | `0.50` | Server ranking: latency weight |
| `VPN_RANK_W_LOAD` | No | `0.30` | Server ranking: load weight |
| `VPN_RANK_W_REGION` | No | `0.20` | Server ranking: region weight |
| `VPN_HEALTH_CHECK_INTERVAL` | No | `30` | Health check interval (seconds) |
| `WG_SSH_KEY_PATH` | Yes | — | SSH key for peer registration |

### Deployment Steps

```bash
# 1. Provision VPS (Hetzner)
scripts/hetzner_bootstrap.sh

# 2. Set up TLS
scripts/setup_tls_certbot.sh

# 3. Configure environment
cp .env.example.backend .env
# Edit .env with production values

# 4. Run database migrations
alembic upgrade head

# 5. Start the service
systemctl enable --now securewave-api
systemctl enable --now securewave-watchdog

# 6. Register VPN nodes
curl -H "X-Admin-API-Key: $ADMIN_API_KEY" \
     -X POST https://api.securewaveapp.com/api/admin/servers/ \
     -d @node_config.json

# 7. Verify
scripts/verify_production_env.sh
```

### Systemd Services

| Service | Description |
|---------|-------------|
| `securewave-api.service` | Main FastAPI application (Gunicorn) |
| `securewave-watchdog.service` | Background health monitoring |
| `securewave-wg-peer-cleanup.timer` | Periodic orphaned peer cleanup |

### Infrastructure Layout

```
/opt/securewave/
├── .env                        # Production environment
├── securewave_runtime.db       # SQLite database (dev/single-node)
├── .ssh/id_ed25519             # SSH key for peer registration
└── logs/                       # Application logs

/etc/
├── wireguard/wg0.conf          # WireGuard server config
├── openvpn/server/             # OpenVPN server config
├── ipsec.d/                    # StrongSwan certificates
├── nginx/sites-enabled/        # TLS reverse proxy
└── sudoers.d/securewave        # Restricted sudo for wg/openvpn/ipsec
```

## Scaling Considerations

### Current Architecture (Single Control Plane)

- 1 API server + N VPN nodes
- SQLite for dev, PostgreSQL for production
- In-memory rate limiting fallback, Redis recommended
- Health monitoring from the API server to all nodes

### Scaling Path

| Bottleneck | Solution |
|-----------|---------|
| API throughput | Add Gunicorn workers, or horizontal scale behind LB |
| Database | Migrate SQLite → PostgreSQL (script: `scripts/ops/migrate_sqlite_to_postgres.py`) |
| VPN capacity | Register additional nodes via admin API |
| Rate limiting | Deploy Redis for distributed rate limit state |
| Monitoring | Point Prometheus at `/metrics`, build Grafana dashboards |
| Geographic coverage | Deploy VPN nodes in new Hetzner locations (hel1, ash) |

### Security Hardening Checklist

- [ ] `ENVIRONMENT=production` set
- [ ] `ADMIN_API_KEY` configured (≥32 hex characters)
- [ ] `CORS_ORIGINS` explicitly set (no wildcards)
- [ ] HTTPS enforced via NGINX + Let's Encrypt
- [ ] Firewall: only 443/tcp, 51820/udp, 1194/udp, 500/udp, 4500/udp
- [ ] SSH: key-only auth, no root login
- [ ] Sudoers: restricted to `wg`, `systemctl`, `openvpn`, `ipsec` commands
- [ ] Database: file permissions 0666 (SQLite) or TLS client certs (PostgreSQL)
- [ ] Log rotation configured (`infrastructure/logrotate/securewave`)
- [ ] Prometheus scraping `/metrics` endpoint
