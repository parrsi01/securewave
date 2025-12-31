# Backend (SecureWave)

FastAPI backend that serves the static frontend and exposes auth, VPN, dashboard, and payment endpoints. WireGuard generation supports Azure mock mode.

## Run locally
```bash
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
alembic upgrade head
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

## Environment variables
- `DATABASE_URL` (PostgreSQL, default: `postgresql+psycopg2://postgres:postgres@localhost:5432/securewave`)
- `ACCESS_TOKEN_SECRET`, `REFRESH_TOKEN_SECRET`
- `APP_BASE_URL` (for payment redirects)
- `STRIPE_SECRET_KEY`, `STRIPE_PRICE_ID`
- `PAYPAL_CLIENT_ID`, `PAYPAL_CLIENT_SECRET`, `PAYPAL_MODE`
- `WG_DATA_DIR`, `WG_ENDPOINT`, `WG_DNS`, `WG_ENCRYPTION_KEY`, `WG_MOCK_MODE`

## Deploy
Copy `../frontend` into `static/`, zip the backend directory, and deploy to Azure App Service (Python 3.12).
