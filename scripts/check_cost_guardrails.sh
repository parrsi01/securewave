#!/bin/bash
set -euo pipefail

TFVARS_FILE="${1:-infrastructure/hetzner/terraform.tfvars}"

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

if [[ "$server_type" != "cx33" ]]; then
  echo "ERROR: server_type '$server_type' is not allowed. Allowed: cx33 only."
  exit 1
fi

if [[ "$node_count" != "1" && "$allow_scale" != "true" ]]; then
  echo "ERROR: node_count '$node_count' requires allow_scale=true."
  exit 1
fi

echo "Cost guardrails OK: server_type=$server_type, node_count=$node_count, allow_scale=$allow_scale"
