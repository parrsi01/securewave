#!/usr/bin/env bash
set -euo pipefail

# One-shot launch validation runner.
#
# This is intentionally pragmatic:
# - Runs local CI-safe suites (tests + chaos/benchmark/leak + geo harness + inprocess audit)
# - Optionally runs live network validation if LIVE_API_BASE_URL is set (WireGuard requires root)
# - Emits a lightweight operator summary under artifacts/launch_validation/<run_id>/

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

STRICT="false"
LIVE_MODE="auto" # auto|on|off

usage() {
  cat <<EOF
Usage: $0 [--strict] [--live|--no-live]

Options:
  --strict     Treat skipped live prerequisites as failures.
  --live       Force live suite (requires LIVE_API_BASE_URL).
  --no-live    Skip live suite even if LIVE_API_BASE_URL is set.

Env (live suite):
  LIVE_API_BASE_URL         Base URL for deployed backend (https://...)
  LIVE_VALIDATION_USERS     Default: 2

Outputs:
  - artifacts/launch_validation/<run_id>/
  - artifacts/launch_orchestrator_summary.md (via generator)
  - artifacts/launch_alert_matrix.md
  - artifacts/operator_playbooks_index.md
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --strict) STRICT="true"; shift ;;
    --live) LIVE_MODE="on"; shift ;;
    --no-live) LIVE_MODE="off"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

RUN_ID="$(date -u +"%Y%m%d_%H%M%S")"
OUT_DIR="${ROOT_DIR}/artifacts/launch_validation/${RUN_ID}"
LOG_DIR="${OUT_DIR}/logs"
mkdir -p "${LOG_DIR}"

PY="${ROOT_DIR}/.venv/bin/python"
if [[ ! -x "${PY}" ]]; then
  PY="python3"
fi
PYTEST="${ROOT_DIR}/.venv/bin/pytest"
if [[ ! -x "${PYTEST}" ]]; then
  PYTEST="pytest"
fi

passes=()
fails=()
skips=()
overall_rc=0

run_step() {
  local name="$1"
  shift
  local log="${LOG_DIR}/${name}.log"

  echo "==> ${name}"
  set +e
  "$@" >"${log}" 2>&1
  local rc=$?
  set -e

  if [[ $rc -eq 0 ]]; then
    echo "[PASS] ${name}"
    passes+=("${name}")
  else
    echo "[FAIL] ${name} (rc=${rc})"
    fails+=("${name}")
    overall_rc=1
  fi
  return 0
}

skip_step() {
  local name="$1"
  local reason="$2"
  echo "[SKIP] ${name}: ${reason}"
  skips+=("${name}")
  echo "${reason}" >"${LOG_DIR}/${name}.log"
  if [[ "${STRICT}" == "true" ]]; then
    overall_rc=1
  fi
}

echo "run_id=${RUN_ID}" >"${OUT_DIR}/metadata.txt"
echo "generated_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")" >>"${OUT_DIR}/metadata.txt"
echo "strict=${STRICT}" >>"${OUT_DIR}/metadata.txt"

# 1) Static web smoke check (UI files only; no server)
run_step "web_smoke_check" bash "${ROOT_DIR}/scripts/web_smoke_check.sh" "${ROOT_DIR}/static" "${OUT_DIR}/web_smoke_check.txt"

# 2) Targeted pytest gates (includes tier isolation + geo ordering + stripe hardening)
run_step "pytest_launch_gates" "${PYTEST}" -q \
  tests/smoke \
  tests/health/test_metrics_endpoints.py \
  tests/integration/test_vpn_profile.py \
  tests/unit/test_geo_recommendation.py \
  tests/integration/test_stripe_hardening.py

# 3) Offline geo recommendation harness artifact
run_step "geo_reco_harness" "${PY}" "${ROOT_DIR}/dev_tools/sandbox/geo_reco/run_geo_reco.py" --output-dir "${OUT_DIR}/geo_reco"

# 4) Local in-process metrics/system audit (works even when sockets are restricted)
run_step "system_audit_inprocess" "${PY}" "${ROOT_DIR}/dev_tools/sandbox/system_audit/run_local_system_audit.py"

# 5) Chaos/benchmark/leak strict suites + master report
run_step "chaos_suite_strict" bash "${ROOT_DIR}/dev_tools/sandbox/chaos_tests/run_chaos_suite.sh" --strict
run_step "benchmark_suite_strict" bash "${ROOT_DIR}/dev_tools/sandbox/benchmark/run_benchmarks.sh" --strict
run_step "leak_suite_strict" bash "${ROOT_DIR}/dev_tools/sandbox/leak_tests/run_leak_tests.sh" --strict
run_step "validation_master_report" "${PY}" "${ROOT_DIR}/scripts/generate_validation_master_report.py"

