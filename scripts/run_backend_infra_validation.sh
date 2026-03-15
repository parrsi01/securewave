#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

RUN_BASELINE=false
RUN_LIVE_VALIDATION=false
RUN_LIVE_STRESS=false
RUN_STABILITY=false
STRICT=false

usage() {
  cat <<'EOF'
Usage:
  scripts/run_backend_infra_validation.sh [--baseline] [--live-validation] [--live-stress] [--stability] [--strict]

Flags:
  --baseline         Run Hetzner fleet/node baseline validation
  --live-validation  Run live WireGuard/API validation harness
  --live-stress      Run live concurrent stress validation harness
  --stability        Run vpn_stability_test.sh (requires VPN_PROFILE_PATH)
  --strict           Forward strict mode to live harnesses

Environment:
  HETZNER_API_TOKEN      Required for --baseline
  LIVE_API_BASE_URL      Required for --live-validation, --live-stress, and --stability
  WG_SSH_KEY_PATH        Recommended for --baseline
  VPN_PROFILE_PATH       Required for --stability
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --baseline) RUN_BASELINE=true; shift ;;
    --live-validation) RUN_LIVE_VALIDATION=true; shift ;;
    --live-stress) RUN_LIVE_STRESS=true; shift ;;
    --stability) RUN_STABILITY=true; shift ;;
    --strict) STRICT=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ "${RUN_BASELINE}" == "false" && "${RUN_LIVE_VALIDATION}" == "false" && "${RUN_LIVE_STRESS}" == "false" && "${RUN_STABILITY}" == "false" ]]; then
  RUN_BASELINE=true
fi

strict_flag=()
if [[ "${STRICT}" == "true" ]]; then
  strict_flag=(--strict)
fi

if [[ "${RUN_BASELINE}" == "true" ]]; then
  "${ROOT_DIR}/scripts/ops/validate_vpn_node_baseline.sh"
fi

if [[ "${RUN_LIVE_VALIDATION}" == "true" ]]; then
  : "${LIVE_API_BASE_URL:?LIVE_API_BASE_URL is required for --live-validation}"
  "${ROOT_DIR}/dev_tools/sandbox/live_validation/run_live_validation.sh" "${strict_flag[@]}"
fi

if [[ "${RUN_LIVE_STRESS}" == "true" ]]; then
  : "${LIVE_API_BASE_URL:?LIVE_API_BASE_URL is required for --live-stress}"
  "${ROOT_DIR}/dev_tools/sandbox/live_validation/run_live_stress_tests.sh" "${strict_flag[@]}"
fi

if [[ "${RUN_STABILITY}" == "true" ]]; then
  : "${LIVE_API_BASE_URL:?LIVE_API_BASE_URL is required for --stability}"
  : "${VPN_PROFILE_PATH:?VPN_PROFILE_PATH is required for --stability}"
  "${ROOT_DIR}/scripts/vpn_stability_test.sh" \
    --api-base-url "${LIVE_API_BASE_URL}" \
    --profile "${VPN_PROFILE_PATH}"
fi
