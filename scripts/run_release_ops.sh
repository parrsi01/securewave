#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ENVIRONMENT_NAME="production"
REPO_SLUG="${GITHUB_REPOSITORY:-}"
REF_NAME="$(git rev-parse --abbrev-ref HEAD)"
DISPATCH=false
DRY_RUN=false

VERIFY_SCRIPT_PATH="${VERIFY_PRODUCTION_ENV_SCRIPT:-scripts/verify_production_env.sh}"
SYNC_SCRIPT_PATH="${SYNC_GITHUB_RELEASE_SECRETS_SCRIPT:-scripts/sync_github_release_secrets.sh}"
AUDIT_SCRIPT_PATH="${AUDIT_GITHUB_RELEASE_SECRETS_SCRIPT:-scripts/audit_github_release_secrets.sh}"
RELEASE_WORKFLOW_PATH="${RELEASE_WORKFLOW_FILE:-.github/workflows/flutter-release.yml}"

usage() {
  cat <<'EOF'
Usage: bash scripts/run_release_ops.sh [--env production] [--repo owner/repo] [--ref git-ref] [--dispatch] [--dry-run]

Runs the SecureWave release operator flow:
1. strict local production env validation
2. GitHub production secret sync
3. GitHub production secret audit
4. optional flutter-release workflow dispatch
EOF
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
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
    --ref)
      [[ $# -ge 2 ]] || fail "--ref requires a value."
      REF_NAME="$2"
      shift 2
      ;;
    --dispatch)
      DISPATCH=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
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

if [[ -z "$REPO_SLUG" ]]; then
  REPO_SLUG="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)"
fi
[[ -n "$REPO_SLUG" ]] || fail "Unable to determine GitHub repository slug. Set GITHUB_REPOSITORY or pass --repo owner/repo."

echo "SecureWave release operator flow"
echo "Repository: $REPO_SLUG"
echo "Environment: $ENVIRONMENT_NAME"
echo "Ref: $REF_NAME"
echo "Mode: $([[ "$DRY_RUN" == "true" ]] && echo dry-run || echo apply)"
echo "Dispatch workflow: $DISPATCH"
echo

echo "[1/4] Verify local production environment"
VERIFY_STRICT=true ENVIRONMENT=production bash "$VERIFY_SCRIPT_PATH"

echo
echo "[2/4] Sync GitHub production secrets"
sync_args=(--env "$ENVIRONMENT_NAME" --repo "$REPO_SLUG")
if [[ "$DRY_RUN" == "true" ]]; then
  sync_args+=(--dry-run)
fi
bash "$SYNC_SCRIPT_PATH" "${sync_args[@]}"

echo
echo "[3/4] Audit GitHub production secret inventory"
bash "$AUDIT_SCRIPT_PATH" "$ENVIRONMENT_NAME"

if [[ "$DISPATCH" == "true" && "$DRY_RUN" == "false" ]]; then
  echo
  echo "[4/4] Dispatch release workflow"
  gh workflow run "$RELEASE_WORKFLOW_PATH" --ref "$REF_NAME"
  echo "OK: release workflow dispatched."
elif [[ "$DISPATCH" == "true" ]]; then
  echo
  echo "[4/4] Dispatch release workflow"
  echo "SKIP: dry-run mode does not dispatch GitHub Actions."
else
  echo
  echo "[4/4] Dispatch release workflow"
  echo "SKIP: dispatch not requested."
fi

echo
echo "OK: release operator flow completed."
