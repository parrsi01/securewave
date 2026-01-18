#!/bin/bash
###############################################################################
# SecureWave VPN - Azure App Service Startup Script (Production)
# Ensures dependencies exist before launching gunicorn.
###############################################################################

set -euo pipefail

export PYTHONUNBUFFERED=1
export PORT="${PORT:-8000}"

APP_DIR="/home/site/wwwroot"
VENV_DIR="${APP_DIR}/antenv"
PYTHON_BIN="/opt/python/3.11.14/bin/python3.11"

if [ ! -x "${VENV_DIR}/bin/python" ]; then
  "${PYTHON_BIN}" -m venv "${VENV_DIR}"
fi

source "${VENV_DIR}/bin/activate"

python - <<'PY'
import importlib.util
critical = ("uvicorn", "fastapi", "gunicorn", "passlib", "sqlalchemy")
missing = [m for m in critical if importlib.util.find_spec(m) is None]
if missing:
    raise SystemExit(1)
PY

if [ $? -ne 0 ]; then
  pip install --no-input -r "${APP_DIR}/requirements.txt"
fi

exec gunicorn -k uvicorn.workers.UvicornWorker main:app --bind 0.0.0.0:${PORT} --timeout 600
