#!/bin/bash
# SecureWave iOS Clean Build Script
# Performs a clean rebuild with all prerequisites

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
IOS_DIR="$PROJECT_ROOT/ios"

echo "🧹 SecureWave iOS Clean Build"
echo "============================="
echo ""

# Run doctor first
echo "Step 1: Running environment checks..."
if ! "$SCRIPT_DIR/doctor_flutter_ios.sh"; then
  echo "❌ Environment check failed. Fix issues before proceeding."
  exit 1
fi

echo ""
echo "Step 2: Cleaning Flutter build..."
cd "$PROJECT_ROOT"
flutter clean
echo "✓ Flutter cleaned"

echo ""
echo "Step 3: Getting Flutter packages..."
flutter pub get
echo "✓ Packages fetched"

echo ""
echo "Step 4: Cleaning iOS build..."
cd "$IOS_DIR"
rm -rf build/
rm -rf Pods/
rm -f Podfile.lock
echo "✓ iOS build artifacts cleaned"

echo ""
echo "Step 5: Installing CocoaPods..."
pod install --repo-update
echo "✓ Pods installed"

echo ""
echo "Step 6: Building iOS app (no-codesign for CI)..."
cd "$PROJECT_ROOT"
if [[ "${CI:-false}" == "true" ]]; then
  echo "CI mode detected - building without code signing"
  flutter build ios --no-codesign --debug
else
  echo "Building for device (requires signing)"
  flutter build ios --debug
fi
echo "✓ Build completed"

echo ""
echo "============================="
echo "✅ Clean build successful!"
echo ""
echo "Next steps:"
echo "  • Open: $IOS_DIR/Runner.xcworkspace"
echo "  • Run on simulator: flutter run -d ios"
echo "  • Run on device: flutter run -d <device-id>"
