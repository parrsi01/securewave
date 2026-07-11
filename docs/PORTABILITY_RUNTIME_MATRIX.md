# SecureWave VPN Runtime Portability Matrix

Last audited: 2026-07-11 UTC

Audit basis:

- Branch: `codex/vpn-runtime-portability-refactor`
- Base: `origin/master` at `81f8a655`
- Audit host: Linux `aarch64` / Debian `arm64`
- Current local package proof: ARM64 only
- Production deploy, publication, signing, live credentials, and live infrastructure
  changes were excluded.

## Status meanings

| Status | Meaning |
| --- | --- |
| Implemented | A complete source path exists from Flutter through a native runtime boundary. |
| Package/build proven | The named architecture was built and its package metadata/payload were inspected. |
| Install/helper proven | A clean target host installed the package and proved the helper/service/socket contract. |
| Live routing proven | Route, DNS, public exit-IP, data-plane, disconnect, and cleanup evidence exists for the exact platform/architecture/protocol. |
| Blocked | Evidence cannot be produced in the current authorized environment. |
| Intentionally unavailable | The app rejects the protocol because no native implementation exists. |

## Protocol truth matrix

| OS / architecture / artifact | Protocol | Implemented | Package/build proven | Install/helper proven | Live routing proven | Current truth |
| --- | --- | --- | --- | --- | --- | --- |
| Linux ARM64 `.deb` | WireGuard | Yes: contract-10 helper, `sw-wg`, route/policy/status/counters, cleanup | Yes on this ARM64 host; app and helper are AArch64 ELF files | Blocked: no passwordless root or clean ARM64 systemd VM | Blocked: no authorized live credentials/infrastructure run | Implemented and package-proven, not release-proven |
| Linux ARM64 `.deb` | OpenVPN | Yes: allowlisted start/stop/status, config validation, root process/config pinning, counters | Yes on this ARM64 host | Blocked: same clean-install/root gate | Blocked: no authorized live proof and the deployed server authentication mode was not inspected | Implemented and package-proven; profile authentication compatibility remains unproven |
| Linux ARM64 `.deb` | IKEv2 | Helper path exists: NetworkManager/strongSwan start/status/cleanup, route/DNS, XFRM ESP, pref-220 loop rejection | Yes on this ARM64 host | Blocked: same clean-install/root gate | Blocked: the backend intentionally does not advertise Linux IKEv2; a stale pref-220 rule is also present on this host | Intentionally unavailable in the app/backend despite packaged helper code |
| Linux x64 `.deb` | WireGuard / OpenVPN / IKEv2 | Same portable source paths as ARM64 | Historical workflow run `29036573515` produced an x64 build with supplied SHA-256 `f2718810c7dea6e2c298c159f25d904321423ab3a359c1d1428b3e824d7b4d92`; it predates contract 10 and is not a current-branch runtime artifact | Blocked: clean x86_64 VM run required | Blocked: exact x64 artifact and authorized credentials required | No x64 release-readiness claim |
| Linux portable tar/zip/AppImage, ARM64 or x64 | All | UI can call an already-installed matching helper | Portable build script now strips helper/service installer payload | Not supplied by portable archive | Not proven | UI-only unless the matching `.deb` helper is separately installed and proven |
| Windows x64 | WireGuard | Yes: official WireGuard tunnel-service install/uninstall; status requires a running service | Blocked: no Windows host/build artifact in this pass | N/A to Linux helper; Windows admin/service proof is missing | Blocked: Windows route/DNS/exit-IP/data-plane proof required | Implemented, not release-proven |
| Windows x64 | OpenVPN / IKEv2 | No | No | No | No | Intentionally unavailable; native bridge rejects non-WireGuard protocols |
| Windows ARM64 | All | No certified target path | No | No | No | Blocked/unsupported until a native ARM64 build and runtime implementation are proven |
| macOS ARM64 / x64 UI demo | WireGuard / OpenVPN / IKEv2 | No Network Extension provider exists | UI demo build evidence may exist separately; it is not VPN evidence | No VPN runtime to install | No | Intentionally unavailable; `isAvailable=false`, status is disconnected, counters unavailable |
| Other Linux architectures | All | Not assessed | No | No | No | Unsupported until architecture-native build and runtime proof exists |

## Fail-closed boundaries

- The Linux app uses only `/run/securewave/helper.sock`; it has no connect-time
  `sudo`, `pkexec`, raw `wg-quick`, or `/bin/sh -c` fallback.
- `isAvailable` probes the selected Linux protocol. One installed protocol does
  not make the other protocols available. The Dart product gate additionally
  keeps Linux IKEv2 unavailable while the backend refuses Linux IKEv2 profiles.
- Helper request fields and operations are allowlisted. Malformed, duplicate,
  unknown, over-sized, unsafe-path, and contract-mismatch requests are rejected.
- WireGuard configs reject arbitrary pre/post hooks. Only the exact
  backend-generated IPv4/IPv6 kill-switch hooks are accepted.
- OpenVPN configs reject script, plugin, include, management, external
  credential-path, daemonization, and arbitrary root file-write directives.
- The current OpenVPN profile/client authentication contract is not treated as
  runtime proof. Server authentication compatibility requires an authorized
  live certification run.
- Windows accepts WireGuard only. macOS accepts no VPN protocol.
- A connected UI state is insufficient. Active certification also requires
  helper status, interface/process, route, DNS, protocol safety, counters,
  changed public exit IP, HTTPS data-plane success, disconnect, and cleanup.

## Evidence still required

- Clean ARM64 systemd VM install, service/socket ownership and mode, no-prompt
  connect/disconnect, uninstall, and cleanup.
- Clean x86_64 systemd VM certification of a contract-10 package built from the
  reviewed commit.
- Authorized per-protocol live route, DNS, exit-IP, data-plane, counter, and
  cleanup evidence.
- Windows x64 build/install/service/routing evidence.
- A signed native macOS Network Extension implementation before any macOS VPN
  claim.

No artifact status was changed and no artifact was published by this refactor.
