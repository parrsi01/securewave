# SecureWave

SecureWave is a FastAPI-based VPN control plane with a single-server WireGuard data plane. The infrastructure is **Hetzner Cloud only** and is intentionally minimal and cost-safe.

## Quick Start (Local)

```bash
bash deploy.sh local
```

Visit:
- `http://localhost:8000/home.html`
- `http://localhost:8000/api/docs`

## Production (Hetzner)

Provisioning and deployment are documented in `docs/HETZNER_RUNBOOK.md`.

Highlights:
- Single server by default
- `cx33` default server type
- Firewall allows SSH and WireGuard only by default
- Scaling requires a manual flag

## Configuration

Key environment variables:
- `DATABASE_URL`
- `APP_URL`
- `WG_ENDPOINT`
- `WG_SSH_HOST`, `WG_SSH_USER`, `WG_SSH_KEY_PATH`

Secrets are read from environment variables only.

## Repository Layout

- `infrastructure/hetzner/` Terraform for provisioning
- `scripts/hetzner_bootstrap.sh` host bootstrap
- `scripts/check_cost_guardrails.sh` CI guardrails
- `docs/HETZNER_RUNBOOK.md` deployment guide
