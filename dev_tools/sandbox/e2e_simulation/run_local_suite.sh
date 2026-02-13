#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
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
  echo "cloud_excluded=true"
  echo "platforms_validated=android,windows,linux,web (non-apple)"
} > "$OUT_DIR/metadata.txt"

echo "[1/7] Python compile checks"
python3 -m compileall services/ ml/ -q >"$LOG_DIR/python_compileall.txt" 2>&1 || {
  echo "Python compileall failed; see $LOG_DIR/python_compileall.txt"
  exit 1
}

echo "[2/7] Pytest (local-only)"
.venv/bin/pytest -q >"$LOG_DIR/pytest.txt" 2>&1 || {
  echo "Pytest failed; see $LOG_DIR/pytest.txt"
  exit 1
}

echo "[3/7] Real-mode WG profile structure (no live traffic)"
.venv/bin/pytest -q tests_real >"$LOG_DIR/pytest_real_mode.txt" 2>&1 || {
  echo "Real-mode pytest failed; see $LOG_DIR/pytest_real_mode.txt"
  exit 1
}

echo "[4/7] Flutter analyze"
(
  cd securewave_app
  flutter analyze
) >"$LOG_DIR/flutter_analyze.txt" 2>&1 || {
  echo "flutter analyze failed; see $LOG_DIR/flutter_analyze.txt"
  exit 1
}

echo "[5/7] Flutter tests"
(
  cd securewave_app
  flutter test
) >"$LOG_DIR/flutter_test.txt" 2>&1 || {
  echo "flutter test failed; see $LOG_DIR/flutter_test.txt"
  exit 1
}

echo "[6/7] Start local backend (uvicorn + sqlite)"
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
export ENVIRONMENT="development"
export DATABASE_URL="sqlite:///$DB_PATH"
export AUTO_CREATE_TABLES="true"
export ENABLE_SENTRY="false"
export EMAIL_PROVIDER="smtp"
export APP_URL="$BASE_URL"
export DEFAULT_DOMAIN="localhost"
export WG_ENDPOINT="127.0.0.1:51820"
export SECRET_KEY=[REDACTED]
export ACCESS_TOKEN_SECRET="sim-access-secret-stable"
export REFRESH_TOKEN_SECRET="sim-refresh-secret-stable"

# Seed a single fake Hetzner server so /api/vpn/profile can return a usable config.
set +e
.venv/bin/python - <<'PY' >"$LOG_DIR/seed_server.txt" 2>&1
from database.session import SessionLocal
from models.vpn_server import VPNServer

db = SessionLocal()
try:
    if db.query(VPNServer).count() == 0:
        server = VPNServer(
            server_id="ash-001",
            location="Ashburn, US",
            country="US",
            country_code="US",
            city="Ashburn",
            region="Americas",
            latitude=39.0438,
            longitude=-77.4874,
            hcloud_server_id="sim",
            hcloud_server_name="securewave-sim-01",
            hcloud_location="ash",
            hcloud_server_type="cx33",
            hcloud_server_state="running",
            public_ip="203.0.113.10",
            endpoint="203.0.113.10:51820",
            wg_listen_port=51820,
            wg_public_key="dGVzdC1wdWJsaWMta2V5LXByb2ZpbGU=",
            wg_private_key_encrypted="",
            status="active",
            health_status="healthy",
            max_connections=1000,
            current_connections=0,
            tier_restriction=None,
            performance_score=100.0,
        )
        db.add(server)
        db.commit()
finally:
    db.close()
PY
EC=$?
set -e
if [[ $EC -ne 0 ]]; then
  echo "Failed to seed simulation server; see $LOG_DIR/seed_server.txt"
  exit 1
fi

# Network leak/throughput suite requires a real tunnel endpoint.
# This suite runs logic-only simulation.

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

echo "[7/7] Website/API simulation"
.venv/bin/python dev_tools/sandbox/e2e_simulation/website_simulation.py --base-url "$BASE_URL" --out "$OUT_DIR/website_simulation.json" >"$LOG_DIR/website_simulation.txt" 2>&1 || {
  echo "Website simulation failed; see $LOG_DIR/website_simulation.txt"
  exit 1
}

echo "OK" > "$OUT_DIR/STATUS_OK"
echo "Local-only suite complete."
