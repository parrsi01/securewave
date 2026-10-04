# Quick Start

## Backend

```bash
python3 -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt
DATABASE_URL=postgresql+psycopg2://USER:PASSWORD@HOST:5432/securewave bash scripts/run_backend.sh
```

Use the Hetzner PostgreSQL database URL that is already set up.

## Install the current Linux app

Download `securewave-vpn_4.0.0+11_arm64.deb` from
https://www.securewaveapp.com/download.html or the GitHub release. In the
directory containing the file, run:

```sh
sudo apt install ./securewave-vpn_4.0.0+11_arm64.deb
securewave-vpn
```

This package targets Ubuntu 24.04 ARM64. Sign in with an existing account,
or create an account with a valid email and an 8+ character password.

## Linux app development

```bash
make linux-runtime-install
SECUREWAVE_API_BASE_URL=https://api.securewaveapp.com/api make flutter-run
```

Development launches do not replace installed-package acceptance. See
`docs/current-state.md` for the stack and evidence, and
`docs/ui-only-handoff.md` for the next planned visual changes.
