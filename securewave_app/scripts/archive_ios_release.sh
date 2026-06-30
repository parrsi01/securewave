#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$ROOT_DIR/.." && pwd)"
IOS_DIR="$ROOT_DIR/ios"
WORKSPACE="$IOS_DIR/Runner.xcworkspace"
SCHEME="${IOS_SCHEME:-Runner}"
CONFIGURATION="${IOS_CONFIGURATION:-Release}"
ARCHIVE_PATH="${IOS_ARCHIVE_PATH:-$ROOT_DIR/build/ios/archive/SecureWave.xcarchive}"
EXPORT_DIR="${IOS_EXPORT_DIR:-$ROOT_DIR/build/ios/export}"
EXPORT_METHOD="${IOS_EXPORT_METHOD:-app-store}"
TEAM_ID="${APPLE_TEAM_ID:-}"
SIGNING_STYLE_RAW="${IOS_SIGNING_STYLE:-automatic}"
SIGNING_STYLE="$(printf '%s' "$SIGNING_STYLE_RAW" | tr '[:upper:]' '[:lower:]')"
UPLOAD_SYMBOLS="${IOS_UPLOAD_SYMBOLS:-true}"

usage() {
  cat <<'EOF'
Usage: bash securewave_app/scripts/archive_ios_release.sh

Creates a signed iOS archive/export from Runner.xcworkspace. Run this on macOS
with Xcode, CocoaPods, Go, and Apple signing assets installed.

Required environment:
  APPLE_TEAM_ID=<Apple Developer Team ID>

Optional environment:
  IOS_ARCHIVE_PATH=securewave_app/build/ios/archive/SecureWave.xcarchive
  IOS_EXPORT_DIR=securewave_app/build/ios/export
  IOS_EXPORT_METHOD=app-store
  IOS_SIGNING_STYLE=automatic
  IOS_UPLOAD_SYMBOLS=true
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "ERROR: iOS archive/export requires macOS with Xcode." >&2
  echo "Run this script from the Mac after pulling the branch." >&2
  exit 2
fi

if [[ -z "$TEAM_ID" ]]; then
  echo "ERROR: APPLE_TEAM_ID is required." >&2
  exit 2
fi

case "$SIGNING_STYLE" in
  automatic)
    XCODE_SIGNING_STYLE="Automatic"
    EXPORT_SIGNING_STYLE="automatic"
    ;;
  manual)
    XCODE_SIGNING_STYLE="Manual"
    EXPORT_SIGNING_STYLE="manual"
    ;;
  *)
    echo "ERROR: IOS_SIGNING_STYLE must be automatic or manual." >&2
    exit 2
    ;;
esac

case "$UPLOAD_SYMBOLS" in
  true|false)
    ;;
  *)
    echo "ERROR: IOS_UPLOAD_SYMBOLS must be true or false." >&2
    exit 2
    ;;
esac

for tool in flutter pod xcodebuild go; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "ERROR: required tool not found: $tool" >&2
    exit 2
  fi
done

if [[ ! -d "$WORKSPACE" ]]; then
  echo "ERROR: missing workspace: $WORKSPACE" >&2
  echo "Run: cd $IOS_DIR && pod install" >&2
  exit 2
fi

cd "$ROOT_DIR"
flutter pub get

cd "$IOS_DIR"
pod install
bash "$IOS_DIR/scripts/ensure_workspace.sh"

cd "$REPO_ROOT"
bash scripts/verify_ios_store_compliance.sh
bash securewave_app/scripts/verify_ios_build.sh

mkdir -p "$(dirname "$ARCHIVE_PATH")" "$EXPORT_DIR"

echo "[STEP] xcodebuild archive"
xcodebuild archive \
  -workspace "$WORKSPACE" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "generic/platform=iOS" \
  -archivePath "$ARCHIVE_PATH" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE="$XCODE_SIGNING_STYLE" \
  clean archive

EXPORT_OPTIONS="$(mktemp "${TMPDIR:-/tmp}/securewave-export-options.XXXXXX.plist")"
cat >"$EXPORT_OPTIONS" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>$EXPORT_METHOD</string>
  <key>teamID</key>
  <string>$TEAM_ID</string>
  <key>signingStyle</key>
  <string>$EXPORT_SIGNING_STYLE</string>
  <key>stripSwiftSymbols</key>
  <true/>
  <key>uploadSymbols</key>
  <$UPLOAD_SYMBOLS/>
</dict>
</plist>
EOF

echo "[STEP] xcodebuild exportArchive"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_OPTIONS"

rm -f "$EXPORT_OPTIONS"

echo "OK: iOS archive/export complete."
echo "Archive: $ARCHIVE_PATH"
echo "Export:  $EXPORT_DIR"
