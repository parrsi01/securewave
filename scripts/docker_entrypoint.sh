#!/usr/bin/env sh
set -eu

alembic upgrade head

exec gunicorn main:app \
  --worker-class uvicorn.workers.UvicornWorker \
  --workers "${WEB_CONCURRENCY:-2}" \
  --threads "${WORKER_THREADS:-2}" \
  --bind "0.0.0.0:${PORT:-8080}" \
  --timeout "${GUNICORN_TIMEOUT:-120}" \
  --access-logfile - \
  --error-logfile - \
  --log-level info
