# SecureWave

SecureWave is now scoped to one thing: a Linux Flutter VPN app backed by a small FastAPI API and real WireGuard connectivity.

This repo intentionally carries only the Linux WireGuard app and its small API.

## What should work

- Register an account with any valid email address.
- Log in immediately after registration.
- Fetch a live WireGuard profile from the API.
- Connect through the Linux native helper.
- Report WireGuard data-usage deltas while the app is open.
- Disconnect and log out.

## Main paths

- `main.py`, `routes/`, `services/`, `models/`, `database/`, `utils/` — simplified backend.
- `securewave_app/` — Flutter Linux app and native Linux helper.
- `scripts/run_backend.sh` — local API runner.
- `scripts/run_flutter_linux.sh` — Flutter Linux runner.
- `scripts/setup_linux_runtime.sh` — builds and installs the privileged WireGuard helper on a Linux VM.
- `infrastructure/register_server.py` — registers a real WireGuard server row in the database.

## Quick run

```bash
python3 -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt
DATABASE_URL=postgresql+psycopg2://USER:PASSWORD@HOST:5432/securewave \
  ACCESS_TOKEN_SECRET="$(python -c 'import secrets; print(secrets.token_urlsafe(64))')" \
  REFRESH_TOKEN_SECRET="$(python -c 'import secrets; print(secrets.token_urlsafe(64))')" \
  bash scripts/run_backend.sh
```

In another terminal:

```bash
make linux-runtime-install
SECUREWAVE_API_BASE_URL=http://localhost:8000/api make flutter-run
```

If the helper, backend, database, or registered WireGuard server is missing, the app should fail visibly instead of pretending the VPN connected.
