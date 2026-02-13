#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

required_files=(main.tf variables.tf versions.tf)
for tf_file in "${required_files[@]}"; do
  if [[ ! -f "$ROOT_DIR/$tf_file" ]]; then
    echo "ERROR: Infra misconfigured. Missing $tf_file in $ROOT_DIR" >&2
    exit 1
  fi
done

if ! command -v terraform >/dev/null 2>&1; then
  echo "WARNING: terraform not found; skipping terraform fmt/init/validate checks." >&2
  echo "Guardrails PARTIAL OK: static infra file checks passed."
  exit 0
fi

terraform -chdir="$ROOT_DIR" fmt -check -diff
terraform -chdir="$ROOT_DIR" init -backend=false -input=false >/dev/null
terraform -chdir="$ROOT_DIR" validate

echo "Guardrails OK: Terraform format + validation passed."
