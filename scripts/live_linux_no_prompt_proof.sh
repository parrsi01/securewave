#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="${SECUREWAVE_ROOT:-$(pwd)}"
cd "$ROOT_DIR"

RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-live"
PROOF_DIR="artifacts/linux-no-prompt-vpn-proof/$RUN_ID"
mkdir -p "$PROOF_DIR"
printf '%s\n' "$PROOF_DIR" > artifacts/linux-no-prompt-vpn-proof/latest-live.txt

PYTHON_BIN="${SECUREWAVE_PYTHON:-}"
if [[ -z "$PYTHON_BIN" ]]; then
  if [[ -x ".venv/bin/python" ]]; then
    PYTHON_BIN=".venv/bin/python"
  elif [[ -x "venv/bin/python" ]]; then
    PYTHON_BIN="venv/bin/python"
  else
    PYTHON_BIN="python3"
  fi
fi

log() { printf '\n[%s] %s\n' "$(date -u +%H:%M:%S)" "$*"; }

run_capture() {
  local name="$1"
  shift
  log "Running: $name"
  set +e
  "$@" > "$PROOF_DIR/$name.log" 2>&1
  local status=$?
  set -e
  printf '%s\n' "$status" > "$PROOF_DIR/$name.exit"
  return "$status"
}

must_pass() {
  local name="$1"
  shift
  if ! run_capture "$name" "$@"; then
    echo "FAIL: $name" >&2
    tail -n 160 "$PROOF_DIR/$name.log" >&2 || true
    exit 1
  fi
}

soft_run() {
  local name="$1"
  shift
  run_capture "$name" "$@" || true
}

require_file() {
  [[ -f "$1" ]] || {
    echo "Missing required file: $1" >&2
    exit 1
  }
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

require_cmd sudo
require_cmd dpkg
require_cmd dpkg-deb
require_cmd curl
require_cmd flutter
require_cmd docker
require_cmd pytest
require_file securewave_app/scripts/build_deb.sh
require_file scripts/linux_app_vpn_tunnel_proof.py
require_file scripts/linux_vpn_runtime_verifier.py

{
  echo "timestamp_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "branch=$(git branch --show-current)"
  echo "head_before=$(git rev-parse HEAD)"
  echo "python_bin=$PYTHON_BIN"
} > "$PROOF_DIR/proof_context.txt"

log "Requesting sudo once for package installation"
sudo -v

log "Building fresh .deb and download manifest"
must_pass build_deb bash -lc 'cd securewave_app && bash scripts/build_deb.sh'

ARCH="$(dpkg --print-architecture)"
case "$ARCH" in
  amd64) DOWNLOAD_ARCH="x64" ;;
  arm64) DOWNLOAD_ARCH="arm64" ;;
  *) DOWNLOAD_ARCH="$ARCH" ;;
esac

DEB="static/downloads/securewave-linux-${DOWNLOAD_ARCH}.deb"
require_file "$DEB"

must_pass deb_control dpkg-deb -I "$DEB"
must_pass deb_contents dpkg-deb -c "$DEB"
must_pass deb_helper_payload bash -lc "rg -n 'securewave-helper|securewave-wg-quick|tmpfiles|contract|wireguard-tools|openvpn|strongswan|acl|systemd' '$PROOF_DIR/deb_control.log' '$PROOF_DIR/deb_contents.log'"

log "Installing .deb with normal package manager behavior"
must_pass deb_install sudo apt install -y "$PWD/$DEB"

log "Ensuring helper service is enabled and running"
must_pass helper_service_restart sudo systemctl restart securewave-helper.service
must_pass helper_service_status systemctl status securewave-helper.service --no-pager

