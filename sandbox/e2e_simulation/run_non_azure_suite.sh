#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

TS="$(date +%Y%m%d_%H%M%S)"
OUT_DIR="artifacts/sim_tests/$TS"
LOG_DIR="$OUT_DIR/logs"
REPORT_DIR="$OUT_DIR/reports"
mkdir -p "$LOG_DIR" "$REPORT_DIR"

echo "Output: $OUT_DIR"

{
  echo "timestamp=$TS"
  echo "branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  echo "commit=$(git rev-parse --short HEAD 2>/dev/null || true)"
  echo "azure_excluded=true"
  echo "platforms_validated=android,windows,linux,web (non-apple)"
} > "$OUT_DIR/metadata.txt"

echo "[1/6] Python compile checks"
python3 -m compileall services/ ml/ -q >"$LOG_DIR/python_compileall.txt" 2>&1 || {
  echo "Python compileall failed; see $LOG_DIR/python_compileall.txt"
  exit 1
}

echo "[2/6] Pytest (non-Azure)"
.venv/bin/pytest -q >"$LOG_DIR/pytest.txt" 2>&1 || {
  echo "Pytest failed; see $LOG_DIR/pytest.txt"
  exit 1
}

echo "[3/6] Flutter analyze"
(
  cd securewave_app
  flutter analyze
) >"$LOG_DIR/flutter_analyze.txt" 2>&1 || {
  echo "flutter analyze failed; see $LOG_DIR/flutter_analyze.txt"
  exit 1
}

echo "[4/6] Flutter tests"
(
  cd securewave_app
  flutter test
) >"$LOG_DIR/flutter_test.txt" 2>&1 || {
  echo "flutter test failed; see $LOG_DIR/flutter_test.txt"
  exit 1
}

echo "[5/6] Start local backend (uvicorn + sqlite)"
PORT="${SIM_PORT:-18080}"
BASE_URL="http://127.0.0.1:$PORT"

case "$BASE_URL" in
  http://127.0.0.1:*|http://localhost:*) ;;
  *)
    echo "Refusing to run with non-local BASE_URL=$BASE_URL"
    exit 1
    ;;
esac

DB_PATH="$OUT_DIR/sim.db"

export TESTING="true"
export DEMO_MODE="true"
export WG_MOCK_MODE="true"
export ENVIRONMENT="development"
export DATABASE_URL="sqlite:///$DB_PATH"
export AUTO_CREATE_TABLES="true"
export ENABLE_APP_INSIGHTS="false"
export ENABLE_SENTRY="false"
export USE_AZURE_KEY_VAULT="false"
export EMAIL_PROVIDER="smtp"
export APP_URL="$BASE_URL"
export DEFAULT_DOMAIN="localhost"
export WG_ENDPOINT="127.0.0.1:51820"
export SECRET_KEY=[REDACTED]
export ACCESS_TOKEN_SECRET="sim-access-secret-stable"
export REFRESH_TOKEN_SECRET="sim-refresh-secret-stable"

# AZURE_SKIPPED: securewave-tests network leak/throughput suite requires a real tunnel endpoint
# (SecureWave uses Azure-hosted WireGuard servers in production). This suite runs logic-only simulation.

.venv/bin/python -m uvicorn main:app --host 127.0.0.1 --port "$PORT" >"$LOG_DIR/uvicorn.txt" 2>&1 &
UVICORN_PID=$!

cleanup() {
  if kill -0 "$UVICORN_PID" 2>/dev/null; then
    kill "$UVICORN_PID" >/dev/null 2>&1 || true
    wait "$UVICORN_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

echo "Waiting for backend health at $BASE_URL/health ..."
.venv/bin/python - <<PY >"$LOG_DIR/backend_wait.txt" 2>&1
import time
from urllib import request

base = "$BASE_URL"
deadline = time.time() + 20
last_err = None
while time.time() < deadline:
    try:
        with request.urlopen(base + "/health", timeout=2) as r:
            if r.status == 200:
                raise SystemExit(0)
    except Exception as e:
        last_err = e
    time.sleep(0.5)
raise SystemExit(f"backend not ready: {last_err}")
PY

echo "[6/6] Website/API simulation"
.venv/bin/python sandbox/e2e_simulation/website_simulation.py --base-url "$BASE_URL" --out "$OUT_DIR/website_simulation.json" >"$LOG_DIR/website_simulation.txt" 2>&1 || {
  echo "Website simulation failed; see $LOG_DIR/website_simulation.txt"
  exit 1
}

echo "OK" > "$OUT_DIR/STATUS_OK"
echo "Non-Azure suite complete."
