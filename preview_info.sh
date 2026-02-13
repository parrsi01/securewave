#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PREVIEW_DIR="${PREVIEW_DIR:-$ROOT_DIR/.preview}"
PREVIEW_HOST="${PREVIEW_HOST:-}"
PREVIEW_PORT="${PREVIEW_PORT:-8080}"

detect_public_ip() {
  local ip=""
  if command -v curl >/dev/null 2>&1; then
    ip="$(curl -fsS --max-time 3 https://api.ipify.org || true)"
  fi
  if [[ -z "$ip" ]] && command -v wget >/dev/null 2>&1; then
    ip="$(wget -qO- --timeout=3 https://api.ipify.org || true)"
  fi
  echo "$ip"
}

is_private_ip() {
  local ip="$1"
  [[ "$ip" =~ ^10\\. ]] && return 0
  [[ "$ip" =~ ^192\\.168\\. ]] && return 0
  [[ "$ip" =~ ^172\\.(1[6-9]|2[0-9]|3[0-1])\\. ]] && return 0
  [[ "$ip" =~ ^127\\. ]] && return 0
  return 1
}

ip="$(detect_public_ip)"
if [[ -z "$PREVIEW_HOST" ]]; then
  if [[ -n "$ip" ]] && ! is_private_ip "$ip"; then
    PREVIEW_HOST="${ip}.nip.io"
  else
    PREVIEW_HOST="localhost"
  fi
fi

echo "SecureWave Preview Info"
echo ""
echo "Local app (uvicorn) listens on: http://127.0.0.1:${PREVIEW_PORT}"
echo ""
echo "If Nginx is configured on staging:"
echo "  http://${PREVIEW_HOST}/"
echo "  https://${PREVIEW_HOST}/   (if SSL configured)"
echo ""
echo "Expected responses:"
echo "  GET /                 -> 200 (static index.html)"
echo "  GET /css/site.css     -> 200 (CSS)"
echo "  GET /js/site.js       -> 200 (JS)"
echo "  GET /api/health       -> 200 (JSON)"
echo "  GET /api/docs         -> 200 (Swagger UI, if enabled)"
echo ""
echo "Quick verify commands:"
echo "  curl -i http://127.0.0.1:${PREVIEW_PORT}/ | head"
echo "  curl -i http://127.0.0.1:${PREVIEW_PORT}/api/health"
echo ""
echo "Nip.io preview example:"
echo "  http://138.199.204.139.nip.io"
echo "  https://138.199.204.139.nip.io"

