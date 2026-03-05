# SecureWave Ops Scripts

These scripts are intended to be run by an operator (typically on the Hetzner host).

## Canary + Zero-Downtime Deploy

- Canary deploy + optional promotion:
  - `scripts/ops/canary_deploy.sh`
- Zero-downtime deploy wrapper (blue/green or graceful):
  - `scripts/ops/zero_downtime_deploy.sh`
- Nginx upstream switch helper:
  - `scripts/ops/nginx_switch_upstream.sh`
- Gunicorn graceful restart helper (pidfile-based):
  - `scripts/ops/gunicorn_graceful_restart.sh`

Notes:
- Canary deploy uses `git worktree` so the new build can be started without modifying the currently-running worktree.
- Promotion switches the Nginx upstream port (requires root).
- Alert/metrics gating can be enabled by setting `ALERT_API_TOKEN` or `ALERT_API_EMAIL`/`ALERT_API_PASSWORD`.

## Full Bootstrap + Validation

- Full remote bootstrap, backend start, token creation, and VPN validation:
  - `scripts/ops/hetzner_full_bootstrap_and_validate.sh`

Example:

```bash
VPS_HOST=138.199.204.139 bash scripts/ops/hetzner_full_bootstrap_and_validate.sh
```

This runs from your local machine and:
- syncs the full repo to the VPS
- runs `tools/provisioning/install_vpn_stack.sh`
- ensures the backend is up on `:8000`
- creates or reuses a validation user
- runs `run_all_validation_tools.sh` remotely
