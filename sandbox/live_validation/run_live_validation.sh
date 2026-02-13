#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${LIVE_VALIDATION_OUTPUT_DIR:-$ROOT_DIR/artifacts/live_validation}"
PYTHON_BIN="${PYTHON_BIN:-$ROOT_DIR/.venv/bin/python}"

if [[ ! -x "$PYTHON_BIN" ]]; then
  PYTHON_BIN="${PYTHON_BIN_FALLBACK:-python3}"
fi

STRICT=false
EXECUTE_FAULTS=false
PLATFORM="${LIVE_VALIDATION_PLATFORM:-auto}"
USERS="${LIVE_VALIDATION_USERS:-3}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --strict)
      STRICT=true
      ;;
    --execute-faults)
      EXECUTE_FAULTS=true
      ;;
    --linux)
      PLATFORM="linux"
      ;;
    --windows)
      PLATFORM="windows"
      ;;
    --android)
      PLATFORM="android"
      ;;
    --users)
      USERS="$2"
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
  shift
done

mkdir -p "$OUT_DIR"

status_fail=0

strict_flag=()
if [[ "$STRICT" == "true" ]]; then
  strict_flag=(--strict)
fi

fault_execute_flag=()
if [[ "$EXECUTE_FAULTS" == "true" ]]; then
  fault_execute_flag=(--execute)
fi

run_step() {
  local name="$1"
  shift
  if "$@"; then
    echo "[PASS] $name"
  else
    echo "[FAIL] $name"
    status_fail=1
  fi
}

run_step "live_e2e_validate" \
  "$PYTHON_BIN" "$ROOT_DIR/sandbox/live_validation/live_e2e_validate.py" \
  --output-dir "$OUT_DIR" \
  --api-base-url "${LIVE_API_BASE_URL:?LIVE_API_BASE_URL is required}" \
  --users "$USERS" \
  --platform "$PLATFORM" \
  "${strict_flag[@]}"

run_step "system_audit_before" \
  "$PYTHON_BIN" "$ROOT_DIR/sandbox/system_audit/system_audit_probe.py" \
  --output-dir "$ROOT_DIR/artifacts/system_audit" \
  --api-base-url "${LIVE_API_BASE_URL:?LIVE_API_BASE_URL is required}" \
  --label "before_live_validation"

run_step "geo_latency_probe" \
  "$PYTHON_BIN" "$ROOT_DIR/sandbox/live_validation/geo_latency_probe.py" \
  --output-dir "$OUT_DIR" \
  --config "$ROOT_DIR/sandbox/live_validation/geo_targets.json"

run_step "network_failure_cases" \
  "$PYTHON_BIN" "$ROOT_DIR/sandbox/live_validation/network_failure_cases.py" \
  --output-dir "$OUT_DIR" \
  --api-base-url "${LIVE_API_BASE_URL:?LIVE_API_BASE_URL is required}" \
  "${strict_flag[@]}" \
  "${fault_execute_flag[@]}"

run_step "system_audit_after" \
  "$PYTHON_BIN" "$ROOT_DIR/sandbox/system_audit/system_audit_probe.py" \
  --output-dir "$ROOT_DIR/artifacts/system_audit" \
  --api-base-url "${LIVE_API_BASE_URL:?LIVE_API_BASE_URL is required}" \
  --label "after_live_validation"

run_step "readiness_report" \
  "$PYTHON_BIN" "$ROOT_DIR/sandbox/live_validation/reporting.py" --output-dir "$OUT_DIR"

# Ensure required artifacts exist even when steps fail early.
if [[ ! -f "$OUT_DIR/handshake_stats.csv" ]]; then
  cat > "$OUT_DIR/handshake_stats.csv" <<'CSV'
timestamp,user,platform,interface,server_endpoint,handshake_ms,success,external_ip_before,external_ip_after,external_ip_changed
CSV
fi

if [[ ! -f "$OUT_DIR/dns_checks.csv" ]]; then
  cat > "$OUT_DIR/dns_checks.csv" <<'CSV'
timestamp,user,platform,interface,expected_dns,observed_dns,status,leaked
CSV
fi

if [[ ! -f "$OUT_DIR/geo_latency_report.csv" ]]; then
  cat > "$OUT_DIR/geo_latency_report.csv" <<'CSV'
timestamp,region,endpoint,iteration,measured_latency_ms,latency_offset_ms,effective_latency_ms,source,status
CSV
fi

if [[ "$status_fail" -ne 0 ]]; then
  exit 1
fi

echo "Live validation complete. Output: $OUT_DIR"
