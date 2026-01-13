# CloudSecure Backend Control Plane

Backend-only SaaS control plane for CloudSecure/SecureWave VPN.

## Purpose
- Centralized API for authentication, user/device management, subscription status, and VPN config issuance.
- Designed to support web account management and future native VPN clients (iOS/macOS/Android/Windows).

## Architecture Summary
- **API-only** FastAPI service (JSON responses; no HTML).
- **Auth**: JWT access + refresh tokens.
- **Devices**: per-user device registration with device tokens.
- **VPN**: stateless config issuance for authenticated devices.
- **DB**: SQLAlchemy models and session management.
 - **Security**: login lockout + refresh token rotation + device token hashing.

## Structure
- `app/main.py`: FastAPI app entrypoint (gunicorn-compatible).
- `app/api/*`: route modules.
- `app/services/*`: business logic.
- `app/models/*`: SQLAlchemy models.
- `app/db/*`: database setup and migrations.
- `scripts/*`: local dev helpers.

## Local Run
```bash
./scripts/init_db.sh
./scripts/dev_run.sh
```

## Migrations
```bash
alembic upgrade head
```

## Seed a VPN Server
```bash
WG_PUBLIC_KEY=... ENDPOINT=your-vm-ip:51820 ./scripts/seed_vpn_server.sh
```

## Notes
- VPN server control is out-of-scope here; this service only issues configs/tokens.
- TODOs are marked in service layers for future hardening and billing enforcement.
- Admin access is controlled by `ADMIN_EMAILS` (comma-separated).
