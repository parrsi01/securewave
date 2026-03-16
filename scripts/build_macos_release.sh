#!/bin/bash
# build_macos_release.sh
# Builds the SecureWaveMac standalone macOS client, exports the .app,
# computes a SHA256 checksum, and creates a zip archive.
#
# Prerequisites:
#   - Xcode command-line tools installed
#   - Valid Apple Developer signing identity in Keychain
#   - Provisioning profile with Network Extension + App Group entitlements
#
# Usage:
#   ./scripts/build_macos_release.sh [--scheme SecureWaveMac] [--config Release]
#
# Output:
#   build/macos/SecureWaveMac.app
#   build/macos/SecureWaveMac.zip
#   build/macos/SecureWaveMac.zip.sha256

set -euo pipefail

# ── Configuration ────────────────────────────────────────────────────────────

SCHEME="${1:-SecureWaveMac}"
CONFIGURATION="${2:-Release}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
XCODE_PROJECT="${PROJECT_DIR}/apple/macos/SecureWaveMac/SecureWaveMac.xcodeproj"
BUILD_DIR="${PROJECT_DIR}/build/macos"
EXPORT_OPTIONS_PLIST="${PROJECT_DIR}/apple/macos/SecureWaveMac/ExportOptions.plist"
APP_NAME="SecureWaveMac"
ARCHIVE_PATH="${BUILD_DIR}/${APP_NAME}.xcarchive"
EXPORT_PATH="${BUILD_DIR}/export"
ZIP_NAME="${APP_NAME}.zip"
CHECKSUM_FILE="${APP_NAME}.zip.sha256"

# ── Helpers ──────────────────────────────────────────────────────────────────

log()  { echo "[build_macos_release] $*"; }
die()  { echo "[build_macos_release] ERROR: $*" >&2; exit 1; }
need() { command -v "$1" &>/dev/null || die "Required tool not found: $1"; }

need xcodebuild
need shasum
need zip

# ── Pre-flight ───────────────────────────────────────────────────────────────

if [ ! -d "${XCODE_PROJECT}" ]; then
  die "Xcode project not found at: ${XCODE_PROJECT}
  Run 'xcodegen generate' or open Xcode and create the project first."
fi

mkdir -p "${BUILD_DIR}"

# ── Step 1: Archive ──────────────────────────────────────────────────────────

log "Archiving ${SCHEME} (${CONFIGURATION})…"
xcodebuild archive \
  -project "${XCODE_PROJECT}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -archivePath "${ARCHIVE_PATH}" \
  -destination "generic/platform=macOS" \
  CODE_SIGN_STYLE=Automatic \
  ONLY_ACTIVE_ARCH=NO \
  | xcpretty 2>/dev/null || true   # xcpretty is optional; raw output shown if absent.

[ -d "${ARCHIVE_PATH}" ] || die "Archive step produced no .xcarchive at: ${ARCHIVE_PATH}"
log "Archive complete: ${ARCHIVE_PATH}"

# ── Step 2: Export .app ──────────────────────────────────────────────────────

if [ -f "${EXPORT_OPTIONS_PLIST}" ]; then
  log "Exporting .app using ExportOptions.plist…"
  xcodebuild -exportArchive \
    -archivePath "${ARCHIVE_PATH}" \
    -exportOptionsPlist "${EXPORT_OPTIONS_PLIST}" \
    -exportPath "${EXPORT_PATH}"
else
  # Fallback: copy directly from archive.
  log "ExportOptions.plist not found — copying from archive directly."
  mkdir -p "${EXPORT_PATH}"
  APP_IN_ARCHIVE="$(find "${ARCHIVE_PATH}/Products" -name "*.app" -maxdepth 3 | head -1)"
  [ -n "${APP_IN_ARCHIVE}" ] || die "No .app found inside archive."
  cp -R "${APP_IN_ARCHIVE}" "${EXPORT_PATH}/"
fi

APP_PATH="$(find "${EXPORT_PATH}" -name "*.app" -maxdepth 2 | head -1)"
[ -n "${APP_PATH}" ] || die "Export produced no .app bundle."
log "Export complete: ${APP_PATH}"

# ── Step 3: Read version from bundle ─────────────────────────────────────────

VERSION="$(defaults read "${APP_PATH}/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "unknown")"
BUILD_NUM="$(defaults read "${APP_PATH}/Contents/Info" CFBundleVersion 2>/dev/null || echo "0")"
log "Version: ${VERSION} (build ${BUILD_NUM})"

# ── Step 4: Create zip archive ────────────────────────────────────────────────

cd "${BUILD_DIR}"
ZIP_OUTPUT="${BUILD_DIR}/${ZIP_NAME}"
log "Creating zip archive: ${ZIP_OUTPUT}"
zip -r --quiet "${ZIP_NAME}" "$(basename "${APP_PATH}")"
log "Archive size: $(du -sh "${ZIP_OUTPUT}" | cut -f1)"

# ── Step 5: SHA256 checksum ───────────────────────────────────────────────────

CHECKSUM="$(shasum -a 256 "${ZIP_NAME}" | awk '{print $1}')"
echo "${CHECKSUM}  ${ZIP_NAME}" > "${CHECKSUM_FILE}"
log "SHA256: ${CHECKSUM}"
log "Checksum written to: ${BUILD_DIR}/${CHECKSUM_FILE}"

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo "┌─────────────────────────────────────────────────────────┐"
echo "│  SecureWaveMac macOS Build Complete                     │"
echo "├─────────────────────────────────────────────────────────┤"
printf "│  Version:    %-43s│\n" "${VERSION} (build ${BUILD_NUM})"
printf "│  Archive:    %-43s│\n" "${ZIP_NAME}"
printf "│  SHA256:     %-43s│\n" "${CHECKSUM:0:40}…"
printf "│  Output dir: %-43s│\n" "${BUILD_DIR}"
echo "└─────────────────────────────────────────────────────────┘"
