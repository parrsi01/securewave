# SecureWave

SecureWave is a full-stack VPN platform repository that combines a Python/FastAPI backend, a Flutter client app, VPN provisioning logic, payment flows, and infrastructure automation.

Current public app truth is Linux ARM64 desktop with WireGuard only. Retained
OpenVPN and IKEv2 implementation paths are future-facing and must remain
unavailable unless their local runtime, backend evidence, and live data-plane
checks independently pass. The Flutter client must never mark a VPN as
connected unless the native runtime reports success.

Apple/iOS work currently means signed archive preparation and App Store review
support, not a public mobile release. The iOS target uses NetworkExtension
Packet Tunnel Provider entitlement scope, not Hotspot Helper. Final signed
archive/export must be run on macOS with Xcode via
`securewave_app/scripts/archive_ios_release.sh`.

The public download page currently lists macOS and Windows as coming soon.
The retained macOS UI/account demo packaging workflow can be rebuilt on a Mac
with `securewave_app/scripts/package_macos_ui_demo.sh`, but it is not a public
VPN release and macOS tunneling remains disabled until a signed macOS Network
Extension target is added.

The repository now targets **Hetzner Cloud only**. Older retired-provider assumptions are not part of the supported deployment story; provisioning and production operations are centered on the Terraform module in `infrastructure/hetzner/` and the Hetzner runbook in `docs/HETZNER_RUNBOOK.md`.

If you encounter legacy retired-provider-named files elsewhere in the repository or older history, treat them as archival context rather than the supported deployment path.

## Recruiter-Friendly Overview

This project demonstrates work across:

- **Backend engineering:** FastAPI, SQLAlchemy, Alembic, auth flows, rate limiting, structured logging, and production config validation
- **Client development:** Flutter/Dart app with Riverpod, Dio, secure storage, fresh Apple-utility style screens, and native VPN integration hooks
- **Payments and account systems:** Stripe and PayPal service integrations, subscription logic, and webhook handling
- **Networking and VPN operations:** WireGuard profile generation and peer lifecycle management, plus multiprotocol provisioning and validation paths for OpenVPN and IKEv2
- **Infrastructure and DevOps:** Terraform, Docker, systemd, Nginx, UFW, fail2ban, GitHub Actions, and deployment guardrails for Hetzner
- **Security and reliability:** env validation, log redaction, secret scanning, regression tests, simulation tooling, and operational runbooks

## Core Stack

- **Languages:** Python, Dart, Shell, Terraform, SQL
- **Backend:** FastAPI, Uvicorn, Gunicorn, SQLAlchemy, Alembic, PostgreSQL, Redis
- **Frontend/App:** Flutter, Riverpod, Dio, flutter_secure_storage
- **Payments:** Stripe, PayPal
- **VPN/Infra:** WireGuard, OpenVPN/IKEv2 support code, Terraform, Docker, systemd, Nginx
- **Tooling:** pytest, Flutter test/analyze, GitHub Actions, gitleaks-oriented secret hygiene
- **Apple packaging:** Xcode workspace guardrails, Packet Tunnel extension metadata, signed iOS archive/export handoff, macOS UI demo package script

## Current Deployment Model

- **Cloud provider:** Hetzner Cloud only
- **Default topology:** single-server deployment with explicit guardrails against accidental scaling
- **Live API default:** the Flutter app defaults to `https://api.securewaveapp.com/api`; mock API mode is opt-in only
- **Branch model:** `master` is canonical; focused work is reviewed through short-lived pull-request branches before merge
- **Provisioning:** Terraform in `infrastructure/hetzner/`
- **Host hardening:** `scripts/hetzner_bootstrap.sh`
- **Operations docs:** `docs/HETZNER_RUNBOOK.md`, `ARCHITECTURE.md`, `SETUP_GUIDE.md`

## Repository Map

- `main.py`, `routes/`, `routers/`, `services/`, `models/`: backend API and business logic
- `securewave_app/`: Flutter client app
- `static/`: website and static assets
- `infrastructure/hetzner/`: Terraform for Hetzner provisioning
- `scripts/` and `docs/`: deployment, validation, and operations tooling
- `tests/`, `securewave_app/test/`, `securewave-tests/`: backend, Flutter, and simulated validation coverage

## Getting Started

### Safe local certification

After installing `requirements_dev.txt` and Flutter/Linux build dependencies,
run the maximum safe local suite from the repository root:

```bash
PYTHON_BIN=.venv/bin/python bash scripts/certify_repository.sh
```

The command never deploys, publishes, signs, sends provider email, runs an
external load test, or uses live VPN credentials. It exits nonzero for failed
checks and exits `2` when a required tool is unavailable; unavailable checks
are reported as blocked, never passed. See
`docs/REPOSITORY_CERTIFICATION_REPORT.md` for the current master baseline and
platform-specific blockers.

### Local backend

```bash
bash deploy.sh local
```

Then open:

- `http://localhost:8000/home.html`
- `http://localhost:8000/api/docs`

### Flutter app

```bash
# Works from a fresh clone when Flutter is installed.
make flutter-run
```

The UI can run without administrator access, but the Linux VPN protocols are
fail-closed until the contract-13 helper service is installed. For a complete
Linux runtime on the host, run this once:

```bash
make linux-runtime-install
make flutter-run
```

The installer uses the architecture-matched Flutter bundle, installs only the
allowlisted root helper and systemd unit, and never elevates at connect time.
Use `make linux-runtime-check` to inspect helper, package, and residue gates.

See `securewave_app/README.md` for platform-specific notes.

The Linux app uses one GTK application instance. Launching it again should
present the existing window rather than creating a second Flutter engine.

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
- `docs/hr_app_process_overview/README.md`
- `securewave_app/README.md`
- `docs/APPLE_REVIEW_HANDOFF.md`
- `docs/APPLE_RELEASE.md`
- `docs/SECRET_REMEDIATION.md`
