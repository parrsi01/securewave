#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

MODE="${1:-all}"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

log() {
  echo "[guardrails] $*"
}

require_file() {
  local path="$1"
  [[ -f "$path" ]] || fail "Required file missing: $path"
}

check_https_tls() {
  log "HTTPS/TLS config checks"
  local prod_conf="infra/nginx/securewave_prod.conf"
  local preview_conf="nginx/securewave_preview.conf"

  require_file "$prod_conf"
  require_file "$preview_conf"

  grep -Eq 'return 301 https://\$host\$request_uri;' "$prod_conf" \
    || fail "HTTP->HTTPS redirect missing in $prod_conf"
  grep -Eq 'listen 443 ssl( http2)?;' "$prod_conf" \
    || fail "TLS listener missing in $prod_conf"
  grep -Eq '^\s*ssl_protocols\s+TLSv1\.2\s+TLSv1\.3;' "$prod_conf" \
    || fail "TLS baseline must be exactly TLSv1.2/TLSv1.3 in $prod_conf"
  grep -Eq 'Strict-Transport-Security' "$prod_conf" \
    || fail "HSTS header missing in $prod_conf"

  if grep -Eq 'TLSv1(\s|;)|TLSv1\.1' "$prod_conf"; then
    fail "Legacy TLS version (<1.2) detected in $prod_conf"
  fi

  grep -Eq 'listen 443 ssl( http2)?;' "$preview_conf" \
    || fail "TLS listener missing in $preview_conf"
  grep -Eq '^\s*ssl_protocols\s+TLSv1\.2\s+TLSv1\.3;' "$preview_conf" \
    || fail "TLS baseline must be exactly TLSv1.2/TLSv1.3 in $preview_conf"
}

check_no_mock_demo() {
  log "No mock/demo VPN artifact checks"

  # Ban old fake/demo tunnel flags and fake success phrases in tracked code.
  local -a grep_args=(
    -n -i -E
    '\bDEMO_MODE\b|\bWG_MOCK_MODE\b|\bWG_SIMULATE\b|MockVpnService|mock[_ -]?tunnel|simulate[_ -]?connect|fake success'
    --
    .github/workflows
    routes
    services
    models
    securewave_app/lib
    securewave_app/linux
    securewave_app/windows
    securewave_app/macos
    tests
    scripts
    ':!sandbox/live_validation_multi_protocol/run_validation.py'
    ':!scripts/ci_multiprotocol_release_guardrails.sh'
    ':!scripts/ci_multiprotocol_safety_check.sh'
    ':!dev_tools/**'
  )

  if git grep "${grep_args[@]}" >/tmp/securewave_mock_hits.txt 2>/dev/null; then
    cat /tmp/securewave_mock_hits.txt >&2 || true
    fail "Mock/demo VPN patterns detected in tracked files"
  fi

  # Ban demo-labeled VPN tests/workflows from reappearing.
  if git ls-files | grep -E '/test_demo_vpn\.py$' >/tmp/securewave_demo_test_hits.txt 2>/dev/null; then
    cat /tmp/securewave_demo_test_hits.txt >&2 || true
    fail "Demo-labeled VPN test file detected"
  fi

  if git grep -n -i -E 'demo vpn|demo connect' -- .github/workflows tests/integration tests/e2e \
    >/tmp/securewave_demo_wording_hits.txt 2>/dev/null; then
    cat /tmp/securewave_demo_wording_hits.txt >&2 || true
    fail "Demo-labeled VPN wording detected in workflows/integration/e2e tests"
  fi
}

