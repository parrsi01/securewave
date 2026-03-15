#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COVERAGE_DIR="${COVERAGE_DIR:-${ROOT_DIR}/artifacts/test_reports/backend}"
mkdir -p "${COVERAGE_DIR}"

TARGETS=(
  tests/integration/test_auth.py
  tests/security/test_security.py
  tests/integration/test_refresh_token_rotation.py
  tests/integration/test_jwt_revocation.py
  tests/integration/test_vpn_profile_generation.py
  tests/integration/test_vpn_profile.py
  tests/integration/test_peer_lifecycle.py
  tests/integration/test_vpn_credentials.py
  tests/integration/test_backend_matrix_additions.py
  tests/integration/test_device_lifecycle_remote_cleanup.py
  tests/integration/test_backend_load_harness.py
  tests/health/test_metrics_endpoints.py
  tests/unit/test_system_metrics_endpoint.py
  tests/unit/test_geo_recommendation.py
  tests/smoke/test_api_endpoints.py
)

DEFAULT_TARGETS="${TARGETS[*]}"
PYTEST_ARGS_DEFAULT="${DEFAULT_TARGETS} --cov=routes --cov=routers --cov=services --cov=models --cov=utils --cov-report=term-missing:skip-covered --cov-report=xml:${COVERAGE_DIR}/coverage.xml --cov-report=html:${COVERAGE_DIR}/html --cov-report=json:${COVERAGE_DIR}/coverage.json"
PYTEST_ARGS="${PYTEST_ARGS:-${PYTEST_ARGS_DEFAULT}}"

if [[ -n "${EXTRA_PYTEST_ARGS:-}" ]]; then
  PYTEST_ARGS="${PYTEST_ARGS} ${EXTRA_PYTEST_ARGS}"
fi

if [[ "${DRY_RUN:-false}" == "true" ]]; then
  echo "PYTEST_ARGS=${PYTEST_ARGS}"
  exit 0
fi

cd "${ROOT_DIR}"
PYTEST_ARGS="${PYTEST_ARGS}" bash "${ROOT_DIR}/scripts/run_backend_tests.sh"
