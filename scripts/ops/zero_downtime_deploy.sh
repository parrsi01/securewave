#!/usr/bin/env bash
set -euo pipefail

# zero_downtime_deploy.sh
#
# Two supported strategies:
# 1) bluegreen (default): start a canary on a new port, validate, then switch Nginx upstream.
# 2) graceful: send HUP/USR2 to an existing gunicorn master (no built-in rollback).

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

MODE="bluegreen" # bluegreen|graceful
REF="HEAD"
CANARY_PORT="${CANARY_PORT:-8081}"
CANARY_HOST="${CANARY_HOST:-127.0.0.1}"
STABILIZE_SECONDS="${STABILIZE_SECONDS:-20}"
NGINX_CONF="${NGINX_SITE_CONF:-/etc/nginx/sites-available/securewave_preview.conf}"

PIDFILE=""
HEALTH_URL=""
SIGNAL="${GUNICORN_RESTART_SIGNAL:-HUP}"

usage() {
  cat <<EOF
Usage: $0 [--mode bluegreen|graceful] [options]

Blue/green mode (recommended):
  --mode bluegreen
  --ref <git-ref>            (default: HEAD)
  --canary-host <host>       (default: 127.0.0.1)
  --canary-port <port>       (default: 8081)
  --nginx-conf <path>        (default: /etc/nginx/sites-available/securewave_preview.conf)
  --stabilize-seconds <n>    (default: 20)

Graceful mode (no rollback built-in):
  --mode graceful
  --pidfile <path>           gunicorn master pidfile (required)
  --signal HUP|USR2          (default: HUP)
  --health-url <url>         optional readiness check to wait for

Examples:
  sudo $0 --mode bluegreen --ref v4.1.0 --canary-port 8081
  $0 --mode graceful --pidfile /run/securewave/gunicorn.pid --health-url http://127.0.0.1:8080/api/ready
EOF
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode) MODE="$2"; shift 2 ;;
    --ref) REF="$2"; shift 2 ;;
    --canary-host) CANARY_HOST="$2"; shift 2 ;;
    --canary-port) CANARY_PORT="$2"; shift 2 ;;
    --nginx-conf) NGINX_CONF="$2"; shift 2 ;;
    --stabilize-seconds) STABILIZE_SECONDS="$2"; shift 2 ;;
    --pidfile) PIDFILE="$2"; shift 2 ;;
    --signal) SIGNAL="$2"; shift 2 ;;
    --health-url) HEALTH_URL="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

case "${MODE}" in
  bluegreen)
    exec bash "${ROOT_DIR}/scripts/ops/canary_deploy.sh" \
      --ref "${REF}" \
      --canary-host "${CANARY_HOST}" \
      --canary-port "${CANARY_PORT}" \
      --nginx-conf "${NGINX_CONF}" \
      --stabilize-seconds "${STABILIZE_SECONDS}" \
      --promote
    ;;
  graceful)
    [[ -n "${PIDFILE}" ]] || die "--pidfile is required for --mode graceful"
    exec bash "${ROOT_DIR}/scripts/ops/gunicorn_graceful_restart.sh" \
      --pidfile "${PIDFILE}" \
      --signal "${SIGNAL}" \
      ${HEALTH_URL:+--health-url "${HEALTH_URL}"}
    ;;
  *)
    die "unknown --mode: ${MODE} (expected bluegreen|graceful)"
    ;;
esac

