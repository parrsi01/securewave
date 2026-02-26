#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PREVIEW_DIR="${PREVIEW_DIR:-$ROOT_DIR/.preview}"
LOG_DIR="${PREVIEW_LOG_DIR:-$PREVIEW_DIR/logs}"
PID_DIR="${PREVIEW_PID_DIR:-$PREVIEW_DIR/pids}"

PREVIEW_HOST="${PREVIEW_BIND:-127.0.0.1}"
PREVIEW_PORT="${PREVIEW_PORT:-8080}"

PYTHON_BIN="${PYTHON_BIN:-$ROOT_DIR/.venv/bin/python}"
if [[ ! -x "$PYTHON_BIN" ]]; then
  PYTHON_BIN="${PYTHON_BIN_FALLBACK:-python3}"
fi

UVICORN_WORKERS="${UVICORN_WORKERS:-1}"
UVICORN_LOG_LEVEL="${UVICORN_LOG_LEVEL:-info}"
UVICORN_RELOAD="${UVICORN_RELOAD:-0}"

mkdir -p "$LOG_DIR" "$PID_DIR"

pid_file="$PID_DIR/preview_site.pid"
log_file="$LOG_DIR/preview_site.log"

if [[ -f "$pid_file" ]]; then
  old_pid="$(cat "$pid_file" || true)"
  if [[ -n "${old_pid:-}" ]] && kill -0 "$old_pid" >/dev/null 2>&1; then
    echo "preview already running (pid=$old_pid)"
    exit 0
  fi
fi

if command -v ss >/dev/null 2>&1; then
  if ss -ltn | awk '{print $4}' | grep -q ":${PREVIEW_PORT}$"; then
    echo "port ${PREVIEW_PORT} already in use"
    exit 1
  fi
fi

# Preview-safe defaults. Override via env if desired.
export ENVIRONMENT="${ENVIRONMENT:-preview}"
export EMAIL_PROVIDER="${EMAIL_PROVIDER:-smtp}"
export APP_URL="${APP_URL:-http://localhost:${PREVIEW_PORT}}"
export DATABASE_URL="${DATABASE_URL:-sqlite:///${PREVIEW_DIR}/securewave_preview.db}"
export DB_ECHO="${DB_ECHO:-false}"

# Keep preview DB schema aligned with current code before starting the app.
ALEMBIC_BIN="${ALEMBIC_BIN:-$ROOT_DIR/.venv/bin/alembic}"
if [[ -x "$ALEMBIC_BIN" ]]; then
  if ! (cd "$ROOT_DIR" && "$ALEMBIC_BIN" upgrade head >>"$log_file" 2>&1); then
    # Preview DBs may predate Alembic stamping and already contain base tables.
    # In that case, stamp at the last known pre-multi-protocol revision and retry.
    if grep -q "table users already exists" "$log_file"; then
      echo "preview DB appears to be a legacy unstamped schema; stamping and retrying migrations"
      if ! (cd "$ROOT_DIR" && "$ALEMBIC_BIN" stamp 0009 >>"$log_file" 2>&1 && "$ALEMBIC_BIN" upgrade head >>"$log_file" 2>&1); then
        echo "alembic migration recovery failed for preview DB (see $log_file)"
        exit 1
      fi
    else
      echo "alembic migration failed for preview DB (see $log_file)"
      exit 1
    fi
  fi
fi

reload_flag=()
if [[ "$UVICORN_RELOAD" == "1" || "$UVICORN_RELOAD" == "true" ]]; then
  reload_flag=(--reload)
fi

nohup "$PYTHON_BIN" -m uvicorn main:app \
  --host "$PREVIEW_HOST" \
  --port "$PREVIEW_PORT" \
  --workers "$UVICORN_WORKERS" \
  --log-level "$UVICORN_LOG_LEVEL" \
  "${reload_flag[@]}" \
  >"$log_file" 2>&1 &

new_pid="$!"
echo "$new_pid" >"$pid_file"

echo "starting preview site on http://${PREVIEW_HOST}:${PREVIEW_PORT} (pid=$new_pid)"

# Health check loop (best-effort)
health_url="http://${PREVIEW_HOST}:${PREVIEW_PORT}/api/health"
for _ in $(seq 1 40); do
  if command -v curl >/dev/null 2>&1; then
    if curl -fsS "$health_url" >/dev/null 2>&1; then
      echo "preview ready: $health_url"
      exit 0
    fi
  else
    break
  fi
  sleep 0.25
done

echo "preview started, but health endpoint did not respond yet (check logs: $log_file)"
exit 0
