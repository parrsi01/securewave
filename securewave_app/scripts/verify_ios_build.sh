#!/bin/bash
# ------------------------------------------------------------------
# verify_ios_build.sh
# Pre-flight check before any iOS build (CI or local).
# Validates: Generated.xcconfig, Pods, workspace, and entry point.
# ------------------------------------------------------------------
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IOS_DIR="${ROOT_DIR}/ios"
ERRORS=0

echo "SecureWave iOS pre-flight check"
echo "================================"

# 1. Generated.xcconfig must exist (proves flutter pub get ran)
if [[ ! -f "${IOS_DIR}/Flutter/Generated.xcconfig" ]]; then
  echo "FAIL: Missing ios/Flutter/Generated.xcconfig"
  echo "  Fix: cd ${ROOT_DIR} && flutter pub get"
  ERRORS=$((ERRORS + 1))
else
  echo "OK:   Generated.xcconfig"
fi

# 2. Pods directory must exist (proves pod install ran)
if [[ ! -d "${IOS_DIR}/Pods" ]]; then
  echo "FAIL: Missing ios/Pods directory"
  echo "  Fix: cd ${IOS_DIR} && pod install"
  ERRORS=$((ERRORS + 1))
else
  echo "OK:   Pods directory"
fi

# 3. Runner.xcworkspace must exist
if [[ ! -d "${IOS_DIR}/Runner.xcworkspace" ]]; then
  echo "FAIL: Missing Runner.xcworkspace"
  echo "  Fix: cd ${IOS_DIR} && pod install"
  ERRORS=$((ERRORS + 1))
else
  echo "OK:   Runner.xcworkspace"
fi

# 4. Guard against direct xcodeproj usage (Xcode env vars)
if [[ -n "${PROJECT_FILE_PATH:-}" ]] && [[ "${PROJECT_FILE_PATH}" == *"Runner.xcodeproj"* ]] && [[ -z "${WORKSPACE_PATH:-}" ]]; then
  echo "FAIL: Build is using Runner.xcodeproj instead of Runner.xcworkspace"
  echo "  Fix: Close Xcode, open Runner.xcworkspace, then build."
  ERRORS=$((ERRORS + 1))
fi

# 5. Guard: if WORKSPACE_PATH is set, it must point at Runner.xcworkspace
if [[ -n "${WORKSPACE_PATH:-}" ]] && [[ "${WORKSPACE_PATH}" != *"Runner.xcworkspace"* ]]; then
  echo "FAIL: WORKSPACE_PATH does not reference Runner.xcworkspace"
  echo "  Current: ${WORKSPACE_PATH}"
  echo "  Fix: Open Runner.xcworkspace instead."
  ERRORS=$((ERRORS + 1))
fi

echo "================================"
if [[ $ERRORS -gt 0 ]]; then
  echo "FAILED: $ERRORS issue(s) found. Fix them before building."
  exit 1
fi

echo "All checks passed."
