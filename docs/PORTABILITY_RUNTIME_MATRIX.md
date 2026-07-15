# SecureWave VPN Runtime Portability Matrix

Last audited: 2026-07-15 UTC

Audit basis:

- Candidate branch: `codex/linux-runtime-final`
- Base incorporated: `origin/master` at
  `56d3126116120176152e98ab213d0fa1b19e1fdc`
- Source: current PR #48 candidate; use the final PR head for remote evidence.
- Audit host: Linux `aarch64` / Debian `arm64`
- Local ARM64 package checksum: record it with the exact retained build in the
  private PR evidence; never reuse a checksum from an earlier local rebuild.
- Publication, signing, production deployment, and live credentials were
  excluded.

## Status meanings

| Status | Meaning |
| --- | --- |
| Implemented | A complete source path exists to a native runtime boundary. |
| Package/build proven | The named architecture was built and its package metadata/payload inspected. |
| Install/helper proven | A clean target host installed the package and proved the helper/service/socket contract. |
| Live routing proven | Route, DNS, HTTPS, exit-IP, data-plane, disconnect, and cleanup evidence exists for the exact target. |
| Blocked | Evidence requires an environment or authorization not available in this run. |
| Intentionally unavailable | Product gates reject the protocol until its required evidence exists. |

## Protocol truth matrix

| Target | Protocol | Implemented | Package/build proven | Install/helper proven | Live routing proven | Current truth |
| --- | --- | --- | --- | --- | --- | --- |
| Linux ARM64 `.deb` | WireGuard | Yes: contract-13 helper, routes/policy/status/counters, cleanup | Yes: local ARM64 package and AArch64 helper payload | Yes: fresh Ubuntu 24.04 ARM64 systemd container passed install, helper/socket/IPC, verifier, launch, upgrade, purge, and residue checks | Blocked: no authorized staging credentials/infrastructure | Primary path, package-proven, not live-release-proven |
| Linux ARM64 `.deb` | OpenVPN | Yes: allowlisted start/stop/status and config/process safety | Yes: local package payload and dependency metadata | Yes: dependency, helper probe, malformed/unauthorized IPC rejection, verifier, upgrade, purge, and residue checks passed | Blocked: no backend + data-plane evidence in authorized staging | Unavailable unless backend and data-plane gates pass |
| Linux ARM64 `.deb` | IKEv2 | Yes: allowlisted NetworkManager/strongSwan orchestration and safe table-210 routing | Yes: required NetworkManager/strongSwan plugins are declared and installed without a standalone charon daemon | Yes: clean package lifecycle passed; isolated lab additionally passed EAP, ESP/XFRM, rekey, failed auth, reconnect, and cleanup | Blocked: no authenticated backend plus authorized external exit-IP proof | Intentionally unavailable |
| Linux x64 `.deb` | WireGuard/OpenVPN/IKEv2 | Same portable source paths | Exact-head build/architecture/checksum evidence belongs to the private workflow and PR review; earlier-run checksums are never reused | Exact-head ephemeral lifecycle result belongs to the private workflow and PR review | Blocked: authorized staging evidence required | Manifest remains `coming_soon`; no public artifact claim |
| Linux portable archive | All | UI can call an already-installed matching helper | Archive build may be proven independently | Not supplied by the archive | Not proven | UI-only until a matching helper package is installed and certified |
| Windows x64 | WireGuard | Source bridge exists | No Windows artifact in this pass | No Windows service proof in this pass | No Windows route/DNS/data-plane proof | Implemented, not release-proven |
| Windows x64 | OpenVPN/IKEv2 | No | No | No | No | Intentionally unavailable |
| macOS ARM64/x64 demo | All VPN protocols | No Network Extension provider | UI demo is not VPN evidence | No VPN runtime to install | No | Intentionally unavailable |
| Other architectures | All | Not assessed | No | No | No | Unsupported until native build and runtime proof exist |

## Fail-closed boundaries

- Linux connect uses only `/run/securewave/helper.sock`; there is no connect-time
  `sudo`, `pkexec`, raw `wg-quick`, or shell fallback.
- A local helper capability probe never enables a protocol by itself. Backend
  server evidence and, for OpenVPN, data-plane evidence are also required.
- IKEv2 stays unavailable while backend advertising and authorized external
  data-plane proof are incomplete, even though the isolated local lab is green.
- A connected UI state is not certification evidence. Active proof requires
  handshake/process state, routes, DNS, HTTPS, endpoint bypass, exit-IP movement,
  counters, disconnect, and residue cleanup.

## Evidence still required

- Passing exact-head x86_64 package, helper, lifecycle, and cleanup workflow
  evidence in the private PR review record.
- Authorized staging WireGuard, OpenVPN, and IKEv2 route/data-plane proof. No
  production load test or implicit production probe is permitted.
- Windows service/runtime proof and a signed macOS Network Extension before those
  platforms receive VPN release claims.
