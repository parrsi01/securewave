#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DRY_RUN="${DRY_RUN:-false}"

usage() {
  cat <<'EOF'
Usage: bash scripts/run_dev_gate.sh

Runs the SecureWave development validation gate.
This intentionally skips production-only release checks such as:
- release preflight secret validation
- GitHub production secret sync/audit
- release tag creation
- root-required runtime scripts

Set DRY_RUN=true to print the commands without executing them.
EOF
}

run_step() {
  local label="$1"
  shift
  echo
  echo "==> $label"
  if [[ "$DRY_RUN" == "true" ]]; then
    printf '+'
    for arg in "$@"; do
      printf ' %q' "$arg"
    done
    printf '\n'
    return 0
  fi
  "$@"
}

run_in_dir() {
  local dir="$1"
  shift
  if [[ "$DRY_RUN" == "true" ]]; then
    printf '+ (cd %q &&' "$dir"
    for arg in "$@"; do
      printf ' %q' "$arg"
    done
    printf ')\n'
    return 0
  fi
  (
    cd "$dir"
    "$@"
  )
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
  "")
    ;;
  *)
    echo "ERROR: unknown argument: $1" >&2
    usage >&2
    exit 1
    ;;
esac

cd "$ROOT_DIR"

echo "SecureWave development gate"
echo "Repo root: $ROOT_DIR"
echo "Mode: $([[ "$DRY_RUN" == "true" ]] && echo dry-run || echo apply)"

run_step "Git history attestation" bash "$ROOT_DIR/scripts/scan_git_history_for_secrets.sh"
run_step "Working tree + history secret scan" bash "$ROOT_DIR/scripts/secret_scan.sh"
run_step "Release guard verification" bash "$ROOT_DIR/scripts/verify_release_guards.sh"

run_step "Backend import gate" .venv/bin/python -c "import main"
run_step "Backend test gate" pytest -q

run_step "Flutter analyze" run_in_dir "$ROOT_DIR/securewave_app" flutter analyze
run_step "Flutter test" run_in_dir "$ROOT_DIR/securewave_app" flutter test
run_step "Flutter Linux UI smoke" run_in_dir "$ROOT_DIR/securewave_app" flutter test integration_test/ui_debug_smoke_test.dart -d linux --reporter expanded
run_step "Flutter Linux session lifecycle" run_in_dir "$ROOT_DIR/securewave_app" flutter test integration_test/session_lifecycle_test.dart -d linux --reporter expanded
run_step "Flutter Linux integration script" run_in_dir "$ROOT_DIR/securewave_app" bash ./scripts/run_linux_integration_tests.sh
run_step "Flutter release Linux smoke checks" bash "$ROOT_DIR/securewave_app/scripts/run_release_linux_smoke_checks.sh"

run_step "Website validation suite" pytest -q \
  tests/unit/test_ui_pages.py \
  tests/preview/test_assets_loaded.py \
  tests/preview/test_http_status.py \
  tests/preview/test_api_proxy.py \
  tests/e2e/test_full_site_flow.py

run_step "Go test gate" run_in_dir "$ROOT_DIR/netopsd" go test ./...
run_step "Go build gate" run_in_dir "$ROOT_DIR/netopsd" go build ./...

run_step "Security pytest suite" pytest -q tests/security
run_step "Dependency audit" .venv/bin/pip-audit -r requirements.txt
run_step "Runtime guard tests" pytest -q \
  tests/unit/test_release_mock_vpn_guards.py \
  tests/unit/test_tunnel_runtime_mode_guard.py \
  tests/unit/test_region_health_watchdog.py \
  tests/integration/test_wireguard_policy_routing_regression.py

echo
echo "OK: SecureWave development gate completed."