check_manifest_versioning() {
  log "Release manifest versioning checks"
  require_file "VERSION"
  require_file "static/downloads/version.json"

  python3 - <<'PY'
import json
import pathlib
import re
import sys

root = pathlib.Path(".")
version_text = root.joinpath("VERSION").read_text(encoding="utf-8").strip()
if not version_text:
    raise SystemExit("VERSION file is empty")

tag = version_text.replace("+", "-")
release_manifest = root / "artifacts" / "releases" / version_text / "version.json"
published_manifest = root / "static" / "downloads" / "version.json"
if not release_manifest.exists():
    raise SystemExit(f"Missing release manifest: {release_manifest}")

rel = json.loads(release_manifest.read_text(encoding="utf-8"))
pub = json.loads(published_manifest.read_text(encoding="utf-8"))

for name, payload in (("release", rel), ("published", pub)):
    if payload.get("version") != version_text:
        raise SystemExit(f"{name}_manifest_version_mismatch")
    if payload.get("provider", "").lower() != "hetzner":
        raise SystemExit(f"{name}_manifest_provider_not_hetzner")
    for ts_key in ("build_date", "generated_at"):
        value = str(payload.get(ts_key, ""))
        if not re.match(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$", value):
            raise SystemExit(f"{name}_manifest_invalid_{ts_key}")
    artifacts = payload.get("artifacts")
    if not isinstance(artifacts, list) or not artifacts:
        raise SystemExit(f"{name}_manifest_missing_artifacts")
    for i, item in enumerate(artifacts):
        if not isinstance(item, dict):
            raise SystemExit(f"{name}_manifest_artifact_not_object:{i}")
        if item.get("version") != version_text:
            raise SystemExit(f"{name}_manifest_artifact_version_mismatch:{i}")
        status = str(item.get("status", "")).lower()
        filename = item.get("filename")
        if status == "available":
            if not isinstance(filename, str) or not filename:
                raise SystemExit(f"{name}_manifest_available_missing_filename:{i}")
            if tag not in filename:
                raise SystemExit(f"{name}_manifest_filename_missing_version_tag:{filename}")

if rel != pub:
    raise SystemExit("published_manifest_differs_from_release_manifest")
PY
}

check_artifact_checksums() {
  log "Artifact checksum checks"
  require_file "VERSION"
  python3 - <<'PY'
import hashlib
import json
import pathlib

root = pathlib.Path(".")
version_text = root.joinpath("VERSION").read_text(encoding="utf-8").strip()
release_dir = root / "artifacts" / "releases" / version_text
manifest_path = release_dir / "version.json"
checksums_path = release_dir / "checksums.txt"
published_manifest_path = root / "static" / "downloads" / "version.json"

for p in (manifest_path, checksums_path, published_manifest_path):
    if not p.exists():
        raise SystemExit(f"missing_required_artifact:{p}")

manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
published = json.loads(published_manifest_path.read_text(encoding="utf-8"))
if manifest != published:
    raise SystemExit("release_vs_published_manifest_mismatch")

checksum_map = {}
for raw_line in checksums_path.read_text(encoding="utf-8").splitlines():
    line = raw_line.strip()
    if not line:
        continue
    parts = line.split()
    if len(parts) != 2:
        raise SystemExit(f"invalid_checksums_line:{raw_line}")
    checksum_map[parts[1]] = parts[0]

downloads_dir = root / "static" / "downloads"
for item in manifest.get("artifacts", []):
    if not isinstance(item, dict):
        raise SystemExit("artifact_not_object")
    if str(item.get("status", "")).lower() != "available":
        continue
    filename = item.get("filename")
    expected_sha = str(item.get("sha256") or "")
    expected_size = item.get("size_bytes")
    if not filename or not expected_sha:
        raise SystemExit(f"available_artifact_missing_metadata:{filename}")
    if checksum_map.get(filename) != expected_sha:
        raise SystemExit(f"checksums_txt_mismatch:{filename}")
    release_file = release_dir / filename
    published_file = downloads_dir / filename
    for p in (release_file, published_file):
        if not p.exists():
            raise SystemExit(f"missing_artifact_file:{p}")
        h = hashlib.sha256(p.read_bytes()).hexdigest()
        if h != expected_sha:
            raise SystemExit(f"sha256_mismatch:{p}")
        if expected_size is not None and p.stat().st_size != int(expected_size):
            raise SystemExit(f"size_mismatch:{p}")
PY
}

check_hetzner_cost_guardrails() {
  log "Hetzner cost guardrail checks"
  require_file "scripts/check_cost_guardrails.sh"
  require_file "scripts/release_hetzner.sh"

  bash -n scripts/check_cost_guardrails.sh
  bash -n scripts/release_hetzner.sh

  # Validate static policy gates remain in the release wrapper.
  grep -q "HETZNER_MONTHLY_INSTANCE_CAP" scripts/release_hetzner.sh \
    || fail "Missing HETZNER_MONTHLY_INSTANCE_CAP enforcement in scripts/release_hetzner.sh"
  grep -q "node_count != 1" scripts/release_hetzner.sh \
    || fail "Missing single-node policy check in scripts/release_hetzner.sh"
  grep -q "allow_scale=true is not allowed" scripts/release_hetzner.sh \
    || fail "Missing allow_scale guard in scripts/release_hetzner.sh"
  grep -q 'bash "\$ROOT_DIR/scripts/check_cost_guardrails.sh"' scripts/release_hetzner.sh \
    || fail "release_hetzner.sh must call scripts/check_cost_guardrails.sh"

  # Run cost guard script with safe defaults (no terraform/network calls required).
  HETZNER_MONTHLY_INSTANCE_CAP="${HETZNER_MONTHLY_INSTANCE_CAP:-1}" \
  bash scripts/check_cost_guardrails.sh >/tmp/securewave_cost_guardrails.out
}

run_lint_bundle() {
  check_https_tls
  check_no_mock_demo
  check_manifest_versioning
  check_hetzner_cost_guardrails
}

case "$MODE" in
  all)
    run_lint_bundle
    check_artifact_checksums
    ;;
  lint)
    run_lint_bundle
    ;;
  tls)
    check_https_tls
    ;;
  mock)
    check_no_mock_demo
    ;;
  manifest)
    check_manifest_versioning
    ;;
  artifact)
    check_manifest_versioning
    check_artifact_checksums
    ;;
  cost)
    check_hetzner_cost_guardrails
    ;;
  *)
    fail "Unknown mode '$MODE' (expected: all|lint|tls|mock|manifest|artifact|cost)"
    ;;
esac

log "OK (${MODE})"
