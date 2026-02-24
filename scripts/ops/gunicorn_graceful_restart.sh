#!/usr/bin/env bash
set -euo pipefail

# gunicorn_graceful_restart.sh
#
# Gracefully reload a running Gunicorn master process.
#
# Default behavior uses HUP (reload): it spawns new workers and shuts down old
# workers gracefully, avoiding dropped connections in typical setups.
#
# Notes:
# - This does not "roll back" code by itself; prefer blue/green canary deploys
#   when you need a fast rollback path.

PIDFILE=""
SIGNAL="${GUNICORN_RESTART_SIGNAL:-HUP}" # HUP|USR2 (operator override)
HEALTH_URL="${HEALTH_URL:-}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-30}"

usage() {
  cat <<EOF
Usage: $0 --pidfile <path> [--signal HUP|USR2] [--health-url <url>] [--timeout-seconds <n>]

Options:
  --pidfile <path>         Path to gunicorn master pidfile (required)
  --signal HUP|USR2        Signal to send (default: HUP)
  --health-url <url>       Optional readiness probe to wait for (expects HTTP 200)
  --timeout-seconds <n>    Wait timeout for health probe (default: 30)
EOF
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

http_code() {
  local url="$1"
  curl -sS -o /dev/null -w "%{http_code}" --max-time 6 "$url" 2>/dev/null || echo "000"
}

wait_http_200() {
  local url="$1"
  local timeout_s="$2"
  local deadline
  deadline="$(($(date +%s) + timeout_s))"
  while [[ "$(date +%s)" -lt "$deadline" ]]; do
    if [[ "$(http_code "$url")" == "200" ]]; then
      return 0
    fi
    sleep 0.5
  done
  return 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pidfile) PIDFILE="$2"; shift 2 ;;
    --signal) SIGNAL="$2"; shift 2 ;;
    --health-url) HEALTH_URL="$2"; shift 2 ;;
    --timeout-seconds) TIMEOUT_SECONDS="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

[[ -n "${PIDFILE}" ]] || { usage; exit 2; }
[[ -f "${PIDFILE}" ]] || die "pidfile not found: ${PIDFILE}"

pid="$(cat "${PIDFILE}" 2>/dev/null || true)"
[[ "${pid}" =~ ^[0-9]+$ ]] || die "invalid pid in pidfile: ${PIDFILE}"
kill -0 "${pid}" >/dev/null 2>&1 || die "process not running (pid=${pid})"

case "${SIGNAL}" in
  HUP|USR2) ;;
  *) die "unsupported signal: ${SIGNAL} (use HUP or USR2)" ;;
esac

echo "Sending ${SIGNAL} to gunicorn master pid=${pid} (pidfile=${PIDFILE})"
kill "-${SIGNAL}" "${pid}" >/dev/null 2>&1 || die "failed to send signal to pid ${pid}"

if [[ -n "${HEALTH_URL}" ]]; then
  if ! [[ "${TIMEOUT_SECONDS}" =~ ^[0-9]+$ ]]; then
    die "invalid --timeout-seconds: ${TIMEOUT_SECONDS}"
  fi
  echo "Waiting for health check: ${HEALTH_URL} (timeout=${TIMEOUT_SECONDS}s)"
  wait_http_200 "${HEALTH_URL}" "${TIMEOUT_SECONDS}" || die "health check did not return 200 within timeout"
fi

echo "OK: gunicorn graceful restart completed"
exit 0

