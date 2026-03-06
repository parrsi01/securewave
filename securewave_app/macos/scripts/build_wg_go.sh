#!/bin/bash
set -euo pipefail

MACOS_DIR="${PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
WG_APPLE_DIR="${MACOS_DIR}/../ios/ThirdParty/wireguard-apple"
WG_GO_DIR="${WG_APPLE_DIR}/Sources/WireGuardKitGo"
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
