#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

HOST="${PREVIEW_HOST:-}"
EMAIL="${LETSENCRYPT_EMAIL:-}"
SSL_MODE="${PREVIEW_SSL_MODE:-auto}"
UPSTREAM_HOST="${PREVIEW_UPSTREAM_HOST:-127.0.0.1}"
UPSTREAM_PORT="${PREVIEW_UPSTREAM_PORT:-8080}"

usage() {
  cat <<'TXT'
setup_nginx_https.sh

Wrapper around ./setup_preview.sh for Hetzner production/preview readiness.

Options (or env):
  --host <domain>          PREVIEW_HOST
  --email <email>          LETSENCRYPT_EMAIL (required for letsencrypt)
  --ssl-mode <mode>        PREVIEW_SSL_MODE: auto|letsencrypt|selfsigned|none
  --upstream-host <host>   PREVIEW_UPSTREAM_HOST (default 127.0.0.1)
  --upstream-port <port>   PREVIEW_UPSTREAM_PORT (default 8080)

Examples:
  sudo bash sandbox/live_hetzner/https/setup_nginx_https.sh --ssl-mode selfsigned
  sudo bash sandbox/live_hetzner/https/setup_nginx_https.sh --host api.example.com --email ops@example.com --ssl-mode letsencrypt
TXT
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host) HOST="$2"; shift 2 ;;
    --email) EMAIL="$2"; shift 2 ;;
    --ssl-mode) SSL_MODE="$2"; shift 2 ;;
    --upstream-host) UPSTREAM_HOST="$2"; shift 2 ;;
    --upstream-port) UPSTREAM_PORT="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

export PREVIEW_HOST="${HOST}"
export LETSENCRYPT_EMAIL="${EMAIL}"
export PREVIEW_SSL_MODE="${SSL_MODE}"
export PREVIEW_UPSTREAM_HOST="${UPSTREAM_HOST}"
export PREVIEW_UPSTREAM_PORT="${UPSTREAM_PORT}"

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "ERROR: must run as root (use sudo). This installs packages and writes /etc/nginx/*." >&2
  exit 1
fi

bash "${ROOT_DIR}/setup_preview.sh"

