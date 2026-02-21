#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PYTHON_BIN="${PYTHON_BIN:-python3}"
OUT_ROOT="${LIVE_MULTI_PROTOCOL_OUTPUT_ROOT:-${ROOT_DIR}/artifacts/live_validation_multi_protocol}"

LIVE_FLAG=()
if [[ "${LIVE_MULTI_PROTOCOL_ENABLE_LIVE:-false}" == "true" ]]; then
  if [[ -z "${LIVE_API_BASE_URL:-}" ]]; then
    echo "LIVE_MULTI_PROTOCOL_ENABLE_LIVE=true but LIVE_API_BASE_URL is not set" >&2
    exit 2
  fi
  LIVE_FLAG=(--live --api-base-url "${LIVE_API_BASE_URL}")
fi

DATA_PLANE_FLAG=()
if [[ "${LIVE_MULTI_PROTOCOL_ENABLE_DATA_PLANE:-false}" == "true" ]]; then
  DATA_PLANE_FLAG=(--enable-data-plane)
fi

NON_INVASIVE_FLAG=(--non-invasive)
if [[ "${LIVE_MULTI_PROTOCOL_STRICT:-false}" == "true" ]]; then
  NON_INVASIVE_FLAG=()
fi

"${PYTHON_BIN}" "${ROOT_DIR}/sandbox/live_validation_multi_protocol/run_validation.py" \
  --output-root "${OUT_ROOT}" \
  --region-config "${ROOT_DIR}/sandbox/live_validation_multi_protocol/region_targets.json" \
  "${LIVE_FLAG[@]}" \
  "${DATA_PLANE_FLAG[@]}" \
  "${NON_INVASIVE_FLAG[@]}"
