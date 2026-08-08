#!/usr/bin/env bash
set -euo pipefail

# Deploys a prebuilt SecureWave container to an explicitly authorized staging
# host.  This is intentionally separate from deploy_production.sh so the
# production guard and its variable names remain unchanged.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_TEMPLATE="$ROOT_DIR/deploy/hetzner/compose.yaml"

fail() {
  echo "$1" >&2
  exit 2
}

validate_host() {
  [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._:-]*$ ]] || \
    fail "SECUREWAVE_STAGING_HOST must be an explicit staging host name or IP."
  case "$1" in
    localhost|localhost.*|127.*|::1|0.0.0.0|http://*|https://*|*/*|*" "*)
      fail "SECUREWAVE_STAGING_HOST must be an explicit staging host name or IP."
      ;;
  esac
}

validate_user() {
  [[ "$1" =~ ^[A-Za-z_][A-Za-z0-9_.-]*$ ]] || \
    fail "SECUREWAVE_STAGING_USER must be a valid remote account name."
}

validate_remote_dir() {
  [[ "$1" =~ ^/[A-Za-z0-9._/-]+$ && "$1" != *"/../"* && "$1" != */.. && "$1" != ../* ]] || \
    fail "SECUREWAVE_STAGING_REMOTE_APP_DIR must be a safe absolute remote path."
}

validate_image_ref() {
  local image="$1"
  local digest
  [[ "$image" =~ ^[A-Za-z0-9][A-Za-z0-9._/@:-]*$ ]] || \
    fail "SECUREWAVE_STAGING_IMAGE must be a safe immutable image reference."
  [[ "$image" == *@sha256:* ]] || \
    fail "SECUREWAVE_STAGING_IMAGE must use a complete sha256 digest; tags are not provably immutable."
  digest="${image##*@sha256:}"
  [[ "$digest" =~ ^[a-fA-F0-9]{64}$ ]] || \
    fail "SECUREWAVE_STAGING_IMAGE must use a complete sha256 digest."
}

verify_staging_approval() {
  local current_sha
  current_sha="$(git -C "$ROOT_DIR" rev-parse HEAD 2>/dev/null || true)"
  [[ -n "$current_sha" && "$current_sha" == "$SECUREWAVE_CANDIDATE_SHA" ]] || \
    fail "SECUREWAVE_CANDIDATE_SHA does not match the current HEAD."
  [[ -z "$(git -C "$ROOT_DIR" status --porcelain --untracked-files=all)" ]] || \
    fail "Refusing staging deployment from a dirty worktree."

  if ! python3 "$ROOT_DIR/scripts/verify_operation_approval.py" \
    --approval-file "$SECUREWAVE_APPROVAL_FILE" \
    --public-key-file "$SECUREWAVE_APPROVAL_PUBLIC_KEY_FILE" \
    --ledger-file "$SECUREWAVE_APPROVAL_LEDGER_FILE" \
    --operation deploy_staging \
    --environment staging \
    --target-ref "$SECUREWAVE_DEPLOY_TARGET_REFERENCE" \
    --candidate-sha "$SECUREWAVE_CANDIDATE_SHA" \
    --consume >/dev/null 2>&1; then
    fail "Signed staging approval validation failed."
  fi
}

required_vars=(
  SECUREWAVE_STAGING_HOST
  SECUREWAVE_STAGING_IMAGE
  SECUREWAVE_STAGING_USER
  SECUREWAVE_STAGING_REMOTE_APP_DIR
)
for name in "${required_vars[@]}"; do
  [[ -n "${!name:-}" ]] || fail "Missing required staging variable: $name"
done

[[ "${CONFIRM_DEPLOY:-}" == "securewave-staging" ]] || \
  fail "Set CONFIRM_DEPLOY=securewave-staging to run a staging deploy."
[[ -f "$COMPOSE_TEMPLATE" ]] || fail "Missing staging compose template."
validate_host "$SECUREWAVE_STAGING_HOST"
validate_user "$SECUREWAVE_STAGING_USER"
validate_remote_dir "$SECUREWAVE_STAGING_REMOTE_APP_DIR"
validate_image_ref "$SECUREWAVE_STAGING_IMAGE"

approval_vars=(
  SECUREWAVE_APPROVAL_FILE
  SECUREWAVE_APPROVAL_PUBLIC_KEY_FILE
  SECUREWAVE_APPROVAL_LEDGER_FILE
  SECUREWAVE_CANDIDATE_SHA
  SECUREWAVE_DEPLOY_TARGET_REFERENCE
)
for name in "${approval_vars[@]}"; do
  [[ -n "${!name:-}" ]] || fail "Missing required staging approval variable: $name"
done
verify_staging_approval

remote="${SECUREWAVE_STAGING_USER}@${SECUREWAVE_STAGING_HOST}"
remote_dir="$SECUREWAVE_STAGING_REMOTE_APP_DIR"
ssh_opts=(
  -o BatchMode=yes
  -o StrictHostKeyChecking=accept-new
)

echo "Staging deployment started."

if ! ssh "${ssh_opts[@]}" "$remote" "mkdir -p '$remote_dir'" >/dev/null 2>&1; then
  fail "Staging host preparation failed."
fi
if ! scp -q "${ssh_opts[@]}" "$COMPOSE_TEMPLATE" "$remote:${remote_dir}/compose.yaml" >/dev/null 2>&1; then
  fail "Staging compose transfer failed."
fi

if ! ssh "${ssh_opts[@]}" "$remote" \
  "set -euo pipefail
   cd '$remote_dir'
   test -s .env
   export SECUREWAVE_IMAGE='$SECUREWAVE_STAGING_IMAGE'
   export SECUREWAVE_ENVIRONMENT=staging
   docker pull '$SECUREWAVE_STAGING_IMAGE' >/dev/null 2>&1
   docker compose --env-file .env config --quiet >/dev/null 2>&1
   docker compose --env-file .env up -d --pull always >/dev/null 2>&1
   docker compose ps >/dev/null 2>&1" >/dev/null 2>&1; then
  fail "Staging container operation failed."
fi

echo "Staging deployment command completed."
