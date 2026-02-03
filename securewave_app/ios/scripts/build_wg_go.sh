#!/bin/bash
# Build WireGuard's Go backend static library (libwg-go.a) for the current Xcode build.
#
# This is required by WireGuardKitGo's module.modulemap:
#   link "wg-go"
#
# Expected output location (Xcode-provided):
#   $CONFIGURATION_BUILD_DIR/libwg-go.a
set -euo pipefail

IOS_DIR="${PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
WG_GO_DIR="${IOS_DIR}/ThirdParty/wireguard-apple/Sources/WireGuardKitGo"
WG_GO_MOD="${WG_GO_DIR}/go.mod"

if [[ ! -d "${WG_GO_DIR}" ]]; then
  echo "ERROR: WireGuardKitGo sources not found:"
  echo "  ${WG_GO_DIR}"
  exit 1
fi

if [[ ! -f "${WG_GO_MOD}" ]]; then
  echo "ERROR: Missing WireGuardKitGo go.mod:"
  echo "  ${WG_GO_MOD}"
  exit 1
fi

if ! command -v go >/dev/null 2>&1; then
  echo "ERROR: 'go' is required to build libwg-go.a for WireGuardKitGo."
  echo ""
  echo "FIX:"
  echo "  brew install go"
  exit 1
fi

DESTDIR="${CONFIGURATION_BUILD_DIR:-${WG_GO_DIR}/out}"

if [[ -f "${DESTDIR}/libwg-go.a" ]]; then
  echo "OK: libwg-go.a already present: ${DESTDIR}/libwg-go.a"
  exit 0
fi

echo "Building libwg-go.a into: ${DESTDIR}"
make -C "${WG_GO_DIR}" build DESTDIR="${DESTDIR}"

if [[ ! -f "${DESTDIR}/libwg-go.a" ]]; then
  echo "ERROR: WireGuardKitGo build did not produce libwg-go.a at:"
  echo "  ${DESTDIR}/libwg-go.a"
  exit 1
fi

echo "OK: Built ${DESTDIR}/libwg-go.a"
