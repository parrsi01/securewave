# Backend API and data inventory

Generated from the refactor branch on 2026-07-10. This is a source inventory,
not a production-state claim. It contains no credentials, private keys, or
traffic destinations.

## Method

```bash
rg -n --glob '*.py' '^@(?:app|router)\.(?:get|post|put|patch|delete|websocket)' main.py routes routers
rg --files models services routes routers tests alembic/versions | sort
rg -n 'asyncio\.create_task|add_task\(|start_all\(' main.py background_tasks.py services scripts
python3 scripts/generate_backend_inventory.py
```

The complete deterministic enumeration is stored in `source-inventory.txt`.
It records all 126 route decorators, 194 FastAPI `Depends(...)` declarations,
24 mapped model classes, 40 service modules, 7 background task scheduling
sites, all 6 Alembic revisions, and 315 discovered test functions with source
locations. The grouped narrative below explains the architectural boundaries.

## API route surface

`main.py` owns health/readiness/version, page handlers, static assets, error
normalization, and router inclusion. It also serves guarded public download
compatibility routes through `routes/downloads.public_router`:
`GET /downloads/manifest.json` and `GET /downloads/{filename}`.

| Group | Prefix | Declared operations |
| --- | --- | --- |
| Auth | `/api/auth` | register, login, refresh, logout, me, session, email verification/resend/update, password update/reset, logout-all, and full 2FA lifecycle |
| VPN | `/api/vpn` | servers, protocols, allocation, profile, legacy config/QR/status/connect/disconnect/config list, compatibility device actions, usage readout, usage session start/increment/disconnect, health, and admin debug health |
| Devices | `/api/vpn/devices` | list/create, `limits/info`, read/rename, server preference, revoke, config/QR/download, usage, and key rotation |
| Servers | `/api/admin/servers` | CRUD, health checks, metrics, peers/sync/add/remove |
| Downloads | `/api/downloads` | list, detect, guarded file delivery; public compatibility URLs share the same verification logic |
| Billing | `/api/billing` | subscription lifecycle, portal/invoices/plans, provider webhooks, protected billing administration |
| Diagnostics | `/api/diagnostics` | telemetry, batch telemetry, debug session, summary, events |
| VPN tests | `/api/vpn-tests` | status/latest/history and async/sync test execution |
| Admin | `/api/admin` | pending/all peer inventory, registration, mark registered, peer command |
| Supporting routers | `/api/{optimizer,dashboard,payments,contact,security}` | optimizer selection/quality/stats/servers, dashboard user/info/subscription, Stripe/PayPal flows, contact submission, security status/alerts/report |
| Small endpoints | `/api/tools`, `/api/user` | IP helper and plan readout |

All endpoint declarations are mechanically discoverable with the command above;
dynamic device paths are registered after `/limits/info` so the static route is
not shadowed.

## Dependencies and service boundaries

- Common request dependencies: `database.session.get_db`,
  `services.jwt_service.get_current_user`, `routes.auth.optional_current_user`,
  `services.subscription_access.require_active_subscription`, and admin guards.
- Request protection: SlowAPI decorators, app middleware rate limits, CSRF
  checks, CORS/Trusted Host configuration, request IDs, and normalized errors.
- Auth boundary: `AuthService` plus JWT token-version validation. One-time
  verification/reset tokens are stored as SHA-256 verifiers with legacy raw
  token consumption compatibility.
- Profile boundary: `ProtocolAvailabilityService` evaluates current server
  status, capacity, and fresh protocol-specific runtime health evidence.
  Background monitoring and admin health checks share the compact evidence
  recorder; `routes.vpn` issues WireGuard material only after peer registration
  is confirmed.
- Device boundary: `VPNPeerManager` locks the account row on PostgreSQL for
  device-limit checks and relies on database uniqueness for address/name races.
- Metering boundary: `UsageMeteringService` owns durable session start,
  atomic monotonic increments, idempotency events, reconnect finalization, and
  owner checks. It stores byte counters only.
- Download boundary: `routes.downloads` validates manifest schema, containment,
  status, file existence, and optional SHA-256 before advertising or serving an
  artifact.
- Repository layer: none exists; routes/services use SQLAlchemy sessions
  directly. This refactor preserves that project boundary instead of adding a
  broad repository rewrite.

## Models and migration graph

Mapped model modules: users/subscriptions/invoices; WireGuard peers, VPN
servers, connections, demo sessions, and usage events; audit/monitoring;
analytics; support; email; and GDPR/transparency records.

Migration graph:

```text
0001_init -> 0002 -> 0003 -> 0004 -> 0005 -> 0006_backend_api_schema
```

`0006` is additive online reconciliation. It creates missing runtime tables,
adds absent mapped columns/indexes, backfills the legacy nullable subscription
timestamp, establishes case-normalized email/device uniqueness, and adds
active-device session protection. Fresh SQLite and PostgreSQL schemas both
pass `alembic check`. `--sql` is deliberately rejected at that revision because
a legacy schema cannot be inspected safely offline.

## Background work

- Lifespan schedules `initialize_app_background` outside test mode.
- `BackgroundTaskManager` starts VPN health monitoring, policy worker, and the
  key-rotation loop; shutdown stops all managed tasks.
- Billing cron functions remain explicitly runnable in `scripts/billing_cron.py`.

## Test inventory and isolation

Test families are `unit`, `integration`, `security`, `smoke`, and `e2e`.
Refactor-specific coverage is in:

- `tests/integration/test_migrations.py`: fresh head, repeat head, legacy audit
  upgrade, explicit offline rejection, and migrated request-boundary auth.
- `tests/integration/test_auth_hardening.py`: normalized registration/login,
  verification state, logout isolation, invalidation, and hashed reset token.
- `tests/integration/test_vpn_profile.py` and `test_device_acl.py`: ownership,
  fail-closed runtime evidence, registration failure, device routing, profile
  issuance, and protocol truth.
- `tests/integration/test_usage_metering.py`: start/increment/finalize,
  reconnect, logout/login persistence, idempotency, monotonicity, and account
  isolation.
- `tests/integration/test_postgres_usage_concurrency.py`: opt-in separate
  PostgreSQL sessions prove one winner for concurrent sequence updates.
- `tests/unit/test_downloads_manifest.py` and `tests/security/*`: guarded
  public download truth, malformed manifests, validation-error redaction, log
  redaction, and audit-data sanitization.
