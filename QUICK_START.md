# Quick Start

## Backend

```bash
python3 -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt
DATABASE_URL=postgresql+psycopg2://USER:PASSWORD@HOST:5432/securewave bash scripts/run_backend.sh
```

Use the Hetzner PostgreSQL database URL that is already set up.

## Linux app

```bash
make linux-runtime-install
SECUREWAVE_API_BASE_URL=http://localhost:8000/api make flutter-run
```

Register or log in with any valid email address, choose/connect WireGuard, watch usage update while connected, then disconnect/logout.
