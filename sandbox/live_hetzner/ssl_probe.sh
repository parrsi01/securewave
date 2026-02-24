#!/usr/bin/env bash
set -euo pipefail

API_BASE_URL=""
TARGET_IP=""
OUT=""
SNI="${SSL_SNI:-}"

usage() {
  echo "Usage: $0 [--ip <public_ipv4>] --api-base-url <url> --out <path>"
  echo "Env: SSL_SNI=<hostname> (optional for openssl s_client -servername)"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --api-base-url) API_BASE_URL="$2"; shift 2 ;;
    --ip) TARGET_IP="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ -z "${API_BASE_URL}" || -z "${OUT}" ]]; then
  usage
  exit 2
fi

ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

probe_one() {
  local host="$1"
  local port="$2"
  local servername="$3"
  if ! command -v openssl >/dev/null 2>&1; then
    echo "{\"status\":\"skipped\",\"detail\":\"openssl_not_found\"}"
    return 0
  fi
  local cmd=(openssl s_client -connect "${host}:${port}" -showcerts -verify 5)
  if [[ -n "${servername}" ]]; then
    cmd+=(-servername "${servername}")
  fi
  # Capture a small-ish excerpt.
  local out
  out="$("${cmd[@]}" </dev/null 2>&1 | tail -n 60 | sed 's/"/\\"/g' | tr -d '\r')"
  local verify
  verify="$(printf "%s\n" "${out}" | grep -m1 -E "Verify return code: [0-9]+ \\(.*\\)" || true)"
  if [[ -z "${verify}" ]]; then
    verify="unknown"
  fi
  echo "{\"status\":\"ok\",\"verify\":\"${verify}\",\"tail\":\"${out}\"}"
}

api_host="$(python3 - <<PY
import sys
from urllib.parse import urlparse
u=urlparse("${API_BASE_URL}")
print(u.hostname or "")
PY
)"

api_ssl="$(probe_one "${api_host}" 443 "${SNI:-${api_host}}")"

ip_ssl="null"
if [[ -n "${TARGET_IP}" ]]; then
  ip_ssl="$(probe_one "${TARGET_IP}" 443 "${SNI}")"
fi

cat >"${OUT}" <<JSON
{
  "generated_at": "${ts}",
  "api_base_url": "${API_BASE_URL}",
  "api_host": "${api_host}",
  "ssl_sni": "${SNI}",
  "api_host_443": ${api_ssl},
  "ip_443": ${ip_ssl}
}
JSON
