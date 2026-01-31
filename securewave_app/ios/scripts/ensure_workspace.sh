#!/bin/bash
# ------------------------------------------------------------------
# ensure_workspace.sh
# Xcode pre-action / build-guard script.
#
# PURPOSE: Guarantee that ALL builds go through Runner.xcworkspace,
# never through Runner.xcodeproj directly. Opening the .xcodeproj
# excludes CocoaPods-managed dependencies and causes cryptic errors.
#
# WHERE IT RUNS:
#   1. As an Xcode scheme pre-action  (WORKSPACE_PATH is set by Xcode)
#   2. Manually from the command line  (detects workspace on disk)
#   3. From CI scripts                 (detects workspace on disk)
# ------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ------- 1. Check if Xcode set WORKSPACE_PATH ---------
if [[ -n "${WORKSPACE_PATH:-}" ]]; then
  if [[ "${WORKSPACE_PATH}" != *"Runner.xcworkspace"* ]]; then
    echo ""
    echo "================================================================"
    echo "ERROR: Wrong Xcode entry point detected."
    echo ""
    echo "  You opened Runner.xcodeproj instead of Runner.xcworkspace."
    echo ""
    echo "  HOW TO FIX:"
    echo "  1. Close this Xcode window."
    echo "  2. Open: $IOS_DIR/Runner.xcworkspace"
    echo "  3. Build again."
    echo "================================================================"
    echo ""
    exit 1
  fi
  echo "OK: Xcode workspace verified (Runner.xcworkspace)"
  exit 0
fi

# ------- 2. Check if PROJECT_FILE_PATH points at xcodeproj without workspace ---------
if [[ -n "${PROJECT_FILE_PATH:-}" ]] && [[ "${PROJECT_FILE_PATH}" == *"Runner.xcodeproj"* ]]; then
  echo ""
  echo "================================================================"
  echo "ERROR: Build triggered via Runner.xcodeproj."
  echo ""
  echo "  You must use Runner.xcworkspace so that CocoaPods dependencies"
  echo "  (and Flutter engine) are included in the build."
  echo ""
  echo "  HOW TO FIX:"
  echo "  1. Close Xcode."
  echo "  2. Open: $IOS_DIR/Runner.xcworkspace"
  echo "  3. Build again."
  echo "================================================================"
  echo ""
  exit 1
fi

# ------- 3. CLI / CI mode: verify workspace exists on disk ---------
if [[ ! -d "$IOS_DIR/Runner.xcworkspace" ]]; then
  echo ""
  echo "================================================================"
  echo "ERROR: Runner.xcworkspace not found at:"
  echo "  $IOS_DIR/Runner.xcworkspace"
  echo ""
  echo "  This usually means 'pod install' has not been run."
  echo ""
  echo "  HOW TO FIX:"
  echo "    cd $IOS_DIR && pod install"
  echo "================================================================"
  echo ""
  exit 1
fi

if [[ ! -f "$IOS_DIR/Runner.xcworkspace/contents.xcworkspacedata" ]]; then
  echo ""
  echo "================================================================"
  echo "ERROR: Runner.xcworkspace exists but is corrupt."
  echo ""
  echo "  HOW TO FIX:"
  echo "    rm -rf $IOS_DIR/Runner.xcworkspace"
  echo "    cd $IOS_DIR && pod install"
  echo "================================================================"
  echo ""
  exit 1
fi

echo "OK: Runner.xcworkspace verified on disk."
exit 0
