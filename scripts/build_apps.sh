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
    x86_64)        ARCH_LABEL="x64";   FLUTTER_ARCH="x64" ;;
    aarch64|arm64) ARCH_LABEL="arm64"; FLUTTER_ARCH="arm64" ;;
    *)
      echo "ERROR: Unsupported Linux architecture: $HOST_ARCH" >&2
      exit 1
      ;;
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

  APP_BINARY="$BUNDLE_DIR/securewave_app"
  if [[ ! -f "$APP_BINARY" ]]; then
    echo "ERROR: Linux application binary not found at $APP_BINARY." >&2
    exit 1
  fi
  case "$ARCH_LABEL" in
    x64) expected_elf='ELF 64-bit.*x86-64' ;;
    arm64) expected_elf='ELF 64-bit.*(ARM aarch64|aarch64)' ;;
  esac
  if ! file "$APP_BINARY" | grep -Eq "$expected_elf"; then
    echo "ERROR: Built Linux binary does not match requested $ARCH_LABEL architecture." >&2
    file "$APP_BINARY" >&2
    exit 1
  fi

  # Portable archives intentionally exclude the privileged helper payload.
  # Full no-prompt VPN routing is installed only by the architecture-matched
  # .deb, which owns the root helper, systemd unit, allowlist, and socket.
  PACKAGE_STAGING="$APP_DIR/build/packaging/portable-linux-$ARCH_LABEL"
  rm -rf "$PACKAGE_STAGING"
  mkdir -p "$PACKAGE_STAGING"
  cp -a "$BUNDLE_DIR/." "$PACKAGE_STAGING/"
  rm -rf "$PACKAGE_STAGING/packaging/linux" "$PACKAGE_STAGING/scripts/install_linux_helper.sh"

  TARBALL="$DOWNLOADS_DIR/securewave-linux-$ARCH_LABEL.tar.gz"
  echo "==> Packaging SecureWave portable Linux package (UI-only) as $TARBALL ..."
  tar -czf "$TARBALL" -C "$PACKAGE_STAGING" .
  echo "==> Linux tarball created: $TARBALL ($(du -h "$TARBALL" | cut -f1))"

  # Copy the install script alongside the tarball
  if [[ -f "$DOWNLOADS_DIR/install-linux.sh" ]]; then
    echo "==> Linux install script already exists at $DOWNLOADS_DIR/install-linux.sh"
  else
    echo "==> NOTE: Run the project to generate install-linux.sh in static/downloads/"
  fi

  echo "==> Linux portable UI build complete."
  echo "==> Full-device VPN routing requires the root-owned SecureWave helper service."
  echo "==> Install the matching SecureWave .deb package for full no-prompt VPN connect/disconnect."
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
  echo " macOS Build"
  echo "=========================================="
  echo ""

  if [[ "$(uname -s)" == "Darwin" ]]; then
    echo "Building the macOS UI demo package for the website..."
    bash "$APP_DIR/scripts/package_macos_ui_demo.sh"
  else
    echo "macOS app builds require a macOS host with Xcode installed."
    echo "Cross-compilation from Linux is not supported by Flutter."
    echo ""
    echo "Creating the Mac/Xcode review handoff kit for the website..."
    bash "$PROJECT_ROOT/scripts/package_apple_review_handoff.sh"
    echo ""
    echo "To build the website-downloadable macOS UI demo on a Mac:"
    echo "  bash securewave_app/scripts/package_macos_ui_demo.sh"
    echo ""
    echo "To build the signed iOS archive/export on a Mac:"
    echo "  export APPLE_TEAM_ID=<team-id>"
    echo "  bash securewave_app/scripts/archive_ios_release.sh"
    echo ""
    echo "The macOS demo app is UI/account-only and returns vpn_not_configured"
    echo "until a signed macOS Network Extension target is added."
  fi
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
