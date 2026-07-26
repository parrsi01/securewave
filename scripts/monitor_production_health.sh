#!/usr/bin/env bash
set -euo pipefail

health_base="${SECUREWAVE_HEALTH_BASE_URL:-http://127.0.0.1:8080}"
timeout_seconds="${SECUREWAVE_HEALTH_TIMEOUT_SECONDS:-8}"

case "$health_base" in
  http://127.0.0.1:*|http://localhost:*) ;;
  *)
    echo "ERROR: SECUREWAVE_HEALTH_BASE_URL must use local HTTP loopback." >&2
    exit 2
    ;;
esac

if [[ ! "$timeout_seconds" =~ ^[1-9][0-9]?$ ]]; then
  echo "ERROR: SECUREWAVE_HEALTH_TIMEOUT_SECONDS must be between 1 and 99." >&2
  exit 2
fi

probe_dir="$(mktemp -d)"
cleanup() {
  rm -rf -- "$probe_dir"
}
trap cleanup EXIT

probe_json() {
  local endpoint="$1"
  local output="$2"
  curl \
    --fail \
    --silent \
    --show-error \
    --max-time "$timeout_seconds" \
    "${health_base}${endpoint}" \
    >"$output"
  python3 -m json.tool "$output" >/dev/null
}

probe_json "/api/health" "$probe_dir/health.json"
probe_json "/api/ready" "$probe_dir/ready.json"
probe_json "/downloads/manifest.json" "$probe_dir/manifest.json"

python3 - "$probe_dir/manifest.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    payload = json.load(handle)

downloads = payload.get("downloads")
if not isinstance(downloads, list):
    raise SystemExit("download manifest does not contain a downloads list")

linux_arm64 = [
    item
    for item in downloads
    if item.get("platform") == "linux"
    and item.get("architecture") == "arm64"
    and item.get("filename") == "securewave-linux-arm64.deb"
]
if len(linux_arm64) != 1:
    raise SystemExit("download manifest must contain one Linux ARM64 beta")

entry = linux_arm64[0]
if entry.get("status") != "available":
    raise SystemExit("Linux ARM64 beta is not available")
if entry.get("url") != "/downloads/securewave-linux-arm64.deb":
    raise SystemExit("Linux ARM64 beta does not use the guarded download URL")

checksum = str(entry.get("checksum_sha256") or "")
if len(checksum) != 64 or any(char not in "0123456789abcdef" for char in checksum):
    raise SystemExit("Linux ARM64 beta checksum is missing or malformed")
PY

echo "SecureWave production health probe passed."
