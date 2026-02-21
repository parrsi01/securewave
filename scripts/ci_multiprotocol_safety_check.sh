#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

required_scripts=(
  "scripts/provision_openvpn.sh"
  "scripts/provision_ikev2.sh"
  "scripts/rotate_openvpn_ca.sh"
  "scripts/rotate_ikev2_certs.sh"
)

for script in "${required_scripts[@]}"; do
  if [[ ! -f "${script}" ]]; then
    echo "missing_required_script:${script}" >&2
    exit 10
  fi
  bash -n "${script}"
  if ! grep -q "set -euo pipefail" "${script}"; then
    echo "missing_strict_mode:${script}" >&2
    exit 11
  fi
  if ! grep -q "/etc/securewave/secrets" "${script}"; then
    echo "missing_secret_path_guard:${script}" >&2
    exit 12
  fi
 done

# Basic secret leak guard in tracked sources.
if git ls-files | grep -E '\.(pem|key|p12|pfx)$' >/dev/null 2>&1; then
  echo "tracked_key_material_file_detected" >&2
  git ls-files | grep -E '\.(pem|key|p12|pfx)$' >&2 || true
  exit 13
fi

if git grep -n "BEGIN [A-Z ]*PRIVATE KEY" -- \
  ':!securewave_app/ios/ThirdParty/**' \
  ':!docs/reference/**' \
  ':!scripts/pre-commit-hook.sh' \
  ':!artifacts/**' >/dev/null 2>&1; then
  echo "private_key_block_detected_in_tracked_files" >&2
  git grep -n "BEGIN [A-Z ]*PRIVATE KEY" -- ':!securewave_app/ios/ThirdParty/**' ':!docs/reference/**' ':!scripts/pre-commit-hook.sh' ':!artifacts/**' >&2 || true
  exit 14
fi

if rg -n "\\bAzure\\b|\\bazure\\b|AZURE_" \
  --glob '!securewave_app/ios/ThirdParty/**' \
  --glob '!artifacts/**' \
  --glob '!docs/reference/**' \
  --glob '!scripts/ci_multiprotocol_safety_check.sh' \
  routes services scripts docs tests >/dev/null 2>&1; then
  echo "azure_reference_detected" >&2
  rg -n "\\bAzure\\b|\\bazure\\b|AZURE_" --glob '!securewave_app/ios/ThirdParty/**' --glob '!artifacts/**' --glob '!docs/reference/**' --glob '!scripts/ci_multiprotocol_safety_check.sh' routes services scripts docs tests >&2 || true
  exit 15
fi

echo "ci_multiprotocol_safety_check:ok"
