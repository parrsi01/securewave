#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

DOMAINS=()
EMAIL="${LETSENCRYPT_EMAIL:-}"
UPSTREAM_HOST="${PREVIEW_UPSTREAM_HOST:-127.0.0.1}"
UPSTREAM_PORT="${PREVIEW_UPSTREAM_PORT:-8080}"

usage() {
  cat <<'TXT'
setup_nginx_https.sh

Wrapper around `scripts/setup_tls_certbot.sh` for Hetzner production readiness.

Options (or env):
  --domain <domain>        Repeat for each hostname on the certificate
  --email <email>          LETSENCRYPT_EMAIL (required)
  --upstream-host <host>   PREVIEW_UPSTREAM_HOST (default 127.0.0.1)
  --upstream-port <port>   PREVIEW_UPSTREAM_PORT (default 8080)

Examples:
  sudo bash sandbox/live_hetzner/https/setup_nginx_https.sh --domain securewave.app --domain www.securewave.app --email ops@example.com
TXT
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --domain) DOMAINS+=("$2"); shift 2 ;;
    --email) EMAIL="$2"; shift 2 ;;
    --upstream-host) UPSTREAM_HOST="$2"; shift 2 ;;
    --upstream-port) UPSTREAM_PORT="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

export LETSENCRYPT_EMAIL="${EMAIL}"
export PREVIEW_UPSTREAM_HOST="${UPSTREAM_HOST}"
export PREVIEW_UPSTREAM_PORT="${UPSTREAM_PORT}"

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "ERROR: must run as root (use sudo). This installs packages and writes /etc/nginx/*." >&2
  exit 1
fi

[[ "${#DOMAINS[@]}" -gt 0 ]] || { echo "ERROR: at least one --domain is required" >&2; exit 1; }

cmd=(bash "${ROOT_DIR}/scripts/setup_tls_certbot.sh" --email "${EMAIL}" --upstream-host "${UPSTREAM_HOST}" --upstream-port "${UPSTREAM_PORT}")
for domain in "${DOMAINS[@]}"; do
  cmd+=(--domain "${domain}")
done
"${cmd[@]}"
