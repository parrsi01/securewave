#!/usr/bin/env bash
set -euo pipefail

# Deploys a prebuilt SecureWave container on an already hardened production host.
# This script intentionally refuses to infer hosts, users, images, or confirmation.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_TEMPLATE="${SECUREWAVE_COMPOSE_TEMPLATE:-$ROOT_DIR/deploy/hetzner/compose.yaml}"

required_vars=(
  SECUREWAVE_PRODUCTION_HOST
  SECUREWAVE_PRODUCTION_IMAGE
)

missing=0
for name in "${required_vars[@]}"; do
  if [[ -z "${!name:-}" ]]; then
    echo "Missing required environment variable: $name" >&2
    missing=1
  fi
done

if [[ "${CONFIRM_DEPLOY:-}" != "securewave-production" ]]; then
  echo "Set CONFIRM_DEPLOY=securewave-production to run a production deploy." >&2
  missing=1
fi
if [[ ! -f "$COMPOSE_TEMPLATE" ]]; then
  echo "Missing production compose template: $COMPOSE_TEMPLATE" >&2
  missing=1
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
   test -f .env || { echo 'Missing production env file: ${remote_dir}/.env' >&2; exit 2; }
   export SECUREWAVE_IMAGE='${SECUREWAVE_PRODUCTION_IMAGE}'
   docker pull '${SECUREWAVE_PRODUCTION_IMAGE}'
   docker compose up -d --pull always
   docker compose ps"
