# Claude Notes

Updated 2026-02-11.

This document reflects the Hetzner-only, single-server deployment.

Key points:
- Provisioning via `infrastructure/hetzner/`
- Default server type `cx33` with a single server
- Firewall allows SSH and WireGuard only by default
- Scaling requires `allow_scale = true`

See `docs/HETZNER_RUNBOOK.md` for deployment steps.
