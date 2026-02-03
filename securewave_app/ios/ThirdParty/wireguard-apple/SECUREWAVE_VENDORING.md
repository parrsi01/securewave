# SecureWave vendoring notes (wireguard-apple)

Upstream:
- Repository: `https://github.com/WireGuard/wireguard-apple`
- Pinned snapshot: `10da5cfdef362889b438cfbeff867a74e6d717fd`

Local changes:
- `Sources/WireGuardKitC/include/WireGuardKitC.h`: add `#include <sys/types.h>` to satisfy Xcode/Clang module build requirements for BSD integer types (`u_int32_t`, `u_int16_t`, `u_char`).

Build requirements:
- Go toolchain is required to build `libwg-go.a` via `Sources/WireGuardKitGo/Makefile`.
- SecureWave build phase/script: `securewave_app/ios/scripts/build_wg_go.sh`.
