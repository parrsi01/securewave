# Architecture

SecureWave runs as a single-server deployment on Hetzner Cloud.

## Components

- **FastAPI backend**: control plane and API
- **Website**: static assets served by the backend
- **WireGuard**: data-plane on the same host
- **PostgreSQL**: external or local (recommended external for production)

## Deployment

- Provisioning: Terraform in `infrastructure/hetzner/`
- Host bootstrap: `scripts/hetzner_bootstrap.sh`
- Firewall: SSH + WireGuard only by default
- Scaling: manual flag only

## Data Flow

1. User authenticates via FastAPI.
2. Backend issues WireGuard profile data.
3. WireGuard runs on the same host and terminates tunnels.

## Secrets

Secrets are supplied via environment variables only.