log "Verifying installed helper files"
must_pass installed_helper_status bash -lc '
set -euo pipefail
test -x /usr/local/libexec/securewave-helperd
test -x /usr/local/libexec/securewave-wg-quick
test -f /usr/local/libexec/securewave-wg-quick.contract
contract="$(tr -d "[:space:]" < /usr/local/libexec/securewave-wg-quick.contract)"
[[ "$contract" =~ ^[0-9]+$ ]]
(( contract >= 9 ))
systemctl is-active --quiet securewave-helper.service
test -S /run/securewave/helper.sock
'

log "Running static/runtime verification before live connect"
must_pass linux_runtime_verifier_pre "$PYTHON_BIN" scripts/linux_vpn_runtime_verifier.py --json

log "Verifying downloads truth and Linux recommendation"
must_pass checksums_verify bash -lc 'cd static/downloads && sha256sum -c checksums.txt'
must_pass manifest_file_truth "$PYTHON_BIN" - <<'PY'
import json
from pathlib import Path

manifest = json.loads(Path("static/downloads/manifest.json").read_text())
errors = []
for item in manifest.get("downloads", []):
    filename = item.get("filename")
    if not filename:
        continue
    exists = (Path("static/downloads") / filename).is_file()
    available = item.get("status") == "available"
    if exists != available:
        errors.append(f"{filename}: exists={exists} status={item.get('status')}")
    if available and not item.get("sha256"):
        errors.append(f"{filename}: missing sha256")
    if filename.endswith((".tar.gz", ".zip", ".AppImage")) and item.get("supports_full_routing"):
        errors.append(f"{filename}: portable artifact claims full routing")
if errors:
    raise SystemExit("\n".join(errors))
print("manifest_file_truth=ok")
PY

export DOWNLOAD_ARCH
must_pass downloads_api_linux_recommendation "$PYTHON_BIN" - <<'PY'
import json
import os
from fastapi import FastAPI
from fastapi.testclient import TestClient
from routes import downloads

download_arch = os.environ["DOWNLOAD_ARCH"]
app = FastAPI()
app.include_router(downloads.router)
client = TestClient(app)
ua_arch = "aarch64" if download_arch == "arm64" else "x86_64"
response = client.get(
    "/api/downloads/detect",
    headers={"User-Agent": f"Mozilla/5.0 (X11; Linux {ua_arch})"},
)
payload = response.json()
print(json.dumps({"status_code": response.status_code, "payload": payload}, indent=2))
assert response.status_code == 200
assert payload["recommended_download"] == f"/downloads/securewave-linux-{download_arch}.deb"
PY

log "Validating backend/container/deploy gates"
must_pass docker_compose_config bash -lc '
tmp_env="$(mktemp)"
printf "DUMMY=1\n" > "$tmp_env"
SECUREWAVE_ENV_FILE="$tmp_env" POSTGRES_PASSWORD=proof SECUREWAVE_IMAGE=securewave:proof docker compose -f deploy/hetzner/compose.yaml config --quiet
rm -f "$tmp_env"
'
must_pass shell_syntax bash -n scripts/deploy_production.sh deploy/hetzner/compose.yaml static/downloads/install-linux.sh scripts/build_apps.sh securewave_app/scripts/build_deb.sh securewave_app/scripts/install_linux_helper.sh
soft_run deploy_refuse_latest bash -lc 'SECUREWAVE_PRODUCTION_HOST=prod.securewave.example SECUREWAVE_PRODUCTION_IMAGE=securewave:latest CONFIRM_DEPLOY=securewave-production bash scripts/deploy_production.sh'

log "Running Flutter and backend tests"
must_pass dart_format bash -lc 'cd securewave_app && dart format lib/app.dart'
must_pass flutter_analyze bash -lc 'cd securewave_app && flutter analyze'
must_pass flutter_test bash -lc 'cd securewave_app && flutter test'
must_pass pytest_all pytest tests -q

log "Launching app briefly"
set +e
APP_BIN="$(find securewave_app/build/linux -path '*/release/bundle/securewave_app' -type f -executable -print -quit)"
if [[ -z "$APP_BIN" ]]; then
  echo "No release app binary found" > "$PROOF_DIR/app_launch.log"
  app_status=1
