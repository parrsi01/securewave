#!/usr/bin/env bash
set -euo pipefail

echo "==============================="
echo " SecureWave Dev Bootstrap"
echo "==============================="

# -------------------------------
# 0. Sanity checks
# -------------------------------
command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 not found"; exit 1; }
command -v node >/dev/null 2>&1 || { echo "ERROR: node not found"; exit 1; }
command -v npm >/dev/null 2>&1 || { echo "ERROR: npm not found"; exit 1; }

# -------------------------------
# 1. Python virtual environment
# -------------------------------
if [ ! -d ".venv" ]; then
  echo "Creating Python virtual environment"
  python3 -m venv .venv
fi

echo "Activating Python virtual environment"
source .venv/bin/activate

echo "Upgrading pip"
pip install --upgrade pip setuptools wheel

# -------------------------------
# 2. Backend dependencies
# -------------------------------
if [ -f "requirements.txt" ]; then
  echo "Installing backend Python dependencies"
  pip install -r requirements.txt
else
  echo "WARN: requirements.txt not found - skipping backend deps"
fi

# -------------------------------
# 3. Node / frontend dependencies
# -------------------------------
if [ -d "web" ]; then
  echo "Installing frontend dependencies"
  cd web
  npm install
  cd ..
else
  echo "WARN: web/ directory not found - skipping frontend deps"
fi

# -------------------------------
# 4. Environment variables
# -------------------------------
echo "Loading environment variables"

if [ ! -f ".env" ]; then
  echo "Creating .env from defaults"
  cat <<EOF > .env
# ===============================
# SecureWave Dev Environment
# ===============================

# Backend
ENV=development
BACKEND_HOST=127.0.0.1
BACKEND_PORT=8000

# Security
SECRET_KEY=dev-secret-change-me
SESSION_COOKIE_NAME=securewave_session
CSRF_COOKIE_NAME=securewave_csrf
COOKIE_SECURE=false
COOKIE_SAMESITE=Lax

# Database
DATABASE_URL=sqlite:///./securewave.db

# Rate limiting
RATE_LIMIT_ENABLED=true

# ML / MARL-XGB
ML_BASELINE_CONFIG=ml/configs/baseline.json
ML_V2_CONFIG=ml/configs/v2.json
ML_OUTPUT_DIR=ml/output
ML_SEED=42
EOF
else
  echo ".env already exists - reusing"
fi

set -a
source .env
set +a

BACKEND_HOST="${BACKEND_HOST:-127.0.0.1}"
BACKEND_PORT="${BACKEND_PORT:-${PORT:-8000}}"

# -------------------------------
# 5. Database init (if applicable)
# -------------------------------
if [ -f "scripts/init_db.sh" ]; then
  echo "Initializing database"
  bash scripts/init_db.sh
else
  echo "No DB init script found - assuming auto-init"
fi

# -------------------------------
# 6. Brand asset generation
# -------------------------------
if [ -f "scripts/generate_brand_assets.py" ]; then
  echo "Generating brand assets / icons"
  python scripts/generate_brand_assets.py
else
  echo "Brand assets already present or generator missing"
fi

# -------------------------------
# 7. Run backend (FastAPI)
# -------------------------------
echo "Starting backend (FastAPI)"
nohup uvicorn main:app \
  --host ${BACKEND_HOST} \
  --port ${BACKEND_PORT} \
  --reload \
  > backend.log 2>&1 &

BACKEND_PID=$!
echo "Backend PID: ${BACKEND_PID}"

sleep 3

# -------------------------------
# 8. Run frontend / website
# -------------------------------
if [ -f "scripts/run_web.sh" ]; then
  echo "Starting website"
  nohup bash scripts/run_web.sh > web.log 2>&1 &
  WEB_PID=$!
  echo "Website PID: ${WEB_PID}"
else
  echo "No web runner script found - skipping"
fi

# -------------------------------
# 9. Run tests
# -------------------------------
echo "Running full test suite"
if [ -f "scripts/run_tests.sh" ]; then
  bash scripts/run_tests.sh
else
  echo "WARN: no test runner found"
fi

echo "Running smoke tests"
if [ -f "scripts/run_smoke_tests.sh" ]; then
  bash scripts/run_smoke_tests.sh
else
  echo "WARN: no smoke test runner found"
fi

# -------------------------------
# 10. Status output
# -------------------------------
echo "==============================="
echo " Bootstrap complete"
echo " Backend: http://${BACKEND_HOST}:${BACKEND_PORT}"
if [ -n "${WEB_PID:-}" ]; then
  echo " Web: http://127.0.0.1:8080"
  echo " To stop website: kill ${WEB_PID}"
fi
echo " Logs: backend.log"
echo " To stop backend: kill ${BACKEND_PID}"
echo "==============================="
