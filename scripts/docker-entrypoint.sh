#!/usr/bin/env bash
set -euo pipefail

alembic upgrade head

gunicorn_args=(
  main:app
  --worker-class uvicorn.workers.UvicornWorker
  --workers "${WEB_CONCURRENCY:-2}"
  --threads "${WORKER_THREADS:-2}"
  --worker-connections "${WORKER_CONNECTIONS:-100}"
  --max-requests "${MAX_REQUESTS:-1000}"
  --max-requests-jitter "${MAX_REQUESTS_JITTER:-50}"
  --bind "0.0.0.0:${PORT:-8080}"
  --timeout "${GUNICORN_TIMEOUT:-120}"
  --graceful-timeout "${GRACEFUL_TIMEOUT:-30}"
  --keep-alive "${KEEP_ALIVE:-5}"
  --access-logfile -
  --error-logfile -
  --log-level info
  --worker-tmp-dir /dev/shm
)

if [[ "${GUNICORN_PRELOAD:-false}" == "true" ]]; then
  gunicorn_args+=(--preload)
fi

exec gunicorn "${gunicorn_args[@]}"
