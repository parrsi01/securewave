#!/usr/bin/env bash
set -euo pipefail

# Deploys a prebuilt SecureWave container on an already hardened production host.
# This script intentionally refuses to infer hosts, users, images, or confirmation.

export LC_ALL=C

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_TEMPLATE="${SECUREWAVE_COMPOSE_TEMPLATE:-$ROOT_DIR/deploy/hetzner/compose.yaml}"

mark_missing() {
  echo "$1" >&2
  missing=1
}

is_valid_ipv4_literal() {
  local value="$1"
  local IFS=.
  local -a octets=()
  local octet

  [[ "$value" =~ ^[0-9]+(\.[0-9]+){3}$ ]] || return 1
  read -r -a octets <<< "$value"
  [[ "${#octets[@]}" -eq 4 ]] || return 1
  for octet in "${octets[@]}"; do
    [[ "$octet" =~ ^[0-9]{1,3}$ ]] || return 1
    (( 10#$octet <= 255 )) || return 1
  done
}

is_usable_ipv4_literal() {
  local value="$1"
  local IFS=.
  local -a octets=()
  local first

  is_valid_ipv4_literal "$value" || return 1
  read -r -a octets <<< "$value"
  first=$((10#${octets[0]}))
  (( first > 0 && first != 127 && first < 224 )) || return 1
}

is_usable_ipv6_literal() {
  local value="$1"

  command -v python3 >/dev/null 2>&1 || return 1
  python3 - "$value" >/dev/null 2>&1 <<'PY'
import ipaddress
import sys

try:
    address = ipaddress.IPv6Address(sys.argv[1])
except ValueError:
    raise SystemExit(1)

mapped = address.ipv4_mapped
if address.is_loopback or address.is_unspecified or address.is_multicast:
    raise SystemExit(1)
if mapped is not None and (
    mapped.is_loopback or mapped.is_unspecified or mapped.is_multicast
):
    raise SystemExit(1)
PY
}

is_valid_hostname() {
  local host="$1"
  local hostname_pattern='^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*$'

  (( ${#host} <= 253 )) || return 1
  [[ "$host" =~ $hostname_pattern ]]
}

validate_production_host() {
  local host="$1"
  local lower_host="${host,,}"

  if [[ -z "$host" ]]; then
    mark_missing "SECUREWAVE_PRODUCTION_HOST must not be empty."
    return
  fi
  if [[ "$lower_host" == localhost || "$lower_host" == localhost.* || "$lower_host" == localhost6 || "$lower_host" == localhost6.* || "$lower_host" == ip6-localhost || "$lower_host" == ip6-loopback ]]; then
    mark_missing "SECUREWAVE_PRODUCTION_HOST must not be localhost."
    return
  fi
  if [[ "$host" == *:* ]]; then
    if ! is_usable_ipv6_literal "$host"; then
      mark_missing "SECUREWAVE_PRODUCTION_HOST must be a valid non-loopback host or IP."
    fi
    return
  fi
  if [[ "$host" =~ ^[0-9]+(\.[0-9]+){3}$ ]]; then
    if ! is_usable_ipv4_literal "$host"; then
      mark_missing "SECUREWAVE_PRODUCTION_HOST must be a valid non-loopback host or IP."
    fi
    return
  fi
  if [[ "$lower_host" == 127 || "$lower_host" == 127.* || "$lower_host" == 0 || "$lower_host" == 0.* ]]; then
    mark_missing "SECUREWAVE_PRODUCTION_HOST must not be a loopback or wildcard address."
    return
  fi
  if ! is_valid_hostname "$host"; then
    mark_missing "SECUREWAVE_PRODUCTION_HOST contains an invalid host reference."
  fi
}

is_valid_registry_host() {
  local registry="$1"
  local registry_host="$registry"
  local registry_port=""

  if [[ "$registry" == *:* ]]; then
    [[ "$registry" != *:*:* ]] || return 1
    registry_host="${registry%:*}"
    registry_port="${registry##*:}"
    [[ "$registry_port" =~ ^[0-9]{1,5}$ ]] || return 1
    (( 10#$registry_port >= 1 && 10#$registry_port <= 65535 )) || return 1
  fi

  [[ "$registry_host" == *.* ]] || return 1
  if [[ "$registry_host" =~ ^[0-9]+(\.[0-9]+){3}$ ]]; then
    is_usable_ipv4_literal "$registry_host"
    return
  fi
  is_valid_hostname "$registry_host"
}

validate_image_ref() {
  local image="$1"
  local registry ref repo_path
  local repo_pattern='^[a-z0-9]+([._-][a-z0-9]+)*(\/[a-z0-9]+([._-][a-z0-9]+)*)*$'

  if [[ -z "$image" || ! "$image" =~ ^[A-Za-z0-9._:@/-]+$ ]]; then
    mark_missing "SECUREWAVE_PRODUCTION_IMAGE contains an invalid image reference."
    return
  fi

  registry="${image%%/*}"
  ref="${image#*/}"
  if [[ "$registry" == "$image" || -z "$ref" ]] || ! is_valid_registry_host "$registry"; then
    mark_missing "SECUREWAVE_PRODUCTION_IMAGE must use a fully qualified registry hostname and repository path."
    return
  fi

  if [[ "$ref" =~ ^(.+)@sha256:([0-9A-Fa-f]{64})$ ]]; then
    repo_path="${BASH_REMATCH[1]}"
  elif [[ "$ref" =~ ^(.+):([0-9A-Fa-f]{40})$ ]]; then
    repo_path="${BASH_REMATCH[1]}"
  else
    mark_missing "SECUREWAVE_PRODUCTION_IMAGE must end in a 64-hex @sha256 digest or 40-hex commit tag."
    return
  fi

  if [[ ! "$repo_path" =~ $repo_pattern ]]; then
    mark_missing "SECUREWAVE_PRODUCTION_IMAGE has a malformed repository path."
  fi
}

validate_remote_user() {
  local user="$1"
  local user_pattern='^[a-z_][a-z0-9_-]{0,31}$'

  if [[ ! "$user" =~ $user_pattern ]]; then
    mark_missing "SECUREWAVE_PRODUCTION_USER must be a safe Unix username."
  fi
}

validate_remote_dir() {
  local directory="$1"
  local directory_pattern='^/[A-Za-z0-9_-][A-Za-z0-9._-]*(/[A-Za-z0-9_-][A-Za-z0-9._-]*)*$'

  if [[ ! "$directory" =~ $directory_pattern ]] || [[ "$directory" == */./* || "$directory" == */../* || "$directory" == */. || "$directory" == */.. ]]; then
    mark_missing "SECUREWAVE_REMOTE_APP_DIR must be a safe absolute deployment path."
  fi
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

remote_user="${SECUREWAVE_PRODUCTION_USER-securewave}"
remote_dir="${SECUREWAVE_REMOTE_APP_DIR-/opt/securewave}"
validate_remote_user "$remote_user"
validate_remote_dir "$remote_dir"

if [[ "$missing" -ne 0 ]]; then
  exit 2
fi

remote="${remote_user}@${SECUREWAVE_PRODUCTION_HOST}"
scp_remote="$remote"
if [[ "$SECUREWAVE_PRODUCTION_HOST" == *:* ]]; then
  scp_remote="${remote_user}@[${SECUREWAVE_PRODUCTION_HOST}]"
fi

ssh_opts=(
  -o BatchMode=yes
  -o StrictHostKeyChecking=accept-new
)

echo "Deploying ${SECUREWAVE_PRODUCTION_IMAGE} to ${remote}:${remote_dir}"

# shellcheck disable=SC2016 # Remote positional parameters must expand remotely.
readonly REMOTE_MKDIR_SCRIPT='
set -euo pipefail
remote_dir="$1"
mkdir -p -- "$remote_dir"
'

# shellcheck disable=SC2016 # Remote positional parameters must expand remotely.
readonly REMOTE_DEPLOY_SCRIPT='
set -euo pipefail
remote_dir="$1"
image="$2"
cd -- "$remote_dir"
if ! test -s .env; then
  echo "Missing production env file: ${remote_dir}/.env" >&2
  exit 2
fi
export SECUREWAVE_IMAGE="$image"
docker pull "$image"
docker compose --env-file .env config --quiet
docker compose --env-file .env up -d --pull always
docker compose ps
'

ssh "${ssh_opts[@]}" "$remote" /bin/bash -s -- "$remote_dir" <<<"$REMOTE_MKDIR_SCRIPT"
scp "${ssh_opts[@]}" "$COMPOSE_TEMPLATE" "$scp_remote:${remote_dir}/compose.yaml"
ssh "${ssh_opts[@]}" "$remote" /bin/bash -s -- "$remote_dir" "$SECUREWAVE_PRODUCTION_IMAGE" <<<"$REMOTE_DEPLOY_SCRIPT"
