#!/usr/bin/env bash
set -euo pipefail

API_BASE_URL=""
TARGET_IP=""
OUT=""

usage() {
  echo "Usage: $0 --api-base-url <url> [--ip <public_ipv4>] --out <path>"
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

curl_probe() {
  local url="$1"
  local insecure="${2:-0}"
  local args=(-sS -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time 12)
  if [[ "${insecure}" == "1" ]]; then
    args+=(-k)
  fi
  local code
  code="$(curl "${args[@]}" "${url}" 2>/dev/null || true)"
  code="${code: -3}"
  [[ "${code}" =~ ^[0-9]{3}$ ]] || code="000"
  echo "${code}"
}

json_escape() {
  python3 - <<'PY'
import json,sys
print(json.dumps(sys.stdin.read()))
PY
}

http_ip_code="skipped"
https_ip_code="skipped"
https_ip_insecure_code="skipped"

if [[ -n "${TARGET_IP}" ]]; then
  http_ip_code="$(curl_probe "http://${TARGET_IP}" 0)"
  https_ip_code="$(curl_probe "https://${TARGET_IP}" 0)"
  https_ip_insecure_code="$(curl_probe "https://${TARGET_IP}" 1)"
fi

metrics_code="$(curl_probe "${API_BASE_URL%/}/metrics" 0)"
health_code="$(curl_probe "${API_BASE_URL%/}/health" 0)"

cat >"${OUT}" <<JSON
{
  "generated_at": "${ts}",
  "api_base_url": "${API_BASE_URL}",
  "target_ip": "${TARGET_IP}",
  "probes": {
    "http_ip": {"status_code": "${http_ip_code}"},
    "https_ip": {"status_code": "${https_ip_code}"},
    "https_ip_insecure": {"status_code": "${https_ip_insecure_code}"},
    "health": {"status_code": "${health_code}"},
    "metrics": {"status_code": "${metrics_code}"}
  },
  "notes": [
    "https_ip may fail cert validation for IP-based HTTPS (no matching SAN). https_ip_insecure captures reachability only."
  ]
}
JSON

