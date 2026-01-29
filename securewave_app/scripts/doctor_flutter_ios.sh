#!/bin/bash
# SecureWave iOS Environment Doctor
# Checks all prerequisites for iOS build

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
IOS_DIR="$PROJECT_ROOT/ios"

echo "🔍 SecureWave iOS Environment Doctor"
echo "===================================="
echo ""

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

ERRORS=0
WARNINGS=0

check_pass() {
  echo -e "${GREEN}✓${NC} $1"
}

check_fail() {
  echo -e "${RED}✗${NC} $1"
  ((ERRORS++))
}

check_warn() {
  echo -e "${YELLOW}⚠${NC} $1"
  ((WARNINGS++))
}

echo "1. Checking Xcode..."
if command -v xcodebuild &> /dev/null; then
  XCODE_VERSION=$(xcodebuild -version | head -n 1)
  check_pass "Xcode found: $XCODE_VERSION"
  
  # Check if command line tools are installed
  if xcode-select -p &> /dev/null; then
    XCODE_PATH=$(xcode-select -p)
    check_pass "Command Line Tools: $XCODE_PATH"
  else
    check_fail "Command Line Tools not installed. Run: xcode-select --install"
  fi
else
  check_fail "Xcode not found. Install from App Store."
fi

echo ""
echo "2. Checking Flutter..."
if command -v flutter &> /dev/null; then
  FLUTTER_VERSION=$(flutter --version | head -n 1)
  check_pass "Flutter found: $FLUTTER_VERSION"
  
  echo "   Running flutter doctor..."
  flutter doctor --verbose | grep -E "^\[.?\]" || true
else
  check_fail "Flutter not found. Install from https://flutter.dev"
fi

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

echo ""
echo "4. Checking CocoaPods..."
if command -v pod &> /dev/null; then
  POD_VERSION=$(pod --version)
  check_pass "CocoaPods found: $POD_VERSION"
  
  if [[ -f "$IOS_DIR/Podfile" ]]; then
    check_pass "Podfile exists"
    
    if [[ -f "$IOS_DIR/Podfile.lock" ]]; then
      check_pass "Podfile.lock exists"
      
      if [[ -d "$IOS_DIR/Pods" ]]; then
        check_pass "Pods directory exists"
        
        # Check if pods are up to date
        cd "$IOS_DIR"
        if pod outdated --silent &> /dev/null; then
          check_warn "Some pods may be outdated. Consider running: pod update"
        fi
      else
        check_fail "Pods not installed. Run: cd ios && pod install"
      fi
    else
      check_warn "Podfile.lock missing. Run: cd ios && pod install"
    fi
  else
    check_fail "Podfile missing"
  fi
else
  check_fail "CocoaPods not found. Install: sudo gem install cocoapods"
fi

echo ""
echo "5. Checking workspace..."
if [[ -d "$IOS_DIR/Runner.xcworkspace" ]]; then
  check_pass "Runner.xcworkspace exists"
  
  if [[ -f "$IOS_DIR/Runner.xcworkspace/contents.xcworkspacedata" ]]; then
    check_pass "Workspace is valid"
  else
    check_fail "Workspace is corrupt"
  fi
else
  check_fail "Runner.xcworkspace missing"
fi

if [[ -d "$IOS_DIR/Runner.xcodeproj" ]]; then
  check_pass "Runner.xcodeproj exists"
else
  check_fail "Runner.xcodeproj missing"
fi

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
  check_warn "PacketTunnel extension not found (required for VPN)"
fi

echo ""
echo "===================================="
echo "Summary:"
echo "  Errors: $ERRORS"
echo "  Warnings: $WARNINGS"
echo ""

if [[ $ERRORS -eq 0 ]]; then
  echo -e "${GREEN}✓ Environment is ready for iOS build${NC}"
  echo ""
  echo "Next steps:"
  echo "  1. Open: $IOS_DIR/Runner.xcworkspace"
  echo "  2. Select a development team in Signing & Capabilities"
  echo "  3. Build and run on device or simulator"
  exit 0
else
  echo -e "${RED}✗ Fix the errors above before building${NC}"
  exit 1
fi