elif command -v xvfb-run >/dev/null 2>&1; then
  xvfb-run -a timeout 15s "$APP_BIN" > "$PROOF_DIR/app_launch.log" 2>&1
  app_status=$?
else
  timeout 15s "$APP_BIN" > "$PROOF_DIR/app_launch.log" 2>&1
  app_status=$?
fi
set -e
printf '%s\n' "$app_status" > "$PROOF_DIR/app_launch.exit"
if [[ "$app_status" != "0" && "$app_status" != "124" ]]; then
  echo "FAIL: app launch" >&2
  tail -n 120 "$PROOF_DIR/app_launch.log" >&2 || true
  exit 1
fi

log "Invalidating sudo timestamp before connect proof"
sudo -k || true
soft_run sudo_after_k sudo -n true

if [[ -z "${DEMO_EMAIL:-}${SECUREWAVE_TEST_EMAIL:-}${SECUREWAVE_RUNTIME_PROBE_EMAIL:-}" \
   && -z "${SECUREWAVE_CERT_AUTH_FILE:-}" \
   && ! -f securewave_private/live_certification_account.env ]]; then
  echo "Missing live credentials." >&2
  echo "Set DEMO_EMAIL/DEMO_PASSWORD or create securewave_private/live_certification_account.env." >&2
  exit 2
fi

log "Running mandatory live WireGuard proof without connect-time sudo"
must_pass live_wireguard_proof timeout 10m "$PYTHON_BIN" scripts/linux_app_vpn_tunnel_proof.py \
  --protocol wireguard \
  --hold-seconds "${SECUREWAVE_PROOF_HOLD_SECONDS:-20}" \
  --evidence-timeout "${SECUREWAVE_PROOF_EVIDENCE_TIMEOUT:-120}" \
  --json

log "Verifying cleanup after WireGuard proof"
must_pass linux_runtime_verifier_after_wireguard "$PYTHON_BIN" scripts/linux_vpn_runtime_verifier.py --json

log "OpenVPN proof remains blocked until authenticated current-source evidence exists"

log "Capturing IKEv2 proof if available"
if [[ "${SECUREWAVE_REQUIRE_IKEV2_PROOF:-0}" == "1" ]]; then
  must_pass live_ikev2_proof timeout 10m "$PYTHON_BIN" scripts/linux_app_vpn_tunnel_proof.py \
    --protocol ikev2 \
    --hold-seconds "${SECUREWAVE_PROOF_HOLD_SECONDS:-20}" \
    --evidence-timeout "${SECUREWAVE_PROOF_EVIDENCE_TIMEOUT:-120}" \
    --json
else
  soft_run live_ikev2_proof timeout 10m "$PYTHON_BIN" scripts/linux_app_vpn_tunnel_proof.py \
    --protocol ikev2 \
    --hold-seconds "${SECUREWAVE_PROOF_HOLD_SECONDS:-20}" \
    --evidence-timeout "${SECUREWAVE_PROOF_EVIDENCE_TIMEOUT:-120}" \
    --json
fi

log "Writing final summary"
{
  echo "# SecureWave Live Provisioning Proof"
  echo
  echo "Proof dir: $PROOF_DIR"
  echo "Branch: $(git branch --show-current)"
  echo "HEAD: $(git rev-parse HEAD)"
  echo
  echo "Exit codes:"
  for f in "$PROOF_DIR"/*.exit; do
    printf -- "- %s: %s\n" "$(basename "$f" .exit)" "$(tr -d '\n' < "$f")"
  done | sort
} > "$PROOF_DIR/proof_summary.md"

cat "$PROOF_DIR/proof_summary.md"
echo
echo "DONE: live provisioning/proof finished."
echo "Proof logs: $PROOF_DIR"
