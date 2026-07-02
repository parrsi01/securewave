#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT_DIR/static/downloads"
OUT_FILE="$OUT_DIR/securewave-apple-release-handoff.zip"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$OUT_DIR" "$TMP_DIR/securewave-apple-release-handoff"

copy_file() {
  local source="$1"
  local destination="$2"
  mkdir -p "$(dirname "$TMP_DIR/securewave-apple-release-handoff/$destination")"
  cp "$ROOT_DIR/$source" "$TMP_DIR/securewave-apple-release-handoff/$destination"
}

copy_file "docs/APPLE_REVIEW_HANDOFF.md" "README.md"
copy_file "docs/APP_STORE_REVIEW_NOTES.md" "docs/APP_STORE_REVIEW_NOTES.md"
copy_file "docs/APPLE_RELEASE.md" "docs/APPLE_RELEASE.md"
copy_file "docs/DEVOPS_REPORT_APPLE_SIGNING_READINESS_2026-07-02.md" "docs/DEVOPS_REPORT_APPLE_SIGNING_READINESS_2026-07-02.md"
copy_file "securewave_app/IOS_VPN_SETUP.md" "securewave_app/IOS_VPN_SETUP.md"
copy_file "securewave_app/MACOS_VPN_SETUP.md" "securewave_app/MACOS_VPN_SETUP.md"
copy_file "securewave_app/scripts/doctor_flutter_ios.sh" "securewave_app/scripts/doctor_flutter_ios.sh"
copy_file "securewave_app/scripts/archive_ios_release.sh" "securewave_app/scripts/archive_ios_release.sh"
copy_file "securewave_app/scripts/package_macos_ui_demo.sh" "securewave_app/scripts/package_macos_ui_demo.sh"
copy_file "securewave_app/ios/Runner/Runner.entitlements" "securewave_app/ios/Runner/Runner.entitlements"
copy_file "securewave_app/ios/PacketTunnel/PacketTunnel.entitlements" "securewave_app/ios/PacketTunnel/PacketTunnel.entitlements"
copy_file "static/downloads/manifest.json" "static/downloads/manifest.json"

if command -v zip >/dev/null 2>&1; then
  (cd "$TMP_DIR" && zip -qr "$OUT_FILE" securewave-apple-release-handoff)
else
  python3 - "$TMP_DIR" "$OUT_FILE" <<'PY'
from pathlib import Path
import sys
import zipfile

root = Path(sys.argv[1])
out = Path(sys.argv[2])
with zipfile.ZipFile(out, "w", compression=zipfile.ZIP_DEFLATED) as archive:
    for path in sorted(root.rglob("*")):
        if path.is_file():
            archive.write(path, path.relative_to(root))
PY
fi

echo "OK: wrote $OUT_FILE"
