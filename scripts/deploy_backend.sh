#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

PYTHON_BIN="${PYTHON_BIN:-python3}"
VENV_DIR="${VENV_DIR:-.venv}"
ENV_FILE="${ENV_FILE:-.env}"
RUN_TESTS="${RUN_TESTS:-true}"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

need_cmd "$PYTHON_BIN"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "WARN: $ENV_FILE not found. Copying from .env.example.backend"
  [[ -f ".env.example.backend" ]] || fail ".env.example.backend is missing"
  cp ".env.example.backend" "$ENV_FILE"
fi

if [[ ! -d "$VENV_DIR" ]]; then
  "$PYTHON_BIN" -m venv "$VENV_DIR"
fi

source "$VENV_DIR/bin/activate"
python -m pip install --upgrade pip
python -m pip install -r requirements_production.txt
python -m pip install -r requirements_dev.txt

echo "Running Alembic migrations..."
python -m alembic upgrade head

echo "Validating production env constraints..."
python - <<'PY'
from utils.env_validation import production_env_errors
errors = production_env_errors()
if errors:
    print("Production env validation errors:")
    for err in errors:
        print(f"- {err}")
else:
    print("Production env validation passed (or non-production mode).")
PY

if [[ "$RUN_TESTS" == "true" ]]; then
  echo "Running backend health/security smoke suite..."
  TESTING=true DEMO_MODE=true WG_MOCK_MODE=true pytest -q tests/health tests/security/test_secrets_and_rate_limiting.py
fi

echo "Backend deploy checks complete."
echo "Start service with: bash scripts/run_backend.sh"
