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
  case "$host" in
    localhost|localhost.*|127.*|::1|0.0.0.0|http://*|https://*|*/*|*" "*)
      mark_missing "SECUREWAVE_PRODUCTION_HOST must be a production host name or IP, not '$host'."
      ;;
  esac
}

validate_image_ref() {
  local image="$1"
  local tail tag
  local allow_ambiguous="${SECUREWAVE_ALLOW_AMBIGUOUS_TAG:-false}"

  if [[ "$image" == *@sha256:* ]]; then
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
        mark_missing "Refusing ambiguous image tag '$tag'. Set SECUREWAVE_ALLOW_AMBIGUOUS_TAG=true only for an intentional emergency deploy."
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
  mark_missing "Missing production compose template: $COMPOSE_TEMPLATE"
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
remote="${remote_user}@${SECUREWAVE_PRODUCTION_HOST}"

ssh_opts=(
  -o BatchMode=yes
  -o StrictHostKeyChecking=accept-new
)

echo "Deploying ${SECUREWAVE_PRODUCTION_IMAGE} to ${remote}:${remote_dir}"

ssh "${ssh_opts[@]}" "$remote" "mkdir -p '$remote_dir'"
scp "${ssh_opts[@]}" "$COMPOSE_TEMPLATE" "$remote:${remote_dir}/compose.yaml"

ssh "${ssh_opts[@]}" "$remote" \
  "set -euo pipefail
   cd '$remote_dir'
   test -s .env || { echo 'Missing production env file: ${remote_dir}/.env' >&2; exit 2; }
   export SECUREWAVE_IMAGE='${SECUREWAVE_PRODUCTION_IMAGE}'
   docker pull '${SECUREWAVE_PRODUCTION_IMAGE}'
   docker compose --env-file .env config --quiet
   docker compose --env-file .env up -d --pull always
   docker compose ps"
