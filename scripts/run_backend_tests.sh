#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# SecureWave Backend Test Runner
# =============================================================================
# Usage:
#   bash scripts/run_backend_tests.sh                    # Full test suite
#   PYTEST_ARGS="tests/unit -v" bash scripts/run_backend_tests.sh  # Unit only
#   SKIP_INSTALL=true bash scripts/run_backend_tests.sh  # Skip pip install
#
# Environment variables:
#   ENVIRONMENT            - test environment (default: development)
#   DEMO_MODE              - enable demo mode (default: true for tests)
#   WG_MOCK_MODE           - mock wireguard (default: true for tests)
#   PYTEST_ARGS            - pytest arguments (default: "tests -v")
#   SKIP_INSTALL           - skip pip install step (default: false)
#   USE_SYSTEM_PYTHON      - use system python instead of venv (default: false)
#   VENV_DIR               - virtual environment directory (default: .venv)
# =============================================================================

export ENVIRONMENT="${ENVIRONMENT:-development}"
export TESTING="true"
export DEMO_MODE="${DEMO_MODE:-true}"
export WG_MOCK_MODE="${WG_MOCK_MODE:-true}"
export EMAIL_VALIDATOR_CHECK_DELIVERABILITY="false"

# Detect CI environment
IS_CI="${CI:-false}"
if [[ "$IS_CI" == "true" ]]; then
  echo "Running in CI environment"
fi

PYTHON_BIN="${PYTHON_BIN:-python3}"
if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
  PYTHON_BIN="python"
  if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
    echo "ERROR: Python not found."
    echo ""
    echo "HOW TO FIX:"
    echo "  1. Install Python 3.11+: https://www.python.org/downloads/"
    echo "  2. Or use pyenv: pyenv install 3.11"
    echo ""
    exit 1
  fi
fi

echo "Using Python: $("$PYTHON_BIN" --version)"

if [[ "${USE_SYSTEM_PYTHON:-}" != "true" ]]; then
  VENV_DIR="${VENV_DIR:-.venv}"
  if [[ ! -d "$VENV_DIR" ]]; then
    echo "Creating virtual environment at $VENV_DIR..."
    "$PYTHON_BIN" -m venv "$VENV_DIR"
  fi
  PYTHON_BIN="${VENV_DIR}/bin/python"
fi

if [[ "${SKIP_INSTALL:-}" != "true" ]]; then
  echo "Installing dependencies..."
  "$PYTHON_BIN" -m pip install --upgrade pip -q

  if [[ ! -f "requirements_dev.txt" ]]; then
    echo "ERROR: requirements_dev.txt not found."
    echo ""
    echo "HOW TO FIX:"
    echo "  Ensure you're running from the repository root."
    echo "  Current directory: $(pwd)"
    echo ""
    exit 1
  fi

  "$PYTHON_BIN" -m pip install -r requirements_dev.txt -q
fi

# Verify pytest is installed
if ! "$PYTHON_BIN" -m pytest --version >/dev/null 2>&1; then
  echo "ERROR: pytest not installed."
  echo ""
  echo "HOW TO FIX:"
  echo "  $PYTHON_BIN -m pip install pytest pytest-cov pytest-asyncio"
  echo ""
  exit 1
fi

echo "Running tests..."
echo "ENVIRONMENT=$ENVIRONMENT"
echo "DEMO_MODE=$DEMO_MODE"
echo "WG_MOCK_MODE=$WG_MOCK_MODE"
echo ""

PYTEST_ARGS=${PYTEST_ARGS:-"tests -v"}
read -r -a pytest_args <<< "$PYTEST_ARGS"
if ! "$PYTHON_BIN" -m pytest "${pytest_args[@]}"; then
  echo ""
  echo "============================================"
  echo "TEST FAILURE"
  echo "============================================"
  echo ""
  echo "Some tests failed. Check the output above for details."
  echo ""
  echo "Common fixes:"
  echo "  - Missing DATABASE_URL: export DATABASE_URL=sqlite:///:memory:"
  echo "  - Missing SECRET_KEY: export SECRET_KEY=test-secret-key"
  echo "  - Database connection issues: Ensure PostgreSQL/Redis are running"
  echo ""
  exit 1
fi

echo ""
echo "All tests passed."
