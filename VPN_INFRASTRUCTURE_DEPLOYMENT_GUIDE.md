# VPN Infrastructure Deployment Guide

SecureWave is deployed as a single Hetzner server that hosts:

- FastAPI backend
- Website
- WireGuard data plane

## Provisioning

See `docs/HETZNER_RUNBOOK.md` for Terraform steps and bootstrap.

## Notes

- Scaling is manual and gated by `allow_scale = true`.
- Default server type is `cx33`.
- Firewall allows SSH and WireGuard only by default.
