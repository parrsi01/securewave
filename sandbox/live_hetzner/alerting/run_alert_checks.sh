#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
PY="${ROOT_DIR}/.venv/bin/python"
if [[ ! -x "${PY}" ]]; then
  PY="python3"
fi

API_BASE_URL="${LIVE_API_BASE_URL:-}"
if [[ -z "${API_BASE_URL}" ]]; then
  echo "ERROR: LIVE_API_BASE_URL is required" >&2
  exit 2
fi

"${PY}" "${ROOT_DIR}/sandbox/live_hetzner/alerting/check_alerts.py" \
  --api-base-url "${API_BASE_URL}" \
  --out-json "${ROOT_DIR}/artifacts/live_hetzner_alerting_result.json" \
  --out-md "${ROOT_DIR}/artifacts/live_hetzner_alerting_result.md" \
  ${ALERT_NOTIFY:+--notify}

