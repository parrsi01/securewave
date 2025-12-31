# SecureWave VPN SaaS

SecureWave is a unified FastAPI + static frontend deployment that ships as a single ZIP for Azure App Service. The backend serves the neon-themed static frontend directly from FastAPI, and WireGuard configs are generated on demand with an Azure-friendly mock fallback.

## Quickstart (local)
1. **Install dependencies**
   ```bash
   cd backend
   python -m venv .venv && source .venv/bin/activate
   pip install -r requirements.txt
   ```
2. **Configure environment** (optional overrides)
   ```bash
   export DATABASE_URL="postgresql+psycopg2://postgres:postgres@localhost:5432/securewave"
   export ACCESS_TOKEN_SECRET="change_me_access"
   export REFRESH_TOKEN_SECRET="change_me_refresh"
   export APP_BASE_URL="http://127.0.0.1:8000"
   # Stripe / PayPal keys if you have them
   ```
3. **Run migrations**
   ```bash
   alembic upgrade head
   ```
4. **Run the app**
   ```bash
   uvicorn main:app --reload --host 0.0.0.0 --port 8000
   ```
   FastAPI serves the frontend at `http://127.0.0.1:8000/` and docs at `/docs`.

## WireGuard behavior
- Keys/configs stored under `/wg` (or `WG_DATA_DIR`).
- Mock mode automatically enabled on Azure (no kernel module required) or when `WG_MOCK_MODE=true`.
- Per-user configs live at `/wg/users/{user_id}.conf` and QR codes are rendered on demand.

## Building the unified ZIP for Azure
From the repo root:
```bash
rm -rf backend/static/*
cp -r frontend/* backend/static/
cd backend
zip -r securewave-app.zip .
```
This bundle contains FastAPI and the static frontend together.

## Deploying to Azure App Service
- Create an App Service (Python 3.12) named `securewave-app`.
- Set **Configuration** → **Environment variables** for database and any Stripe/PayPal keys.
- Deploy via ZIP:
  ```bash
  az webapp deploy --resource-group <your-rg> --name securewave-app --type zip --src-path securewave-app.zip
  ```

## Frontend overview
Responsive cyber-neon theme covering Home, Login, Register, Dashboard, Subscription, VPN, Services, About, and Contact pages. Vanilla JS uses `fetch` against the same host for auth, dashboard data, and WireGuard downloads/QR codes.

## Directory layout
- `backend/` — FastAPI app, routers, services, DB models, Alembic migration, Dockerfile.
- `frontend/` — Source HTML/CSS/JS + SVG assets (copied into `backend/static` for deploy).
- `backend/static/` — Empty in source; populated during build/deploy.
