#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LATEST_FILE="${ROOT_DIR}/reports/regression_latest.txt"
INTERVAL_SECONDS="${SW_REGRESSION_INTERVAL_SECONDS:-15}"
MAX_ATTEMPTS="${SW_REGRESSION_MAX_ATTEMPTS:-0}"

if [[ "${EUID}" -ne 0 ]]; then
  echo "ERROR: run as root (sudo)" >&2
  exit 2
fi

if ! [[ "${INTERVAL_SECONDS}" =~ ^[0-9]+$ ]]; then
  echo "ERROR: SW_REGRESSION_INTERVAL_SECONDS must be a non-negative integer" >&2
  exit 2
fi
if ! [[ "${MAX_ATTEMPTS}" =~ ^[0-9]+$ ]]; then
  echo "ERROR: SW_REGRESSION_MAX_ATTEMPTS must be a non-negative integer" >&2
  exit 2
fi

mkdir -p "${ROOT_DIR}/reports"
attempt=0

while :; do
  attempt=$((attempt + 1))
  tmp_file="${LATEST_FILE}.tmp"
  started_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  set +e
  {
    echo "loop_attempt=${attempt}"
    echo "started_at=${started_at}"
    echo "latest_file=${LATEST_FILE}"
    echo

    "${ROOT_DIR}/scripts/regression_vpn_stack.sh"
    run_rc=$?

    echo
    echo "exit_code=${run_rc}"
    if [[ "${run_rc}" -eq 0 ]]; then
      echo "status=PASS"
    else
      echo "status=FAIL"
    fi
    echo "finished_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  } >"${tmp_file}" 2>&1
  set -e

  mv -f "${tmp_file}" "${LATEST_FILE}"

  if grep -q '^status=PASS$' "${LATEST_FILE}"; then
    echo "[loop] PASS on attempt ${attempt}; latest report: ${LATEST_FILE}"
    exit 0
  fi

  echo "[loop] FAIL on attempt ${attempt}; latest report overwritten at ${LATEST_FILE}"

  if [[ "${MAX_ATTEMPTS}" -gt 0 && "${attempt}" -ge "${MAX_ATTEMPTS}" ]]; then
    echo "[loop] max attempts reached (${MAX_ATTEMPTS})"
    exit 1
  fi

  sleep "${INTERVAL_SECONDS}"
done
