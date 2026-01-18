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
PYTHON_BIN="${PYTHON_BIN:-}"
if [ -n "${PYTHON_BIN}" ] && [ -x "${PYTHON_BIN}" ]; then
  : # Use provided python path.
else
  PYTHON_BIN=""
  for candidate in /opt/python/3.12.* /opt/python/3.11.* /opt/python/3.10.*; do
    if [ -x "${candidate}/bin/python3" ]; then
      PYTHON_BIN="${candidate}/bin/python3"
      break
    fi
  done
  if [ -z "${PYTHON_BIN}" ]; then
    PYTHON_BIN="$(command -v python3 || true)"
  fi
  if [ -z "${PYTHON_BIN}" ] || [ ! -x "${PYTHON_BIN}" ]; then
    PYTHON_BIN="/usr/bin/python3"
  fi
fi

REQ_HASH_FILE="${APP_DIR}/.requirements.sha"

echo "[startup] SecureWave startup begin"

if [ ! -x "${VENV_DIR}/bin/python" ]; then
  echo "[startup] creating virtualenv at ${VENV_DIR}"
  "${PYTHON_BIN}" -m venv "${VENV_DIR}"
fi

source "${VENV_DIR}/bin/activate"

python - <<'PY'
import importlib.util
missing = [m for m in ("pip", "setuptools", "_distutils_hack") if importlib.util.find_spec(m) is None]
if missing:
    raise SystemExit(1)
PY

if [ $? -ne 0 ]; then
  echo "[startup] rebuilding virtualenv due to missing base tooling"
  rm -rf "${VENV_DIR}"
  "${PYTHON_BIN}" -m venv "${VENV_DIR}"
  source "${VENV_DIR}/bin/activate"
  pip install --no-input --upgrade pip setuptools wheel
fi

REQ_HASH="$(sha256sum "${APP_DIR}/requirements.txt" | awk '{print $1}')"
INSTALLED_HASH=""
if [ -f "${REQ_HASH_FILE}" ]; then
  INSTALLED_HASH="$(cat "${REQ_HASH_FILE}" 2>/dev/null || true)"
fi

NEEDS_INSTALL=false
if ! python - <<'PY'
import importlib.util
critical = ("uvicorn", "fastapi", "gunicorn", "passlib", "sqlalchemy")
missing = [m for m in critical if importlib.util.find_spec(m) is None]
if missing:
    raise SystemExit(1)
PY
then
  NEEDS_INSTALL=true
fi

if [ "${NEEDS_INSTALL}" = "true" ] || [ "${REQ_HASH}" != "${INSTALLED_HASH}" ]; then
  echo "[startup] installing requirements..."
  pip install --no-input -r "${APP_DIR}/requirements.txt"
  echo "${REQ_HASH}" > "${REQ_HASH_FILE}"
fi

echo "[startup] launching gunicorn"
exec gunicorn -k uvicorn.workers.UvicornWorker main:app --bind 0.0.0.0:${PORT} --timeout 600
