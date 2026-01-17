#!/bin/bash
set -euo pipefail

APP_DIR="/home/site/app"
PORT="${PORT:-8000}"

if [ ! -f "${APP_DIR}/main.py" ]; then
  APP_DIR="/home/site/wwwroot"
fi

if [ -f "${APP_DIR}/output.tar.gz" ]; then
  tar -xzf "${APP_DIR}/output.tar.gz" -C "${APP_DIR}"
fi

export PYTHONPATH="${APP_DIR}:${PYTHONPATH:-}"

if [ -x "${APP_DIR}/antenv/bin/gunicorn" ]; then
  exec "${APP_DIR}/antenv/bin/gunicorn" -k uvicorn.workers.UvicornWorker main:app --bind 0.0.0.0:${PORT} --timeout 600
fi

exec gunicorn -k uvicorn.workers.UvicornWorker main:app --bind 0.0.0.0:${PORT} --timeout 600
