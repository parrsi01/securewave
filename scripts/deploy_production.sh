#!/usr/bin/env bash
set -euo pipefail

# Deploys a prebuilt SecureWave container on an already hardened production host.
# This script intentionally refuses to infer hosts, users, images, or confirmation.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_TEMPLATE="${SECUREWAVE_COMPOSE_TEMPLATE:-$ROOT_DIR/deploy/hetzner/compose.yaml}"

mark_missing() {
  echo "$1" >&2
  missing=1
}

validate_production_host() {
  local host="$1"
  if [[ ! "$host" =~ ^[A-Za-z0-9][A-Za-z0-9._:-]*$ ]]; then
    mark_missing "SECUREWAVE_PRODUCTION_HOST must be a production host name or IP."
    return
  fi
  case "$host" in
    localhost|localhost.*|127.*|::1|0.0.0.0|http://*|https://*|*/*|*" "*)
      mark_missing "SECUREWAVE_PRODUCTION_HOST must be a production host name or IP."
      ;;
  esac
}

validate_remote_user() {
  local user="$1"
  if [[ ! "$user" =~ ^[A-Za-z_][A-Za-z0-9_.-]*$ ]]; then
    mark_missing "SECUREWAVE_PRODUCTION_USER must be a valid remote account name."
  fi
}

validate_remote_dir() {
  local directory="$1"
  if [[ ! "$directory" =~ ^/[A-Za-z0-9._/-]+$ || "$directory" == *"/../"* || "$directory" == */.. || "$directory" == ../* ]]; then
    mark_missing "SECUREWAVE_REMOTE_APP_DIR must be a safe absolute remote path."
  fi
}

validate_image_ref() {
  local image="$1"
  local tail tag digest
  local allow_ambiguous="${SECUREWAVE_ALLOW_AMBIGUOUS_TAG:-false}"

  if [[ ! "$image" =~ ^[A-Za-z0-9][A-Za-z0-9._/@:-]*$ ]]; then
    mark_missing "SECUREWAVE_PRODUCTION_IMAGE must be a safe immutable image reference."
    return
  fi
  if [[ "$image" == *@sha256:* ]]; then
    digest="${image##*@sha256:}"
    if [[ ! "$digest" =~ ^[a-fA-F0-9]{64}$ ]]; then
      mark_missing "SECUREWAVE_PRODUCTION_IMAGE must use a complete sha256 digest."
    fi
    return 0
  fi

  tail="${image##*/}"
  if [[ "$tail" != *:* ]]; then
    mark_missing "SECUREWAVE_PRODUCTION_IMAGE must include an immutable tag or @sha256 digest."
    return 0
  fi

  tag="${tail##*:}"
  if [[ -z "$tag" ]]; then
    mark_missing "SECUREWAVE_PRODUCTION_IMAGE has an empty tag."
    return 0
  fi

  case "$tag" in
    latest|main|master|dev|prod|production|stable|current|edge|nightly)
      if [[ "$allow_ambiguous" != "true" ]]; then
        mark_missing "Refusing ambiguous image tag. Emergency ambiguity override is not enabled."
      fi
      ;;
  esac
}

required_vars=(
  SECUREWAVE_PRODUCTION_HOST
  SECUREWAVE_PRODUCTION_IMAGE
)

missing=0
for name in "${required_vars[@]}"; do
  if [[ -z "${!name:-}" ]]; then
    mark_missing "Missing required environment variable: $name"
  fi
done

if [[ "${CONFIRM_DEPLOY:-}" != "securewave-production" ]]; then
  mark_missing "Set CONFIRM_DEPLOY=securewave-production to run a production deploy."
fi
if [[ ! -f "$COMPOSE_TEMPLATE" ]]; then
  mark_missing "Missing production compose template."
fi
if [[ -n "${SECUREWAVE_PRODUCTION_HOST:-}" ]]; then
  validate_production_host "$SECUREWAVE_PRODUCTION_HOST"
fi
if [[ -n "${SECUREWAVE_PRODUCTION_IMAGE:-}" ]]; then
  validate_image_ref "$SECUREWAVE_PRODUCTION_IMAGE"
fi

if [[ "$missing" -ne 0 ]]; then
  exit 2
fi

remote_user="${SECUREWAVE_PRODUCTION_USER:-securewave}"
remote_dir="${SECUREWAVE_REMOTE_APP_DIR:-/opt/securewave}"
validate_remote_user "$remote_user"
validate_remote_dir "$remote_dir"
if [[ "$missing" -ne 0 ]]; then
  exit 2
fi
remote="${remote_user}@${SECUREWAVE_PRODUCTION_HOST}"

ssh_opts=(
  -o BatchMode=yes
  -o StrictHostKeyChecking=accept-new
)

echo "Production deployment started."

# shellcheck disable=SC2029 # The validated local path is intentionally quoted into the remote command.
if ! ssh "${ssh_opts[@]}" "$remote" "mkdir -p '$remote_dir'" >/dev/null 2>&1; then
  echo "Production host preparation failed." >&2
  exit 1
fi
if ! scp -q "${ssh_opts[@]}" "$COMPOSE_TEMPLATE" "$remote:${remote_dir}/compose.yaml" >/dev/null 2>&1; then
  echo "Production compose transfer failed." >&2
  exit 1
fi

# shellcheck disable=SC2029 # The validated local values are intentionally quoted into the remote command.
if ! ssh "${ssh_opts[@]}" "$remote" \
  "set -euo pipefail
   cd '$remote_dir'
   test -s .env
   export SECUREWAVE_IMAGE='${SECUREWAVE_PRODUCTION_IMAGE}'
   export SECUREWAVE_ENVIRONMENT=production
   docker pull '${SECUREWAVE_PRODUCTION_IMAGE}' >/dev/null 2>&1
   docker compose --env-file .env config --quiet >/dev/null 2>&1
   docker compose --env-file .env up -d --pull always >/dev/null 2>&1
   docker compose ps >/dev/null 2>&1" >/dev/null 2>&1; then
  echo "Production container operation failed." >&2
  exit 1
fi

echo "Production deployment command completed."
