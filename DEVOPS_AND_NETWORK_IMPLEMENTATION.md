# DevOps and Network Implementation

SecureWave uses a minimal, single-server deployment on Hetzner Cloud.

## Provisioning

- Terraform in `infrastructure/hetzner/`
- Guardrails enforced by `scripts/check_cost_guardrails.sh`

## Host Bootstrap

- `scripts/hetzner_bootstrap.sh` installs Docker, UFW, fail2ban
- IP forwarding enabled for WireGuard

## Operations

- Backups via `infrastructure/database_backup_manager.py`
- Logs via Docker/systemd

See `docs/HETZNER_RUNBOOK.md` for step-by-step deployment.
