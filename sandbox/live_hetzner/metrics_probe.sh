#!/usr/bin/env bash
set -euo pipefail

API_BASE_URL=""
OUT=""

usage() {
  echo "Usage: $0 --api-base-url <url> --out <path>"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --api-base-url) API_BASE_URL="$2"; shift 2 ;;
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

probe_text() {
  local url="$1"
  local code
  code="$(curl -sS -o /tmp/sw_metrics_probe_body.txt -w "%{http_code}" --connect-timeout 5 --max-time 12 "${url}" 2>/dev/null || true)"
  code="${code: -3}"
  [[ "${code}" =~ ^[0-9]{3}$ ]] || code="000"
  local preview=""
  if [[ "${code}" == "200" ]]; then
    preview="$(head -n 20 /tmp/sw_metrics_probe_body.txt | sed 's/"/\\"/g' | tr -d '\r')"
  fi
  echo "${code}:::${preview}"
}

metrics_out="$(probe_text "${API_BASE_URL%/}/metrics")"
metrics_code="${metrics_out%%:::*}"
metrics_preview="${metrics_out#*:::}"

cat >"${OUT}" <<JSON
{
  "generated_at": "${ts}",
  "api_base_url": "${API_BASE_URL}",
  "metrics": {
    "status_code": "${metrics_code}",
    "preview": "${metrics_preview}"
  }
}
JSON

