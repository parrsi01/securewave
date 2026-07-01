#!/bin/bash
# ------------------------------------------------------------------
# SecureWave iOS Environment Doctor
# Checks all prerequisites for iOS build.
# Can run on Linux (skip Xcode checks) or macOS (full checks).
# ------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
IOS_DIR="$PROJECT_ROOT/ios"

echo "SecureWave iOS Environment Doctor"
echo "===================================="
echo ""

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

ERRORS=0
WARNINGS=0

check_pass() { echo -e "${GREEN}+${NC} $1"; }
check_fail() { echo -e "${RED}x${NC} $1"; ERRORS=$((ERRORS + 1)); }
check_warn() { echo -e "${YELLOW}!${NC} $1"; WARNINGS=$((WARNINGS + 1)); }
require_release_signing() {
  case "${SECUREWAVE_IOS_RELEASE_SIGNING:-false}" in
    1|true|TRUE|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}
check_signing_issue() {
  if require_release_signing; then
    check_fail "$1"
  else
    check_warn "$1"
  fi
}
profile_matches_bundle() {
  local profile="$1"
  local bundle_id="$2"
  local decoded
  decoded="$(security cms -D -i "$profile" 2>/dev/null || true)"
  if [[ -z "$decoded" ]]; then
    return 1
  fi
  if [[ -n "${APPLE_TEAM_ID:-}" ]]; then
    printf '%s\n' "$decoded" | grep -Fq "<string>${APPLE_TEAM_ID}.${bundle_id}</string>"
  else
    printf '%s\n' "$decoded" | grep -Fq ".${bundle_id}</string>"
  fi
}

# ---- 1. Xcode (macOS only) ----
echo "1. Checking Xcode..."
if [[ "$(uname)" == "Darwin" ]]; then
  if command -v xcodebuild &> /dev/null; then
    XCODE_VERSION=$(xcodebuild -version | head -n 1)
    check_pass "Xcode found: $XCODE_VERSION"
    if xcode-select -p &> /dev/null; then
      check_pass "Command Line Tools: $(xcode-select -p)"
    else
      check_fail "Command Line Tools not installed. Run: xcode-select --install"
    fi
  else
    check_fail "Xcode not found. Install from App Store."
  fi
else
  check_warn "Not macOS - Xcode checks skipped (OK for CI / Linux dev)"
fi

# ---- 2. Flutter ----
echo ""
echo "2. Checking Flutter..."
if command -v flutter &> /dev/null; then
  FLUTTER_VERSION=$(flutter --version 2>/dev/null | head -n 1)
  check_pass "Flutter found: $FLUTTER_VERSION"
else
  check_fail "Flutter not found. Install from https://flutter.dev"
fi

# ---- 3. Project configuration ----
echo ""
echo "3. Checking project configuration..."
if [[ -f "$IOS_DIR/Flutter/Generated.xcconfig" ]]; then
  check_pass "Generated.xcconfig exists"
else
  check_fail "Generated.xcconfig missing. Run: flutter pub get"
fi

if [[ -f "$PROJECT_ROOT/pubspec.yaml" ]]; then
  check_pass "pubspec.yaml exists"
else
  check_fail "pubspec.yaml missing"
fi

if [[ -f "$PROJECT_ROOT/.dart_tool/package_config.json" ]]; then
  check_pass "Flutter packages fetched"
else
  check_warn "Packages not fetched. Run: flutter pub get"
fi

# ---- 4. CocoaPods (macOS only) ----
echo ""
echo "4. Checking CocoaPods..."
if [[ "$(uname)" == "Darwin" ]]; then
  if command -v pod &> /dev/null; then
    POD_VERSION=$(pod --version)
    check_pass "CocoaPods found: $POD_VERSION"
    if [[ -f "$IOS_DIR/Podfile" ]]; then
      check_pass "Podfile exists"
      if [[ -d "$IOS_DIR/Pods" ]]; then
        check_pass "Pods directory exists"
      else
        check_warn "Pods not installed. Run: cd ios && pod install"
      fi
    else
      check_fail "Podfile missing"
    fi
  else
    check_fail "CocoaPods not found. Install: sudo gem install cocoapods"
  fi
else
  check_warn "Not macOS - CocoaPods checks skipped"
