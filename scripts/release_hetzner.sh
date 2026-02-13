#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${TF_DIR:-$ROOT_DIR/infra/hetzner}"
TFVARS_FILE="${TFVARS_FILE:-$TF_DIR/terraform.tfvars}"
FORCE=false
ACTION=""

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

usage() {
  cat <<EOF
Usage: $0 [--force] [plan|apply|destroy]

Options:
  --force   Skip interactive confirmation prompts.

Environment:
  HETZNER_API_TOKEN (required)
  HETZNER_MONTHLY_INSTANCE_CAP (default: 1)
EOF
}

read_tfvar() {
  local key="$1"
  if [[ -f "$TFVARS_FILE" ]]; then
    local line
    line=$(grep -E "^\s*${key}\s*=" "$TFVARS_FILE" | tail -n 1 || true)
    if [[ -n "$line" ]]; then
      echo "$line" | sed -E "s/^\s*${key}\s*=\s*//" | sed -E "s/[\"']//g" | tr -d ' '
      return 0
    fi
  fi
  return 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force)
      FORCE=true
      shift
      ;;
    plan|apply|destroy)
      ACTION="$1"
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

ACTION="${ACTION:-plan}"

[[ -d "$TF_DIR" ]] || fail "Terraform directory not found: $TF_DIR"
command -v terraform >/dev/null 2>&1 || fail "terraform is required"
[[ -n "${HETZNER_API_TOKEN:-}" ]] || fail "HETZNER_API_TOKEN must be set"

server_type="${TF_VAR_server_type:-}"
node_count="${TF_VAR_node_count:-}"
allow_scale="${TF_VAR_allow_scale:-}"
monthly_cap="${HETZNER_MONTHLY_INSTANCE_CAP:-1}"

if [[ -z "$server_type" ]]; then
  server_type=$(read_tfvar "server_type" || true)
fi
if [[ -z "$node_count" ]]; then
  node_count=$(read_tfvar "node_count" || true)
fi
if [[ -z "$allow_scale" ]]; then
  allow_scale=$(read_tfvar "allow_scale" || true)
fi

server_type="${server_type:-cx33}"
node_count="${node_count:-1}"
allow_scale="${allow_scale:-false}"

if [[ "$server_type" != "cx23" && "$server_type" != "cx33" ]]; then
  fail "server_type '$server_type' is not allowed. Allowed: cx23 or cx33"
fi

[[ "$node_count" =~ ^[0-9]+$ ]] || fail "node_count must be numeric (got '$node_count')"
[[ "$monthly_cap" =~ ^[0-9]+$ ]] || fail "HETZNER_MONTHLY_INSTANCE_CAP must be numeric (got '$monthly_cap')"

# Hard cost guardrails: single server only.
if (( node_count != 1 )); then
  fail "node_count '$node_count' is not allowed. Policy: node_count must be 1"
fi
if [[ "${allow_scale,,}" == "true" ]]; then
  fail "allow_scale=true is not allowed. Policy: single-server Hetzner only"
fi
if (( monthly_cap < 1 )); then
  fail "HETZNER_MONTHLY_INSTANCE_CAP must be >= 1 (got '$monthly_cap')"
fi
if (( node_count > monthly_cap )); then
  fail "node_count '$node_count' exceeds monthly cap '$monthly_cap'"
fi

confirm_if_needed() {
  local action="$1"
  if [[ "$FORCE" == "true" ]]; then
    return 0
  fi

  if [[ ! -t 0 ]]; then
    fail "Non-interactive execution requires --force for '$action'"
  fi

  echo "About to run '$action' on Hetzner infra (server_type=$server_type node_count=$node_count)."
  read -r -p "Type YES to continue: " reply
  [[ "$reply" == "YES" ]] || fail "Aborted by operator"
}

export TF_VAR_hcloud_token="$HETZNER_API_TOKEN"

bash "$ROOT_DIR/scripts/check_cost_guardrails.sh" "$TFVARS_FILE"
bash "$TF_DIR/check_guardrails.sh"
terraform -chdir="$TF_DIR" init -input=false

case "$ACTION" in
  plan)
    terraform -chdir="$TF_DIR" plan -out=tfplan
    ;;
  apply)
    confirm_if_needed "apply"
    terraform -chdir="$TF_DIR" plan -out=tfplan
    terraform -chdir="$TF_DIR" apply -auto-approve tfplan
    if [[ "${SYNC_VPN_SERVERS:-true}" == "true" ]]; then
      python "$ROOT_DIR/infrastructure/hetzner/sync_vpn_servers.py" \
        --terraform-dir "$TF_DIR" \
        --wg-port "${WG_PORT:-51820}" \
        ${WG_SYNC_EXTRA_ARGS:-}
    fi
    ;;
  destroy)
    [[ "${ALLOW_DESTROY:-false}" == "true" ]] || fail "Refusing destroy without ALLOW_DESTROY=true"
    [[ "${CONFIRM_DESTROY:-}" == "YES" ]] || fail "Refusing destroy without CONFIRM_DESTROY=YES"
    confirm_if_needed "destroy"
    terraform -chdir="$TF_DIR" destroy -auto-approve
    ;;
  *)
    fail "Unknown action: $ACTION (expected plan|apply|destroy)"
    ;;
esac

echo "Hetzner release action completed: $ACTION"
