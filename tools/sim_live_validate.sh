#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

PORT="${SECUREWAVE_SIM_BACKEND_PORT:-8010}"
LOG_FILE="/tmp/securewave_sim_backend_${PORT}.log"
PID_FILE="/tmp/securewave_sim_backend_${PORT}.pid"

cleanup() {
  if [[ -f "${PID_FILE}" ]]; then
    pid="$(cat "${PID_FILE}" 2>/dev/null || true)"
    if [[ -n "${pid}" ]] && kill -0 "${pid}" >/dev/null 2>&1; then
      kill "${pid}" >/dev/null 2>&1 || true
    fi
    rm -f "${PID_FILE}"
  fi
}
trap cleanup EXIT

export ENVIRONMENT=development
export SECUREWAVE_TUNNEL_MODE=simulated
export SECUREWAVE_ALLOW_DEV_SIMULATED_TUNNEL_MODE=1
export SECUREWAVE_ALLOW_DEV_RESETS=1
export SECUREWAVE_ENABLE_SIM_TUNNEL_ENDPOINTS=1
export DB_ECHO=false

echo "[sim-live] starting backend in simulated mode on :${PORT}"
.venv/bin/python -m uvicorn main:app --host 127.0.0.1 --port "${PORT}" >"${LOG_FILE}" 2>&1 &
echo $! >"${PID_FILE}"

for _ in $(seq 1 30); do
  if curl -fsS "http://127.0.0.1:${PORT}/api/health" >/dev/null 2>&1; then
    break
  fi
  sleep 0.3
done
curl -fsS "http://127.0.0.1:${PORT}/api/health" >/dev/null

echo "[sim-live] creating backup + resetting usage/devices"
.venv/bin/python tools/admin/reset_usage_and_devices.py --yes --with-backup

echo "[sim-live] running backend simulation tests"
.venv/bin/pytest -q \
  tests/unit/test_reset_usage_and_devices.py \
  tests/integration/test_simulated_live_usage_flow.py

if [[ "${RUN_FLUTTER_TESTS:-0}" == "1" ]]; then
  echo "[sim-live] running flutter simulation tests"
  (
    cd securewave_app
    flutter test \
      --dart-define=SECUREWAVE_SIM_MODE=true \
      test/server_region_premium_test.dart \
      test/settings_protocol_reason_message_test.dart
  )
fi

echo "[sim-live] validation complete"