fi

# ---- 5. Workspace validation ----
echo ""
echo "5. Checking workspace..."
if [[ -d "$IOS_DIR/Runner.xcworkspace" ]]; then
  check_pass "Runner.xcworkspace exists"
  if [[ -f "$IOS_DIR/Runner.xcworkspace/contents.xcworkspacedata" ]]; then
    check_pass "Workspace data valid"
  else
    check_fail "Workspace is corrupt (missing contents.xcworkspacedata)"
  fi
else
  check_warn "Runner.xcworkspace missing (run pod install to create it)"
fi

if [[ -d "$IOS_DIR/Runner.xcodeproj" ]]; then
  check_pass "Runner.xcodeproj exists"
else
  check_fail "Runner.xcodeproj missing"
fi

# ---- 6. iOS targets ----
echo ""
echo "6. Checking iOS targets..."
if [[ -d "$IOS_DIR/Runner" ]]; then
  check_pass "Runner target exists"
else
  check_fail "Runner target missing"
fi

if [[ -d "$IOS_DIR/PacketTunnel" ]]; then
  check_pass "PacketTunnel extension exists"
else
  check_warn "PacketTunnel extension not found (required for VPN tunnel)"
fi

# ---- 7. Release signing assets (macOS only) ----
echo ""
echo "7. Checking release signing assets..."
if [[ "$(uname)" == "Darwin" ]]; then
  if ! command -v security &> /dev/null; then
    check_signing_issue "Apple security CLI not found"
  else
    SIGNING_IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null || true)"
    if [[ -z "$SIGNING_IDENTITIES" ]]; then
      check_signing_issue "No code signing identities found in the active keychains"
    elif printf '%s\n' "$SIGNING_IDENTITIES" | grep -Eq "Apple Distribution|iPhone Distribution"; then
      check_pass "Apple Distribution signing identity available"
    elif printf '%s\n' "$SIGNING_IDENTITIES" | grep -Eq "Apple Development|iPhone Developer"; then
      check_signing_issue "Only Apple Development signing identity found; App Store export needs Apple Distribution"
    else
      check_signing_issue "No Apple iOS signing identity found"
    fi
  fi

  if [[ -n "${APPLE_TEAM_ID:-}" ]]; then
    check_pass "APPLE_TEAM_ID is set"
  else
    check_signing_issue "APPLE_TEAM_ID is not set"
  fi

  PROFILE_DIR="$HOME/Library/MobileDevice/Provisioning Profiles"
  if [[ ! -d "$PROFILE_DIR" ]]; then
    check_signing_issue "Provisioning profile directory is missing"
  else
    for bundle_id in "com.securewave.vpn" "com.securewave.vpn.PacketTunnel"; do
      MATCHED_PROFILE=false
      while IFS= read -r -d '' profile; do
        if profile_matches_bundle "$profile" "$bundle_id"; then
          MATCHED_PROFILE=true
          break
        fi
      done < <(find "$PROFILE_DIR" -type f -name "*.mobileprovision" -print0)

      if [[ "$MATCHED_PROFILE" == "true" ]]; then
        check_pass "Provisioning profile found for $bundle_id"
      else
        check_signing_issue "No provisioning profile found for $bundle_id"
      fi
    done
  fi
else
  check_warn "Not macOS - signing identity and provisioning profile checks skipped"
fi

# ---- Summary ----
echo ""
echo "===================================="
echo "Summary: Errors=$ERRORS  Warnings=$WARNINGS"
echo ""

if [[ $ERRORS -eq 0 ]]; then
  echo -e "${GREEN}Environment is ready for iOS build${NC}"
  echo ""
  echo "IMPORTANT: Always open Runner.xcworkspace, never Runner.xcodeproj."
  echo "For release signing diagnostics, run with SECUREWAVE_IOS_RELEASE_SIGNING=1 and APPLE_TEAM_ID set."
  echo ""
  echo "Next steps:"
  echo "  1. Open: $IOS_DIR/Runner.xcworkspace"
  echo "  2. Select a development team in Signing & Capabilities"
  echo "  3. Build and run on device or simulator"
  exit 0
else
  echo -e "${RED}Fix the errors above before building${NC}"
  exit 1
fi
