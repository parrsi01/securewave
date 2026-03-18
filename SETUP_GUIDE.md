# Setup Guide

## Local Setup

1. Install Python 3.11+.
2. Run:

```bash
bash deploy.sh local
```

## Production Setup (Hetzner)

Provisioning is done via Terraform in `infrastructure/hetzner/`.

Steps:
1. Export `HETZNER_API_TOKEN` and pass it to Terraform.
2. Apply Terraform (`terraform init`, `terraform apply`).
3. Bootstrap the host with `scripts/hetzner_bootstrap.sh`.
4. Deploy the app with Docker or systemd.

See `docs/HETZNER_RUNBOOK.md` for copy-paste steps.
