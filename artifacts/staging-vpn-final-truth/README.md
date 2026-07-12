# Staging VPN final protocol truth

## Scope and result

**Branch:** `codex/update-vpn-protocol-truth`

**Base:** `b2c69ade` (`origin/master` at branch creation)

**Date:** 2026-07-12 (UTC)

**Result:** the client now requires both local native/helper capability and a
usable API server entry before a protocol is selectable or Connect is enabled.
No staging or production API, account, profile, VPN server, cloud resource, or
tunnel was contacted. No release status, download availability, or package was
published or changed.

## Live checkout wiring

The clean checkout now defaults to the real control-plane path. `DEMO_MODE` and
`WG_MOCK_MODE` are false unless explicitly set for isolated tests; the backend
and WireGuard service no longer auto-detect a demo tunnel from missing host
tools. The Flutter `.env` file is optional and no longer a required asset, so a
fresh clone can run with the checked-in live API fallback or explicit
`--dart-define` values.

The health endpoints identify the service as `securewave-vpn`; they no longer
return a demo service label. Health `status: ok` means the API process is up,
not that a VPN server or protocol is usable.

This makes the app runnable from GitHub without manufacturing availability:
health and protocol responses still reflect actual backend/server evidence.

## Layered protocol matrix

| Layer | WireGuard | OpenVPN | IKEv2 |
| --- | --- | --- | --- |
| Local client helper | Local contract-10 service/socket/verifier evidence exists. This is not server proof. | Local contract-10 helper probe/verifier evidence exists. This is not server/profile proof. | Helper code may exist, but local helper capability is not a Linux product gate. |
| Authorized staging server runtime | **Unavailable:** no named staging target or redacted runtime audit was supplied. | **Unavailable:** no named staging target, server provisioning evidence, or compatible credential lifecycle was supplied. | **Unavailable by design:** no separate authorization or complete proof. |
| Backend API availability | Fails closed without fresh healthy WireGuard-specific server evidence. | Fails closed without complete metadata and fresh healthy OpenVPN-specific evidence. | Always not release-ready for Linux. |
| Profile issuance | Blocks before device key/profile issuance when readiness is false; WireGuard also requires peer registration. | Blocks when metadata/evidence is incomplete; an issued configuration alone is not a server authentication or tunnel proof. | Linux profile request is rejected. |
| Flutter UI | Requires native capability **and** an API `supported_protocols` entry from a usable server; otherwise selector/Connect are unavailable. | Same dual gate. | Native Linux gate keeps it unavailable even if a stale catalog were to claim support. |
| Live client proof | **Not run:** no authorized staging account/profile/server. | **Not run:** no authorized staging account/profile/server. | Not applicable; intentionally unavailable. |

## Change made

The server catalog model previously treated an absent or empty
`supported_protocols` list as supporting every protocol and fell back to static
support booleans. That could make a locally capable helper look connectable
without API server runtime evidence.

The client now fails closed:

1. `ServerRegion` accepts only explicit `supported_protocols` entries as API
   runtime evidence.
2. The protocol selector requires both `VpnService.canConnectProtocol` and a
   matching usable server in the current catalog (or selected server).
3. The Connect control is disabled for a disconnected protocol that lacks
   either gate and explains whether native or backend evidence is missing.
4. Disconnect remains available for an already connected state, so a catalog
   refresh cannot prevent cleanup.

This does not fabricate server evidence or change backend metadata. It makes
the app faithfully reflect the existing backend availability/profile gates.

## Regression coverage

| Requirement | Evidence |
| --- | --- |
| Missing server evidence fails closed | Backend profile tests cover missing/stale/future evidence; new static-metadata-only case verifies `/api/vpn/protocols` disables WireGuard and OpenVPN. |
| Unavailable protocols remain unavailable | Linux IKEv2 endpoint/profile tests remain blocked; Flutter native and catalog gates both reject it. |
| Local helper does not imply server availability | New Flutter widget regression injects a locally capable service with an empty-evidence catalog and verifies the warning plus disabled Connect control. |
| Incomplete server state cannot issue a profile | New OpenVPN test verifies incomplete endpoint/CA state returns `503`. |
| UI does not present unavailable protocols as connectable | New Flutter catalog regression and explicit Connect gating. |

## Verification

Commands used only local sources, placeholder test configuration, and redacted
status checks. No credentials, private keys, profiles, hostnames, endpoints, or
customer data were printed or written to this artifact.

| Check | Result |
| --- | --- |
| Focused backend profile regression suite | 18 passed |
| Final backend/profile/flow/device/usage/manifest/security suite | 67 passed |
| Live-mode/env/health/profile suite | 90 passed |
| Focused Flutter protocol/UI suite | 11 passed |
| Full Flutter suite | 28 passed |
| Flutter analysis | passed; no issues |
| Clean-checkout Flutter asset resolution | passed; `.env` is optional |
| Manifest JSON parse | passed |
| Website JavaScript syntax | passed |
| Release guards | passed |
| Tracked-file secret scan | passed; values redacted by scanner |
| Bandit high-severity scan | passed (informational `# nosec` warnings only) |
| Dependency audit | passed; no known vulnerabilities |
| `git diff --check` | passed |

The existing Python test environment emits a `pytest-asyncio` warning about an
unset default event-loop scope; the targeted tests passed.

## Website/download documentation

`static/download.html`, `static/vpn.html`, and `static/js/downloads.js` were
inspected. They contain no protocol availability assertion that needs changing;
the download manifest was parsed successfully and was not modified. Repository
documentation and the portability matrix now state that local helper evidence
does not imply server/runtime availability.

## Usage accounting

Usage accounting has backend and Flutter automated coverage for session
start/increment/finalization and counter polling. It is **not live-proven** for
staging because no authorized tunnel, transfer, API session, logout/login, or
persistence target was available. This change does not alter accounting logic.

## Remaining blockers

1. A named staging target demonstrably separate from production.
2. Authorized staging test account/device and safe credential delivery.
3. Fresh protocol-specific WireGuard and OpenVPN server runtime evidence,
   including firewall, NAT, routing, DNS, backend management, and profile
   readiness.
4. Bounded live data-plane, exit-IP, counter, disconnect, cleanup, and usage
   persistence evidence for each authorized protocol.
5. Separate authorization and complete server/runtime proof before IKEv2 could
   ever be enabled; it remains disabled on Linux.

This is a truth-alignment change, not staging certification or a release
readiness claim.
