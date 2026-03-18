# Executive Summary

Updated 2026-03-18.

SecureWave is a full-stack VPN product and operations repository. It combines a FastAPI backend, a Flutter client application, subscription billing, VPN credential orchestration, and deployment automation in one codebase.

## What This Repo Demonstrates

- Backend API design in Python with FastAPI, SQLAlchemy, Alembic, PostgreSQL, and Redis-backed rate limiting
- Flutter client development in Dart with Riverpod, GoRouter, Dio, secure storage, and native VPN bridge integrations
- Subscription and billing workflows using Stripe and PayPal
- VPN profile and server lifecycle work centered on WireGuard, with additional OpenVPN and IKEv2 provisioning paths in the codebase
- DevOps work using Terraform, Docker, systemd, Nginx, UFW, fail2ban, and GitHub Actions
- Security and reliability practices including secret hygiene, logging redaction, simulation tooling, and validation scripts

## Infrastructure Positioning

SecureWave now uses a **Hetzner-only** infrastructure story for public documentation and supported deployment workflows.

- Provisioning lives in `infrastructure/hetzner/`
- Default deployment is a single Hetzner server
- Scaling requires an explicit override
- Host bootstrap and hardening are handled by `scripts/hetzner_bootstrap.sh`
- The main production guide is `docs/HETZNER_RUNBOOK.md`

## Public Repository Hygiene

- Example configuration files use placeholders and are intended to be copied locally
- `.gitignore` excludes `.env` files, key material, Terraform state, and WireGuard runtime data
- Sensitive operational history and remediation notes are documented in `docs/SECRET_REMEDIATION.md`

For a recruiter-friendly landing page, start with `README.md`. For deployment details, use `SETUP_GUIDE.md`, `ARCHITECTURE.md`, and `docs/HETZNER_RUNBOOK.md`.
