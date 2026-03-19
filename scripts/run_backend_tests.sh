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
#   PYTEST_ARGS            - pytest arguments (default: "tests -v")
#   SKIP_INSTALL           - skip pip install step (default: false)
#   USE_SYSTEM_PYTHON      - use system python instead of venv (default: false)
#   VENV_DIR               - virtual environment directory (default: .venv)
#   COVERAGE               - emit coverage artifacts (default: true)
#   ARTIFACTS_DIR          - pytest/coverage artifact directory (default: artifacts/test-results)
#   RUN_LOAD_TESTS         - run load harness after pytest (default: false)
#   LOAD_TEST_ARGS         - arguments for dev_tools/sandbox/load_tests/run_load_tests.py
#   RUN_INFRA_VALIDATION   - run live validation harnesses when LIVE_API_BASE_URL is set (default: false)
#   LIVE_VALIDATION_ARGS   - args for dev_tools/sandbox/live_validation/run_live_validation.sh
#   RUN_LIVE_STRESS        - run live stress after live validation (default: true)
#   LIVE_STRESS_ARGS       - args for dev_tools/sandbox/live_validation/run_live_stress_tests.sh
#   RUN_NODE_BASELINE      - run scripts/ops/validate_vpn_node_baseline.sh (default: false)
#   NODE_BASELINE_ARGS     - args for scripts/ops/validate_vpn_node_baseline.sh
# =============================================================================

export ENVIRONMENT="${ENVIRONMENT:-development}"
export TESTING="true"
export EMAIL_VALIDATOR_CHECK_DELIVERABILITY="false"
export WG_AUTO_REGISTER_PEERS="${WG_AUTO_REGISTER_PEERS:-false}"

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
echo ""

PYTEST_ARGS=${PYTEST_ARGS:-"tests -v"}
ARTIFACTS_DIR="${ARTIFACTS_DIR:-artifacts/test-results}"
COVERAGE="${COVERAGE:-true}"
RUN_LOAD_TESTS="${RUN_LOAD_TESTS:-false}"
RUN_INFRA_VALIDATION="${RUN_INFRA_VALIDATION:-false}"
RUN_LIVE_STRESS="${RUN_LIVE_STRESS:-true}"
RUN_NODE_BASELINE="${RUN_NODE_BASELINE:-false}"
mkdir -p "${ARTIFACTS_DIR}"

read -r -a PYTEST_ARGS_ARRAY <<< "${PYTEST_ARGS}"
PYTEST_CMD=("$PYTHON_BIN" -m pytest "${PYTEST_ARGS_ARRAY[@]}")

if [[ "${COVERAGE}" == "true" ]]; then
  PYTEST_CMD+=(
    "--junitxml=${ARTIFACTS_DIR}/pytest.xml"
    "--cov=main"
    "--cov=routes"
    "--cov=routers"
    "--cov=services"
    "--cov=database"
    "--cov-report=xml:${ARTIFACTS_DIR}/coverage.xml"
    "--cov-report=term-missing"
  )
fi

if ! "${PYTEST_CMD[@]}"; then
  echo ""
  echo "============================================"
  echo "TEST FAILURE"
  echo "============================================"
  echo ""
  echo "Some tests failed. Check the output above for details."
  echo ""
  echo "Common fixes:"
  echo "  - Missing DATABASE_URL: export DATABASE_URL=sqlite:///:memory:"
  echo "  - Missing JWT_SECRET: export JWT_SECRET=testdev"
  echo "  - Database connection issues: Ensure PostgreSQL/Redis are running"
  echo ""
  exit 1
fi

if [[ "${COVERAGE}" == "true" ]]; then
  "$PYTHON_BIN" -m coverage report > "${ARTIFACTS_DIR}/coverage.txt"
  "$PYTHON_BIN" -m coverage html -d "${ARTIFACTS_DIR}/htmlcov" >/dev/null
  echo "Coverage reports:"
  echo "  - ${ARTIFACTS_DIR}/coverage.xml"
  echo "  - ${ARTIFACTS_DIR}/coverage.txt"
  echo "  - ${ARTIFACTS_DIR}/htmlcov/index.html"
fi

if [[ "${RUN_LOAD_TESTS}" == "true" ]]; then
  LOAD_TEST_ARGS="${LOAD_TEST_ARGS:---users 50 --profile-concurrency 10 --real-profile-requests 20 --refresh-attempts 20 --refresh-concurrency 5 --config-iterations 50}"
  read -r -a LOAD_TEST_ARGS_ARRAY <<< "${LOAD_TEST_ARGS}"
  echo ""
  echo "Running load harness..."
  "$PYTHON_BIN" dev_tools/sandbox/load_tests/run_load_tests.py "${LOAD_TEST_ARGS_ARRAY[@]}"
fi

if [[ "${RUN_NODE_BASELINE}" == "true" ]]; then
  read -r -a NODE_BASELINE_ARGS_ARRAY <<< "${NODE_BASELINE_ARGS:-}"
  echo ""
  echo "Running node baseline validation..."
  bash scripts/ops/validate_vpn_node_baseline.sh "${NODE_BASELINE_ARGS_ARRAY[@]}"
fi

if [[ "${RUN_INFRA_VALIDATION}" == "true" ]]; then
  echo ""
  if [[ -z "${LIVE_API_BASE_URL:-}" ]]; then
    echo "Skipping live infrastructure validation: LIVE_API_BASE_URL is not set."
  else
    LIVE_VALIDATION_ARGS="${LIVE_VALIDATION_ARGS:---strict --linux --users 2}"
    read -r -a LIVE_VALIDATION_ARGS_ARRAY <<< "${LIVE_VALIDATION_ARGS}"
    echo "Running live validation harness..."
    bash dev_tools/sandbox/live_validation/run_live_validation.sh "${LIVE_VALIDATION_ARGS_ARRAY[@]}"

    if [[ "${RUN_LIVE_STRESS}" == "true" ]]; then
      LIVE_STRESS_ARGS="${LIVE_STRESS_ARGS:---strict --linux --workers 2 --cycles 2}"
      read -r -a LIVE_STRESS_ARGS_ARRAY <<< "${LIVE_STRESS_ARGS}"
      echo "Running live stress harness..."
      bash dev_tools/sandbox/live_validation/run_live_stress_tests.sh "${LIVE_STRESS_ARGS_ARRAY[@]}"
    fi
  fi
fi

echo ""
echo "All tests passed."
