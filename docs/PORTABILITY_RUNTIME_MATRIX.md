# SecureWave VPN Runtime Portability Matrix

Last audited: 2026-07-13 UTC

Audit basis:

- Candidate branch: `codex/linux-runtime-final`
- Base: `origin/master` at `b2c69ade88a6d7d96a1478f792c39ec793888fac`
- Source head when the local runtime/package checks ran:
  `9243c862f08049cc583e4c94232fb44bd44f407e`
- Audit host: Linux `aarch64` / Debian `arm64`
- Local ARM64 package SHA-256:
  `6bdd66e246a5ddd6de0037266d193101291a47395857777103e954a49c73ad5b`
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
| Linux ARM64 `.deb` | WireGuard | Yes: contract-10 helper, routes/policy/status/counters, cleanup | Yes: local ARM64 package and AArch64 helper payload | Blocked: no clean ARM64 systemd VM; current host helper IPC/service/socket checks pass | Blocked: no authorized staging credentials/infrastructure | Primary path, package-proven, not live-release-proven |
| Linux ARM64 `.deb` | OpenVPN | Yes: allowlisted start/stop/status and config/process safety | Yes: local package payload and dependency metadata | Blocked: no clean ARM64 systemd VM | Blocked: no backend + data-plane evidence in authorized staging | Unavailable unless backend and data-plane gates pass |
| Linux ARM64 `.deb` | IKEv2 | Helper orchestration exists | Yes: package contains the declared strongSwan/NetworkManager dependencies | Blocked: no clean install/runtime proof | Blocked: backend and clean Linux runtime gates are not both green | Intentionally unavailable |
| Linux x64 `.deb` | WireGuard/OpenVPN/IKEv2 | Same portable source paths | Workflow `29261131617` from source head `9243c862` passed; SHA-256 `c51616246415d405a45305d923332f989c0fa71c6b01ddc99ed86f3d0ea394c9`; contract-10 payload/dependencies checked | Blocked: clean x86_64 systemd VM required | Blocked: authorized staging evidence required | Build-proven only; manifest remains `coming_soon` |
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
- IKEv2 stays unavailable while backend advertising and clean Linux runtime proof
  are incomplete.
- A connected UI state is not certification evidence. Active proof requires
  handshake/process state, routes, DNS, HTTPS, endpoint bypass, exit-IP movement,
  counters, disconnect, and residue cleanup.

## Evidence still required

- Clean ARM64 and x86_64 systemd VM install, upgrade, no-prompt helper use,
  uninstall, and cleanup.
- Authorized staging WireGuard and OpenVPN route/data-plane proof. No production
  load test or implicit production probe is permitted.
- Windows service/runtime proof and a signed macOS Network Extension before those
  platforms receive VPN release claims.
