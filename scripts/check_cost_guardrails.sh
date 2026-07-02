#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${TF_DIR:-$ROOT_DIR/infrastructure/hetzner}"
TFVARS_FILE="${1:-${TFVARS_FILE:-$TF_DIR/terraform.tfvars}}"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

read_tfvar() {
  local key="$1"
  if [[ -f "$TFVARS_FILE" ]]; then
    # Extract value from key = value
    local line
    line=$(grep -E "^\s*${key}\s*=" "$TFVARS_FILE" | tail -n 1 || true)
    if [[ -n "$line" ]]; then
      # Remove key, equals, quotes, and whitespace
      echo "$line" | sed -E "s/^\s*${key}\s*=\s*//" | sed -E "s/[\"']//g" | tr -d ' '
      return 0
    fi
  fi
  return 1
}

server_type="${TF_VAR_server_type:-}"
node_count="${TF_VAR_node_count:-}"
allow_scale="${TF_VAR_allow_scale:-}"

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
monthly_cap="${HETZNER_MONTHLY_INSTANCE_CAP:-1}"

if [[ "$server_type" != "cx23" && "$server_type" != "cx33" ]]; then
  fail "server_type '$server_type' is not allowed. Allowed: cx23 or cx33."
fi

if ! [[ "$node_count" =~ ^[0-9]+$ ]]; then
  fail "node_count '$node_count' must be numeric."
fi

if ! [[ "$monthly_cap" =~ ^[0-9]+$ ]]; then
  fail "HETZNER_MONTHLY_INSTANCE_CAP '$monthly_cap' must be numeric."
fi

if (( monthly_cap < 1 )); then
  fail "HETZNER_MONTHLY_INSTANCE_CAP must be >= 1 (got '$monthly_cap')"
fi

# Strict production guard: multi-server scaling is forbidden for this release.
if (( node_count != 1 )); then
  fail "node_count '$node_count' is not allowed. Policy: node_count must be 1."
fi

if [[ "${allow_scale,,}" == "true" ]]; then
  fail "allow_scale=true is not allowed. Policy: single-server Hetzner only."
fi

if (( node_count > monthly_cap )); then
  fail "node_count '$node_count' exceeds monthly cap '$monthly_cap'."
fi

[[ -d "$TF_DIR" ]] || fail "Terraform directory not found: $TF_DIR"

# Static checks that do not require terraform:
# - Backups must be explicit and enabled for production host recovery.
if ! grep -RIn --include="*.tf" -E 'backups[[:space:]]*=[[:space:]]*true' "$TF_DIR" >/dev/null; then
  fail "Hetzner backups must be explicitly enabled (backups=true not found under $TF_DIR)."
fi
if grep -RIn --include="*.tf" -E 'backups[[:space:]]*=[[:space:]]*false' "$TF_DIR" >/dev/null; then
  fail "Hetzner backups must remain enabled (backups=false found under $TF_DIR)."
fi

# - No unexpected paid add-ons/resources (allowlist Hetzner resources).
resource_types=$(
  grep -RhoE --include="*.tf" '^[[:space:]]*resource[[:space:]]+"(hcloud_[^"]+)"' "$TF_DIR" \
    | sed -E 's/.*"(hcloud_[^"]+)".*/\1/' \
    | sort -u
)
while IFS= read -r rtype; do
  [[ -z "$rtype" ]] && continue
  case "$rtype" in
    hcloud_server|hcloud_firewall)
      ;;
    *)
      fail "Unexpected Hetzner resource type '$rtype' detected under $TF_DIR (policy: no add-ons)."
      ;;
  esac
done <<<"$resource_types"

echo "Cost guardrails OK: tf_dir=$TF_DIR server_type=$server_type node_count=$node_count monthly_cap=$monthly_cap"
