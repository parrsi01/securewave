#!/usr/bin/env bash
# build_apps.sh - Build SecureWave Flutter apps for distribution.
# Usage: ./scripts/build_apps.sh [linux|android|all]
#
# Supported targets:
#   linux   - Build Linux x64 release, package as .tar.gz
#   android - Build Android APK release
#   all     - Build all available targets
#
# Windows and macOS require their native toolchains and cannot be
# cross-compiled from Linux. Those targets emit placeholder notes only.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_DIR="$PROJECT_ROOT/securewave_app"
DOWNLOADS_DIR="$PROJECT_ROOT/static/downloads"

# ---------------------------------------------------------------------------
# Preflight checks
# ---------------------------------------------------------------------------

check_flutter() {
  if ! command -v flutter &>/dev/null; then
    echo "ERROR: 'flutter' command not found on PATH."
    echo "Install Flutter: https://docs.flutter.dev/get-started/install"
    exit 1
  fi
  echo "Flutter found: $(flutter --version | head -1)"
}

usage() {
  echo "Usage: $0 [linux|android|all]"
  echo ""
  echo "Targets:"
  echo "  linux    Build Linux x64 release (.tar.gz)"
  echo "  android  Build Android release (.apk)"
  echo "  all      Build all available targets"
  echo ""
  echo "Note: Windows and macOS builds require their native toolchains."
  exit 1
}

if [[ $# -lt 1 ]]; then
  usage
fi

PLATFORM="$1"

mkdir -p "$DOWNLOADS_DIR"

# ---------------------------------------------------------------------------
# Linux build
# ---------------------------------------------------------------------------
build_linux() {
  # Detect host architecture
  HOST_ARCH="$(uname -m)"
  case "$HOST_ARCH" in
    x86_64)  ARCH_LABEL="x64";   FLUTTER_ARCH="x64" ;;
    aarch64) ARCH_LABEL="x64";   FLUTTER_ARCH="arm64" ;;
    arm64)   ARCH_LABEL="x64";   FLUTTER_ARCH="arm64" ;;
    *)       ARCH_LABEL="x64";   FLUTTER_ARCH="$HOST_ARCH" ;;
  esac

  echo ""
  echo "=========================================="
  echo " Building SecureWave for Linux ($HOST_ARCH)"
  echo "=========================================="
  echo ""

  check_flutter

  cd "$APP_DIR"
  flutter build linux --release

  # Flutter outputs to build/linux/<arch>/release/bundle
  BUNDLE_DIR="$APP_DIR/build/linux/$FLUTTER_ARCH/release/bundle"
  if [[ ! -d "$BUNDLE_DIR" ]]; then
    # Fallback: try x64 path in case Flutter uses that label
    BUNDLE_DIR="$APP_DIR/build/linux/x64/release/bundle"
  fi
  if [[ ! -d "$BUNDLE_DIR" ]]; then
    echo "ERROR: Linux build output not found."
    echo "Searched: $APP_DIR/build/linux/*/release/bundle"
    echo "Check the flutter build output above for errors."
    exit 1
  fi

  # Always name the output securewave-linux-x64.tar.gz for download URL consistency
  TARBALL="$DOWNLOADS_DIR/securewave-linux-x64.tar.gz"
  echo "==> Packaging Linux bundle as $TARBALL ..."
  tar -czf "$TARBALL" -C "$BUNDLE_DIR" .
  echo "==> Linux tarball created: $TARBALL ($(du -h "$TARBALL" | cut -f1))"

  # Copy the install script alongside the tarball
  if [[ -f "$DOWNLOADS_DIR/install-linux.sh" ]]; then
    echo "==> Linux install script already exists at $DOWNLOADS_DIR/install-linux.sh"
  else
    echo "==> NOTE: Run the project to generate install-linux.sh in static/downloads/"
  fi

  echo "==> Linux build complete."
}

# ---------------------------------------------------------------------------
# Android build
# ---------------------------------------------------------------------------
build_android() {
  echo ""
  echo "=========================================="
  echo " Building SecureWave for Android (APK)"
  echo "=========================================="
  echo ""

  check_flutter

  cd "$APP_DIR"
  flutter build apk --release

  APK_SOURCE="$APP_DIR/build/app/outputs/flutter-apk/app-release.apk"
  if [[ ! -f "$APK_SOURCE" ]]; then
    echo "ERROR: Android APK not found at $APK_SOURCE"
    echo "Check the flutter build output above for errors."
    exit 1
  fi

  APK_DEST="$DOWNLOADS_DIR/securewave-android.apk"
  cp "$APK_SOURCE" "$APK_DEST"
  echo "==> Android APK copied to: $APK_DEST ($(du -h "$APK_DEST" | cut -f1))"
  echo "==> Android build complete."
}

# ---------------------------------------------------------------------------
# Windows (placeholder - requires Windows host)
# ---------------------------------------------------------------------------
build_windows() {
  echo ""
  echo "=========================================="
  echo " Windows Build (not available)"
  echo "=========================================="
  echo ""
  echo "Windows builds require a Windows host with Visual Studio."
  echo "Cross-compilation from Linux is not supported by Flutter."
  echo ""
  echo "To build on Windows:"
  echo "  1. Install Flutter on Windows"
  echo "  2. Install Visual Studio with C++ desktop workload"
  echo "  3. Run: cd securewave_app && flutter build windows --release"
  echo "  4. Package the output from build/windows/x64/runner/Release/"
  echo "  5. Copy the .zip to static/downloads/securewave-windows-x64.zip"
  echo ""
}

# ---------------------------------------------------------------------------
# macOS (placeholder - requires macOS host with Xcode)
# ---------------------------------------------------------------------------
build_macos() {
  echo ""
  echo "=========================================="
  echo " macOS Build (not available)"
  echo "=========================================="
  echo ""
  echo "macOS builds require a macOS host with Xcode installed."
  echo "Cross-compilation from Linux is not supported by Flutter."
  echo "Apple code signing and notarization are required for distribution."
  echo ""
  echo "Creating the Mac/Xcode review handoff kit for the website..."
  bash "$PROJECT_ROOT/scripts/package_apple_review_handoff.sh"
  echo ""
  echo "To build on macOS:"
  echo "  1. Install Flutter on macOS"
  echo "  2. Install Xcode and accept the license"
  echo "  3. Run: export APPLE_TEAM_ID=<team-id>"
  echo "  4. Run: bash securewave_app/scripts/archive_ios_release.sh"
  echo "  5. Build/notarize macOS separately when the macOS Network Extension target is ready"
  echo ""
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------
case "$PLATFORM" in
  linux)
    build_linux
    ;;
  android)
    build_android
    ;;
  all)
    build_linux
    build_android
    build_windows
    build_macos
    ;;
  windows)
    build_windows
    ;;
  macos)
    build_macos
    ;;
  *)
    echo "ERROR: Unknown platform '$PLATFORM'"
    usage
    ;;
esac

echo ""
echo "=========================================="
echo " Build complete. Artifacts in:"
echo "   $DOWNLOADS_DIR/"
echo "=========================================="
ls -lh "$DOWNLOADS_DIR/" 2>/dev/null || echo "(directory empty)"
