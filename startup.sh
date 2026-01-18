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

REQ_HASH_FILE="${APP_DIR}/.requirements.sha"

if [ ! -x "${VENV_DIR}/bin/python" ]; then
  echo "[startup] creating virtualenv at ${VENV_DIR}"
  "${PYTHON_BIN}" -m venv "${VENV_DIR}"
fi

source "${VENV_DIR}/bin/activate"

REQ_HASH="$(sha256sum "${APP_DIR}/requirements.txt" | awk '{print $1}')"
INSTALLED_HASH=""
if [ -f "${REQ_HASH_FILE}" ]; then
  INSTALLED_HASH="$(cat "${REQ_HASH_FILE}" 2>/dev/null || true)"
fi

python - <<'PY'
import importlib.util
critical = ("uvicorn", "fastapi", "gunicorn", "passlib", "sqlalchemy")
missing = [m for m in critical if importlib.util.find_spec(m) is None]
if missing:
    raise SystemExit(1)
PY

if [ $? -ne 0 ] || [ "${REQ_HASH}" != "${INSTALLED_HASH}" ]; then
  echo "[startup] installing requirements..."
  pip install --no-input -r "${APP_DIR}/requirements.txt"
  echo "${REQ_HASH}" > "${REQ_HASH_FILE}"
fi

exec gunicorn -k uvicorn.workers.UvicornWorker main:app --bind 0.0.0.0:${PORT} --timeout 600
