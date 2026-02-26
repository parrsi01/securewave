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

# Release manifest sanity checks (if a release has been published to static/downloads).
manifest_path="static/downloads/version.json"
if [[ -f "${manifest_path}" ]]; then
  python3 - "${manifest_path}" <<'PY'
import json
import pathlib
import sys

manifest_path = pathlib.Path(sys.argv[1])
downloads_dir = manifest_path.parent

payload = json.loads(manifest_path.read_text(encoding="utf-8"))
if payload.get("provider", "").lower() != "hetzner":
    raise SystemExit("release_manifest_provider_not_hetzner")

artifacts = payload.get("artifacts")
if not isinstance(artifacts, list):
    raise SystemExit("release_manifest_missing_artifacts")

for idx, artifact in enumerate(artifacts):
    if not isinstance(artifact, dict):
        raise SystemExit(f"release_manifest_artifact_not_object:{idx}")

    status = str(artifact.get("status", "unavailable")).lower()
    url = artifact.get("url")
    filename = artifact.get("filename")

    if status == "available" and isinstance(url, str) and url.startswith("/downloads/"):
        if not filename:
            raise SystemExit(f"release_manifest_missing_filename:{idx}")
        local_file = downloads_dir / filename
        if not local_file.exists():
            raise SystemExit(f"release_manifest_missing_local_file:{filename}")
        if not artifact.get("sha256"):
            raise SystemExit(f"release_manifest_missing_sha256:{filename}")
PY
fi

# Download folder should never contain key material or inline private keys.
if find static/downloads -type f \( -name '*.pem' -o -name '*.key' -o -name '*.p12' -o -name '*.pfx' \) | grep -q .; then
  echo "download_artifact_key_material_detected" >&2
  find static/downloads -type f \( -name '*.pem' -o -name '*.key' -o -name '*.p12' -o -name '*.pfx' \) >&2 || true
  exit 16
fi

if rg -n "BEGIN [A-Z ]*PRIVATE KEY" static/downloads >/dev/null 2>&1; then
  echo "download_artifact_private_key_block_detected" >&2
  rg -n "BEGIN [A-Z ]*PRIVATE KEY" static/downloads >&2 || true
  exit 17
fi

echo "ci_multiprotocol_safety_check:ok"
