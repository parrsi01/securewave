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
else
  echo "Building libwg-go.a into: ${DESTDIR}"
  make -C "${WG_GO_DIR}" build DESTDIR="${DESTDIR}"
fi

if [[ ! -f "${DESTDIR}/libwg-go.a" ]]; then
  echo "ERROR: WireGuardKitGo build did not produce libwg-go.a at:"
  echo "  ${DESTDIR}/libwg-go.a"
  exit 1
fi

if [[ "${PLATFORM_NAME:-}" == "iphonesimulator" ]] && /usr/bin/nm -u "${DESTDIR}/libwg-go.a" 2>/dev/null | grep -Eq "_darwin_arm_init_(mach_exception_handler|thread_exception_port)"; then
  ARCH="${CURRENT_ARCH:-}"
  if [[ -z "${ARCH}" || "${ARCH}" == "undefined_arch" ]]; then
    ARCH="$(echo "${ARCHS:-arm64}" | awk '{print $1}')"
  fi

  STUB_C="${DESTDIR}/wg_go_simulator_cgo_stubs.c"
  STUB_O="${DESTDIR}/wg_go_simulator_cgo_stubs_${ARCH}.o"

  cat > "${STUB_C}" <<'EOF'
#include <TargetConditionals.h>

#if TARGET_OS_SIMULATOR
void darwin_arm_init_mach_exception_handler(void) {}
void darwin_arm_init_thread_exception_port(void) {}
#endif
EOF

  xcrun --sdk iphonesimulator clang \
    -target "${ARCH}-apple-ios${IPHONEOS_DEPLOYMENT_TARGET:-14.0}-simulator" \
    -c "${STUB_C}" \
    -o "${STUB_O}"

  if /usr/bin/lipo -info "${DESTDIR}/libwg-go.a" 2>/dev/null | grep -q "Architectures in the fat file"; then
    THIN_LIB="${DESTDIR}/libwg-go-${ARCH}.a"
    THIN_OBJECTS_DIR="$(mktemp -d "${DESTDIR}/wg-go-thin-objects.XXXXXX")"
    /usr/bin/lipo "${DESTDIR}/libwg-go.a" -thin "${ARCH}" -output "${THIN_LIB}"
    (cd "${THIN_OBJECTS_DIR}" && /usr/bin/ar -x "${THIN_LIB}")
    /usr/bin/libtool -static -o "${THIN_LIB}" "${THIN_OBJECTS_DIR}"/*.o "${STUB_O}"
    cp "${THIN_LIB}" "${DESTDIR}/libwg-go.a"
    rm -rf "${THIN_OBJECTS_DIR}"
  else
    THIN_OBJECTS_DIR="$(mktemp -d "${DESTDIR}/wg-go-thin-objects.XXXXXX")"
    (cd "${THIN_OBJECTS_DIR}" && /usr/bin/ar -x "${DESTDIR}/libwg-go.a")
    /usr/bin/libtool -static -o "${DESTDIR}/libwg-go.a" "${THIN_OBJECTS_DIR}"/*.o "${STUB_O}"
    rm -rf "${THIN_OBJECTS_DIR}"
  fi
  echo "OK: Added simulator-only cgo stubs to libwg-go.a"
fi

echo "OK: Built ${DESTDIR}/libwg-go.a"
