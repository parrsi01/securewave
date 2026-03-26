#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${SECUREWAVE_RELEASE_ENV_FILE:-$HOME/.config/securewave/release.env}"
ENVIRONMENT_NAME="production"
REPO_SLUG="${GITHUB_REPOSITORY:-}"
SYNC_GITHUB_SECRETS=false
RUN_SUDO_RUNTIME_CHECKS=false
REWRITE_HISTORY=false
YES_REWRITE_HISTORY=false
PUSH_REWRITTEN_HISTORY=false
TAG_NAME=""

usage() {
  cat <<'EOF'
Usage: bash scripts/run_release_gate_one_shot.sh [options]

Runs the SecureWave pre-release flow from the repo root:
1. optional git-history secret attestation/remediation
2. local release env load
3. release preflight + guard scripts
4. optional GitHub secret sync/audit
5. optional release tag create/push
6. backend, Flutter, website, Go, security, and runtime validation

Options:
  --env-file PATH            Source release env from PATH
  --env NAME                 GitHub environment name (default: production)
  --repo OWNER/REPO          GitHub repo slug for secret sync/audit
  --sync-github-secrets      Push locally loaded secrets to GitHub env, then audit
  --sudo-runtime-checks      Run root-required runtime checks with sudo
  --rewrite-history          Run the history rewrite helper after history scan
  --yes-rewrite-history      Non-interactively confirm the history rewrite helper
  --push-rewritten-history   Force-push rewritten branches and tags after rewrite
  --tag vX.Y.Z               Create and push a release tag on HEAD
  -h, --help                 Show this help

Examples:
  bash scripts/run_release_gate_one_shot.sh --env-file ~/.config/securewave/release.env --sync-github-secrets --sudo-runtime-checks --tag v1.2.3
  bash scripts/run_release_gate_one_shot.sh --rewrite-history --yes-rewrite-history --push-rewritten-history
EOF
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

run_step() {
  local label="$1"
  shift
  echo
  echo "==> $label"
  "$@"
}

run_step_allow_failure() {
  local label="$1"
  shift
  echo
  echo "==> $label"
  set +e
  "$@"
  local status=$?
  set -e
  return "$status"
}

run_in_dir() {
  local dir="$1"
  shift
  (
    cd "$dir"
    "$@"
  )
}

load_env_file() {
  [[ -f "$ENV_FILE" ]] || fail "Release env file not found: $ENV_FILE"
  [[ -r "$ENV_FILE" ]] || fail "Release env file is not readable: $ENV_FILE"

  local perm_octal
  perm_octal="$(stat -c '%a' "$ENV_FILE" 2>/dev/null || true)"
  [[ -n "$perm_octal" ]] || fail "Unable to read permissions for $ENV_FILE"
  if (( (10#$perm_octal % 100) != 0 )); then
    fail "Release env file must not be readable by group/other: $ENV_FILE (mode $perm_octal)"
  fi

  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
}

rewrite_history() {
  if [[ "$YES_REWRITE_HISTORY" == "true" ]]; then
    printf 'rewrite-history\n' | bash "$ROOT_DIR/scripts/history_secret_remediation_filter_repo.sh"
  else
    bash "$ROOT_DIR/scripts/history_secret_remediation_filter_repo.sh"
  fi
}

push_rewritten_history() {
  git -C "$ROOT_DIR" push --force --all
  git -C "$ROOT_DIR" push --force --tags
}

create_and_push_tag() {
  [[ -n "$TAG_NAME" ]] || return 0
  git -C "$ROOT_DIR" rev-parse "$TAG_NAME" >/dev/null 2>&1 && fail "Tag already exists locally: $TAG_NAME"
  git -C "$ROOT_DIR" tag "$TAG_NAME"
  git -C "$ROOT_DIR" push origin "$TAG_NAME"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-file)
      [[ $# -ge 2 ]] || fail "--env-file requires a value."
      ENV_FILE="$2"
      shift 2
      ;;
    --env)
      [[ $# -ge 2 ]] || fail "--env requires a value."
      ENVIRONMENT_NAME="$2"
      shift 2
      ;;
    --repo)
      [[ $# -ge 2 ]] || fail "--repo requires a value."
      REPO_SLUG="$2"
      shift 2
      ;;
    --sync-github-secrets)
      SYNC_GITHUB_SECRETS=true
      shift
      ;;
    --sudo-runtime-checks)
      RUN_SUDO_RUNTIME_CHECKS=true
      shift
      ;;
    --rewrite-history)
      REWRITE_HISTORY=true
      shift
      ;;
    --yes-rewrite-history)
      YES_REWRITE_HISTORY=true
      shift
      ;;
    --push-rewritten-history)
      PUSH_REWRITTEN_HISTORY=true
      shift
      ;;
    --tag)
      [[ $# -ge 2 ]] || fail "--tag requires a value."
      TAG_NAME="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

if [[ "$YES_REWRITE_HISTORY" == "true" && "$REWRITE_HISTORY" != "true" ]]; then
  fail "--yes-rewrite-history requires --rewrite-history."
fi
if [[ "$PUSH_REWRITTEN_HISTORY" == "true" && "$REWRITE_HISTORY" != "true" ]]; then
  fail "--push-rewritten-history requires --rewrite-history."
fi

cd "$ROOT_DIR"

echo "SecureWave one-shot release gate"
echo "Repo root: $ROOT_DIR"
echo "Env file: $ENV_FILE"
echo "GitHub env: $ENVIRONMENT_NAME"
echo "GitHub repo: ${REPO_SLUG:-<auto>}"
echo "Rewrite history: $REWRITE_HISTORY"
echo "Sync GitHub secrets: $SYNC_GITHUB_SECRETS"
echo "Run sudo runtime checks: $RUN_SUDO_RUNTIME_CHECKS"
echo "Tag: ${TAG_NAME:-<none>}"

if [[ "$REWRITE_HISTORY" == "true" ]]; then
  if ! run_step_allow_failure "Pre-rewrite git history attestation (expected to fail until remediation)" bash "$ROOT_DIR/scripts/scan_git_history_for_secrets.sh"; then
    :
  fi
  run_step "History rewrite helper" rewrite_history
  run_step "Post-rewrite git history attestation" bash "$ROOT_DIR/scripts/scan_git_history_for_secrets.sh"
  run_step "Post-rewrite secret scan" bash "$ROOT_DIR/scripts/secret_scan.sh"
  if [[ "$PUSH_REWRITTEN_HISTORY" == "true" ]]; then
    run_step "Force-push rewritten history" push_rewritten_history
  fi
else
  run_step "Git history attestation" bash "$ROOT_DIR/scripts/scan_git_history_for_secrets.sh"
  run_step "Working tree + history secret scan" bash "$ROOT_DIR/scripts/secret_scan.sh"
fi

run_step "Load release env file" load_env_file
run_step "Release preflight" bash "$ROOT_DIR/scripts/release_preflight.sh"
run_step "Release guard verification" bash "$ROOT_DIR/scripts/verify_release_guards.sh"
run_step "Create and push release tag" create_and_push_tag

if [[ "$SYNC_GITHUB_SECRETS" == "true" ]]; then
  sync_args=(--env "$ENVIRONMENT_NAME")
  if [[ -n "$REPO_SLUG" ]]; then
    sync_args+=(--repo "$REPO_SLUG")
  fi
  run_step "Sync GitHub production secrets" bash "$ROOT_DIR/scripts/sync_github_release_secrets.sh" "${sync_args[@]}"
  run_step "Audit GitHub production secrets" bash "$ROOT_DIR/scripts/audit_github_release_secrets.sh" "$ENVIRONMENT_NAME"
fi

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

if [[ "$RUN_SUDO_RUNTIME_CHECKS" == "true" ]]; then
  run_step "WireGuard regression verification (sudo)" sudo bash "$ROOT_DIR/scripts/verify_wireguard_regression.sh"
  run_step "Teardown safety verification (sudo)" sudo bash "$ROOT_DIR/scripts/verify_teardown_safety.sh"
else
  echo
  echo "==> Skipping root-required runtime checks"
  echo "Pass --sudo-runtime-checks to run:"
  echo "  sudo bash scripts/verify_wireguard_regression.sh"
  echo "  sudo bash scripts/verify_teardown_safety.sh"
fi

echo
echo "OK: SecureWave one-shot release gate completed."
