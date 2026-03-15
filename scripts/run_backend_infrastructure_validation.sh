#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${MODE:-safe}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
LIVE_HANDSHAKE="${LIVE_HANDSHAKE:-false}"
SSH_BASELINE="${SSH_BASELINE:-false}"

SAFE_CMD=(
  "${PYTHON_BIN}" -m pytest -q
  tests/live_network/test_live_validation_common.py
  tests/live_network/test_live_reporting.py
  tests/live_network/test_network_failure_cases.py
  tests/unit/test_infra_guard_scripts.py
)

BASELINE_CMD=(
  bash "${ROOT_DIR}/scripts/ops/validate_vpn_node_baseline.sh"
)

HANDSHAKE_CMD=(
  bash "${ROOT_DIR}/dev_tools/sandbox/live_validation/run_live_stress_tests.sh"
  --strict
  --linux
  --workers "${LIVE_STRESS_WORKERS:-1}"
  --cycles "${LIVE_STRESS_CYCLES:-1}"
)

if [[ "${DRY_RUN:-false}" == "true" ]]; then
  case "${MODE}" in
    safe)
      printf '%q ' "${SAFE_CMD[@]}"
      printf '\n'
      ;;
    live)
      if [[ "${SSH_BASELINE}" == "true" ]]; then
        printf '%q ' "${BASELINE_CMD[@]}" "$@"
        printf '\n'
      fi
      if [[ "${LIVE_HANDSHAKE}" == "true" ]]; then
        printf '%q ' "${HANDSHAKE_CMD[@]}"
        printf '\n'
      fi
      ;;
    *)
      echo "Unknown MODE: ${MODE}" >&2
      exit 2
      ;;
  esac
  exit 0
fi

cd "${ROOT_DIR}"

case "${MODE}" in
  safe)
    "${SAFE_CMD[@]}"
    ;;
  live)
    if [[ "${SSH_BASELINE}" != "true" && "${LIVE_HANDSHAKE}" != "true" ]]; then
      echo "Set SSH_BASELINE=true and/or LIVE_HANDSHAKE=true for MODE=live." >&2
      exit 2
    fi
    if [[ "${SSH_BASELINE}" == "true" ]]; then
      "${BASELINE_CMD[@]}" "$@"
    fi
    if [[ "${LIVE_HANDSHAKE}" == "true" ]]; then
      "${HANDSHAKE_CMD[@]}"
    fi
    ;;
  *)
    echo "Unknown MODE: ${MODE}" >&2
    exit 2
    ;;
esac
