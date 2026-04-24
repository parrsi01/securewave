# SecureWave

SecureWave is a full-stack VPN platform repository that combines a Python/FastAPI backend, a Flutter client app, VPN provisioning logic, payment flows, and infrastructure automation.

Current public v1 planning truth is Linux desktop only: WireGuard is the primary
release path, OpenVPN is limited to the already certified Linux runtime/helper
dataplane path unless separately promoted, and IKEv2 plus Windows/macOS/mobile
runtime support remain outside the public v1 go decision.

The repository now targets **Hetzner Cloud only**. Provisioning and production operations are centered on the Terraform module in `infrastructure/hetzner/` and the Hetzner runbook in `docs/HETZNER_RUNBOOK.md`; no alternate cloud deployment workflow is supported in this tree.

## Recruiter-Friendly Overview

This project demonstrates work across:

- **Backend engineering:** FastAPI, SQLAlchemy, Alembic, auth flows, rate limiting, structured logging, and production config validation
- **Client development:** Flutter/Dart app with Riverpod, GoRouter, Dio, secure storage, and native VPN integration hooks
- **Payments and account systems:** Stripe and PayPal service integrations, subscription logic, and webhook handling
- **Networking and VPN operations:** WireGuard profile generation and peer lifecycle management, plus multiprotocol provisioning and validation paths for OpenVPN and IKEv2
- **Infrastructure and DevOps:** Terraform, Docker, systemd, Nginx, UFW, fail2ban, GitHub Actions, and deployment guardrails for Hetzner
- **Security and reliability:** env validation, log redaction, secret scanning, regression tests, simulation tooling, and operational runbooks

## Core Stack

- **Languages:** Python, Dart, Shell, Terraform, SQL
- **Backend:** FastAPI, Uvicorn, Gunicorn, SQLAlchemy, Alembic, PostgreSQL, Redis
- **Frontend/App:** Flutter, Riverpod, Dio, GoRouter, flutter_secure_storage
- **Payments:** Stripe, PayPal
- **VPN/Infra:** WireGuard, OpenVPN/IKEv2 support code, Terraform, Docker, systemd, Nginx
- **Tooling:** pytest, Flutter test/analyze, GitHub Actions, gitleaks-oriented secret hygiene

## Current Deployment Model

- **Cloud provider:** Hetzner Cloud only
- **Default topology:** single-server deployment with explicit guardrails against accidental scaling
- **Provisioning:** Terraform in `infrastructure/hetzner/`
- **Host hardening:** `scripts/hetzner_bootstrap.sh`
- **Operations docs:** `docs/HETZNER_RUNBOOK.md`, `ARCHITECTURE.md`, `SETUP_GUIDE.md`

## Repository Map

- `main.py`, `routes/`, `routers/`, `services/`, `models/`: backend API and business logic
- `securewave_app/`: Flutter client app
- `static/`: website and static assets
- `infrastructure/hetzner/`: Terraform for Hetzner provisioning
- `scripts/` and `docs/`: deployment, validation, and operations tooling
- `tests/`, `tests_real/`, `securewave-tests/`: automated and simulated validation coverage

## Getting Started

### Local backend

```bash
bash deploy.sh local
```

Then open:

- `http://localhost:8000/home.html`
- `http://localhost:8000/api/docs`

### Flutter app

```bash
cd securewave_app
flutter pub get
flutter run -d linux
```

See `securewave_app/README.md` for platform-specific notes.

### Production on Hetzner

Start with:

1. `SETUP_GUIDE.md`
2. `ARCHITECTURE.md`
3. `docs/HETZNER_RUNBOOK.md`

## Public Repo Safety

This repository is meant to be understandable in public without exposing deploy-time secrets.

- Secrets are supplied through environment variables or external secret stores, not committed config
- `.gitignore` excludes `.env` files, Terraform state, key material, WireGuard runtime data, and private directories
- Example env files use placeholders and should be copied and filled locally
- The historical secret cleanup process is documented in `docs/SECRET_REMEDIATION.md`

Do not commit real values for:

- `HETZNER_API_TOKEN`
- Stripe, PayPal, SMTP, or Sentry credentials
- WireGuard private keys, management API keys, or SSH private keys
- `terraform.tfvars`, `.tfstate`, or local `.env` files

## Key Docs

- `QUICK_START.md`
- `EXECUTIVE_SUMMARY.md`
- `ARCHITECTURE.md`
- `SETUP_GUIDE.md`
- `docs/HETZNER_RUNBOOK.md`
- `securewave_app/README.md`
- `docs/SECRET_REMEDIATION.md`
