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
- No native mobile/desktop apps (planned later)

## Local Run

```bash
bash deploy.sh local
```

Alternative:

```bash
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

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
- Version: `/version`
- Docs (non-production): `/api/docs`

## VPN Notes
- The website does not create tunnels; users import configs into WireGuard apps.
- Device limits are enforced by subscription tier.
- Demo/test usage is supported; production use requires managed Postgres and secrets.

## Demo Scope
See `DEMO.md` for the exact demo flow.
