#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ts() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

PYTEST_BIN="${PYTEST_BIN:-.venv/bin/pytest}"
TIMEOUT_SECONDS="${INTEGRATION_TIMEOUT_SECONDS:-600}"
KILL_AFTER_SECONDS="${INTEGRATION_TIMEOUT_KILL_AFTER_SECONDS:-20}"

ARGS=("$@")
if [ ${#ARGS[@]} -eq 0 ]; then
  ARGS=(tests/integration -q)
fi

echo "[$(ts)] starting integration pytest with timeout=${TIMEOUT_SECONDS}s" >&2
echo "[$(ts)] pytest args: -vv -s --maxfail=1 ${ARGS[*]}" >&2

if command -v timeout >/dev/null 2>&1; then
  timeout --signal=USR1 --kill-after="${KILL_AFTER_SECONDS}s" "${TIMEOUT_SECONDS}s" \
    "$PYTEST_BIN" -vv -s --maxfail=1 "${ARGS[@]}"
else
  "$PYTEST_BIN" -vv -s --maxfail=1 "${ARGS[@]}" &
  pid=$!
  start_ts=$(date +%s)
  while kill -0 "$pid" 2>/dev/null; do
    now_ts=$(date +%s)
    if [ $((now_ts - start_ts)) -ge "$TIMEOUT_SECONDS" ]; then
      echo "[$(ts)] timeout exceeded, sending SIGUSR1 to pid=${pid}" >&2
      kill -USR1 "$pid" 2>/dev/null || true
      sleep 5
      echo "[$(ts)] terminating pytest pid=${pid}" >&2
      kill -TERM "$pid" 2>/dev/null || true
      sleep "$KILL_AFTER_SECONDS"
      kill -KILL "$pid" 2>/dev/null || true
      wait "$pid" || true
      exit 124
    fi
    sleep 1
  done
  wait "$pid"
fi