# 6) Optional live validation suite (real WireGuard + DNS + throughput probes)
LIVE_API_BASE_URL="${LIVE_API_BASE_URL:-}"
want_live="false"
if [[ "${LIVE_MODE}" == "on" ]]; then
  want_live="true"
elif [[ "${LIVE_MODE}" == "off" ]]; then
  want_live="false"
else
  [[ -n "${LIVE_API_BASE_URL}" ]] && want_live="true" || want_live="false"
fi

if [[ "${want_live}" == "true" ]]; then
  if [[ -z "${LIVE_API_BASE_URL}" ]]; then
    skip_step "live_suite" "LIVE_API_BASE_URL not set"
  else
    # The live validation harness requires root to bring up wg-quick. Use sudo when available.
    if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
      if command -v sudo >/dev/null 2>&1; then
        run_step "live_validation_linux_strict" sudo -E bash "${ROOT_DIR}/dev_tools/sandbox/live_validation/run_live_validation.sh" --strict --linux --users "${LIVE_VALIDATION_USERS:-2}"
        run_step "live_stress_linux_strict" sudo -E bash "${ROOT_DIR}/dev_tools/sandbox/live_validation/run_live_stress_tests.sh" --strict --linux --workers "${LIVE_STRESS_WORKERS:-2}" --cycles "${LIVE_STRESS_CYCLES:-2}"
      else
        skip_step "live_validation_linux_strict" "requires root or sudo"
        skip_step "live_stress_linux_strict" "requires root or sudo"
      fi
    else
      run_step "live_validation_linux_strict" bash "${ROOT_DIR}/dev_tools/sandbox/live_validation/run_live_validation.sh" --strict --linux --users "${LIVE_VALIDATION_USERS:-2}"
      run_step "live_stress_linux_strict" bash "${ROOT_DIR}/dev_tools/sandbox/live_validation/run_live_stress_tests.sh" --strict --linux --workers "${LIVE_STRESS_WORKERS:-2}" --cycles "${LIVE_STRESS_CYCLES:-2}"
    fi

    # Consolidated Hetzner smoke runner (best-effort; continues even if wg isn't available).
    run_step "live_hetzner_smoke_runner" bash "${ROOT_DIR}/sandbox/live_hetzner/run_live_hetzner_validation_linux.sh"

    # Alert checks (best-effort; requires auth to be meaningful).
    run_step "live_alert_checks" "${PY}" "${ROOT_DIR}/sandbox/live_hetzner/alerting/check_alerts.py" \
      --api-base-url "${LIVE_API_BASE_URL}" \
      --out-json "${OUT_DIR}/live_alerts.json" \
      --out-md "${OUT_DIR}/live_alerts.md"
  fi
else
  skip_step "live_suite" "disabled"
fi

# 7) Generate operator-facing launch artifacts (static docs + pointers)
run_step "launch_orchestrator_reports" "${PY}" "${ROOT_DIR}/scripts/generate_launch_orchestrator_reports.py"

cat >"${OUT_DIR}/summary.md" <<EOF
# Launch Validation Summary

- Run ID: \`${RUN_ID}\`
- Generated: \`$(date -u +"%Y-%m-%dT%H:%M:%SZ")\`
- Strict: **${STRICT}**

## Results

- Passed: **${#passes[@]}**
- Failed: **${#fails[@]}**
- Skipped: **${#skips[@]}**

### Failed Steps
$(printf "%s\n" "${fails[@]}" | sed 's/^/- /')

### Skipped Steps
$(printf "%s\n" "${skips[@]}" | sed 's/^/- /')

## Key Artifacts

- Validation master: \`${ROOT_DIR}/artifacts/validation_master_report.md\`
- Launch summary: \`${ROOT_DIR}/artifacts/launch_orchestrator_summary.md\`
- Alert matrix: \`${ROOT_DIR}/artifacts/launch_alert_matrix.md\`
- Playbooks index: \`${ROOT_DIR}/artifacts/operator_playbooks_index.md\`
- Live Hetzner smoke (latest): \`${ROOT_DIR}/artifacts/live_hetzner_smoke_report.md\`
EOF

cp "${OUT_DIR}/summary.md" "${ROOT_DIR}/artifacts/launch_validation_latest_summary.md" >/dev/null 2>&1 || true

echo ""
echo "Outputs:"
echo "- ${OUT_DIR}/summary.md"
echo "- ${LOG_DIR}/"
echo ""

exit "${overall_rc}"
