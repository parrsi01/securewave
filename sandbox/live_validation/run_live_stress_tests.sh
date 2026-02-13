#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${LIVE_VALIDATION_OUTPUT_DIR:-$ROOT_DIR/artifacts/live_validation}"
PYTHON_BIN="${PYTHON_BIN:-$ROOT_DIR/.venv/bin/python}"

if [[ ! -x "$PYTHON_BIN" ]]; then
  PYTHON_BIN="${PYTHON_BIN_FALLBACK:-python3}"
fi

STRICT=false
LINUX=false
WINDOWS=false
ANDROID=false
CYCLES="${LIVE_STRESS_CYCLES:-4}"
WORKERS="${LIVE_STRESS_WORKERS:-4}"
ENABLE_TUNNEL=true

if [[ "${LIVE_STRESS_ENABLE_TUNNEL:-true}" == "false" || "${LIVE_STRESS_ENABLE_TUNNEL:-1}" == "0" ]]; then
  ENABLE_TUNNEL=false
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --strict)
      STRICT=true
      ;;
    --linux)
      LINUX=true
      ;;
    --windows)
      WINDOWS=true
      ;;
    --android)
      ANDROID=true
      ;;
    --cycles)
      CYCLES="$2"
      shift
      ;;
    --workers)
      WORKERS="$2"
      shift
      ;;
    --no-tunnel)
      ENABLE_TUNNEL=false
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
  shift
done

mkdir -p "$OUT_DIR"

flags=()
if [[ "$STRICT" == "true" ]]; then
  flags+=(--strict)
fi
if [[ "$LINUX" == "true" ]]; then
  flags+=(--linux)
fi
if [[ "$WINDOWS" == "true" ]]; then
  flags+=(--windows)
fi
if [[ "$ANDROID" == "true" ]]; then
  flags+=(--android)
fi
if [[ "$ENABLE_TUNNEL" == "true" ]]; then
  flags+=(--enable-tunnel)
fi

"$PYTHON_BIN" "$ROOT_DIR/sandbox/system_audit/system_audit_probe.py" \
  --output-dir "$ROOT_DIR/artifacts/system_audit" \
  --api-base-url "${LIVE_API_BASE_URL:?LIVE_API_BASE_URL is required}" \
  --label "before_live_stress_tests" || true

"$PYTHON_BIN" "$ROOT_DIR/sandbox/live_validation/live_stress_runner.py" \
  --output-dir "$OUT_DIR" \
  --api-base-url "${LIVE_API_BASE_URL:?LIVE_API_BASE_URL is required}" \
  --cycles "$CYCLES" \
  --workers "$WORKERS" \
  "${flags[@]}"

"$PYTHON_BIN" "$ROOT_DIR/sandbox/system_audit/system_audit_probe.py" \
  --output-dir "$ROOT_DIR/artifacts/system_audit" \
  --api-base-url "${LIVE_API_BASE_URL:?LIVE_API_BASE_URL is required}" \
  --label "after_live_stress_tests" || true

echo "Live stress tests complete. Metrics in: $OUT_DIR"
