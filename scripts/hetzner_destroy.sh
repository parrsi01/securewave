#!/bin/bash
set -euo pipefail

if [ -z "${HETZNER_API_TOKEN:-}" ]; then
  echo "HETZNER_API_TOKEN must be set."
  exit 1
fi

if [ "${CONFIRM_DESTROY:-}" != "YES" ]; then
  echo "Refusing to destroy without CONFIRM_DESTROY=YES."
  exit 1
fi

if ! command -v terraform >/dev/null 2>&1; then
  echo "Terraform is required for teardown."
  exit 1
fi

pushd infrastructure/hetzner >/dev/null

export TF_VAR_hcloud_token="${HETZNER_API_TOKEN}"
terraform init -input=false
terraform destroy -auto-approve

popd >/dev/null

echo "Teardown complete."
