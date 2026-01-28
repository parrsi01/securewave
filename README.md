# SecureWave VPN

SecureWave is a website-first VPN control plane. It manages accounts, subscriptions, device provisioning, and WireGuard configuration delivery. VPN tunneling is performed by WireGuard clients on user devices.

## What It Is
- FastAPI backend + static frontend
- WireGuard config generation + QR codes
- Device management and revocation
- VPN performance test harness
- Azure App Service deployment

## What It Is Not
- No custom VPN protocol
- No in-browser tunneling
- No browser-based VPN or proxying

## Local Run

```bash
bash deploy.sh local
```

Alternative:

```bash
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

## Local Commands
- Web UI (static preview): `scripts/run_web.sh`
- Backend API: `scripts/run_backend.sh`
- Full test suite: `scripts/run_tests.sh`
- Fast smoke tests: `scripts/run_smoke_tests.sh`
- Backend release build: `scripts/build_release.sh`

## Azure Deploy

```bash
bash deploy.sh azure
```

Or the single-app deploy script:

```bash
export AZURE_RESOURCE_GROUP="your-rg"
export AZURE_APP_NAME="your-app"

bash deploy_securewave_single_app.sh
```

## Runtime Endpoints
- Health: `/health` and `/api/health`
- Docs (non-production): `/api/docs`

## VPN Notes
- The website does not create tunnels; users import configs into WireGuard apps.
- Device limits are enforced by subscription tier.
- Demo/test usage is supported; production use requires managed Postgres and secrets.

## Brand Assets and How to Regenerate Icons
- Master logo sources live in `assets/brand/` (SVG + monochrome).
- The canonical 1024x1024 app icon source is `assets/brand/app_icon_1024.png`.
- Regenerate all platform icons and web favicons with:

```bash
python3 scripts/generate_brand_assets.py
```

## ML Experiments (MARL + XGBoost)
Run the reproducible experiment harness with a JSON config profile:

```bash
python3 -m ml.experiment --config ml/configs/baseline.json --data data/vpn_telemetry.csv
```

For the optional v2 profile:

```bash
python3 -m ml.experiment --config ml/configs/v2.json --data data/vpn_telemetry.csv
```

## Required Production Secrets
- `AUTH_ENCRYPTION_KEY` (Fernet key) is required in production for 2FA storage.
- SMTP credentials are required for contact + billing notifications. If SMTP is missing, the contact form returns a 503 with a user-facing message.

## Demo Scope
See `DEMO.md` for the exact demo flow.

---
© 2026 SecureWave. All rights reserved.
