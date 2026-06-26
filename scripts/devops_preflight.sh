#!/usr/bin/env bash
set -euo pipefail

# Local mirror of the CI quality gates that do not require production secrets.
# Set SKIP_FLUTTER=true to run only backend/static checks.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHON_BIN="${PYTHON_BIN:-$ROOT_DIR/.venv/bin/python}"

if [[ ! -x "$PYTHON_BIN" ]]; then
  PYTHON_BIN="${PYTHON_BIN_FALLBACK:-python3}"
fi

cd "$ROOT_DIR"

echo "== Repository guards =="
bash scripts/verify_ui_v1.sh
bash scripts/check_plan_copy.sh
bash scripts/verify_release_guards.sh
bash scripts/check_xcworkspace_usage.sh

echo "== Website static QA =="
bash scripts/verify_website.sh

echo "== Python security audit =="
"$PYTHON_BIN" -m pip_audit -r requirements.txt
"$PYTHON_BIN" -m pip_audit -r requirements_production.txt
"$PYTHON_BIN" -m bandit -r main.py routes routers services utils database models scripts \
  -x tests,.venv,venv \
  --severity-level medium \
  --confidence-level high

echo "== Backend smoke/security tests =="
"$PYTHON_BIN" -m pytest tests/smoke/test_api_endpoints.py tests/security/test_security.py tests/security/test_log_redaction.py -q

if [[ "${SKIP_FLUTTER:-false}" != "true" ]]; then
  echo "== Flutter static analysis and tests =="
  FORCE_FLUTTER_ENV=true bash scripts/prepare_flutter_env.sh
  (
    cd securewave_app
    flutter pub get
    flutter analyze
    flutter test
  )
fi

echo "OK: DevOps preflight passed."
