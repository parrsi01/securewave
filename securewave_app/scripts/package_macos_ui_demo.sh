#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$ROOT_DIR/.." && pwd)"
MACOS_DIR="$ROOT_DIR/macos"
BUILD_DIR="$ROOT_DIR/build/macos/Build/Products/Release"
DOWNLOADS_DIR="$REPO_ROOT/static/downloads"

usage() {
  cat <<'EOF'
Usage: bash securewave_app/scripts/package_macos_ui_demo.sh

Builds and packages a macOS UI demo app from Runner.xcworkspace. Run this on a
Mac with Xcode, CocoaPods, and Flutter installed.

The output is a website-downloadable zip:
  static/downloads/securewave-macos-<arch>-ui-demo.zip

This is not a production macOS VPN release. The current macOS app returns
vpn_not_configured for tunnel start/stop until a signed macOS Network Extension
target is added.

Optional environment:
  MACOS_CODESIGN_IDENTITY="Developer ID Application: ..."
  MACOS_DEMO_ARCH=arm64|x64
  MACOS_DEMO_OUT=/path/to/output.zip
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "ERROR: macOS demo packaging requires macOS with Xcode." >&2
  echo "Run this script from the Mac after pulling the branch." >&2
  exit 2
fi

for tool in flutter pod xcodebuild ditto codesign python3; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "ERROR: required tool not found: $tool" >&2
    exit 2
  fi
done

HOST_ARCH="$(uname -m)"
case "${MACOS_DEMO_ARCH:-$HOST_ARCH}" in
  arm64|aarch64)
    ARCH_LABEL="arm64"
    ;;
  x86_64|x64)
    ARCH_LABEL="x64"
    ;;
  *)
    echo "ERROR: unsupported macOS demo architecture: ${MACOS_DEMO_ARCH:-$HOST_ARCH}" >&2
    exit 2
    ;;
esac

DEFAULT_OUT_FILE="$DOWNLOADS_DIR/securewave-macos-${ARCH_LABEL}-ui-demo.zip"
OUT_FILE="${MACOS_DEMO_OUT:-$DEFAULT_OUT_FILE}"

if [[ ! -f "$ROOT_DIR/.env" ]]; then
  bash "$REPO_ROOT/scripts/prepare_flutter_env.sh"
fi

cd "$ROOT_DIR"
flutter pub get

cd "$MACOS_DIR"
pod install
bash "$MACOS_DIR/scripts/ensure_workspace.sh"

cd "$ROOT_DIR"
flutter build macos --release

APP_BUNDLE="$(find "$BUILD_DIR" -maxdepth 1 -type d -name "*.app" | sort | head -n 1)"
if [[ -z "$APP_BUNDLE" || ! -d "$APP_BUNDLE" ]]; then
  echo "ERROR: macOS app bundle not found under $BUILD_DIR" >&2
  exit 1
fi

if [[ -n "${MACOS_CODESIGN_IDENTITY:-}" ]]; then
  echo "[STEP] Codesigning with configured identity"
  codesign --force --deep --options runtime --sign "$MACOS_CODESIGN_IDENTITY" "$APP_BUNDLE"
else
  echo "[STEP] Applying ad-hoc signature for local demo testing"
  codesign --force --deep --sign - "$APP_BUNDLE"
fi

mkdir -p "$(dirname "$OUT_FILE")"
rm -f "$OUT_FILE"
ditto -c -k --keepParent "$APP_BUNDLE" "$OUT_FILE"

echo "OK: macOS UI demo package created."
echo "Output: $OUT_FILE"
shasum -a 256 "$OUT_FILE"

if [[ "$OUT_FILE" == "$DEFAULT_OUT_FILE" ]]; then
  python3 "$REPO_ROOT/scripts/update_download_manifest.py"
fi
