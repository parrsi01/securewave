# SecureWave Portable Release Closeout Plan

Last updated: 2026-07-09 UTC

This is the final planning gate for making SecureWave usable across Linux
ARM64, Linux x64, Windows, and macOS without false public claims. It is based
on current evidence, not intended future behavior.

This plan does not authorize production deploys, artifact publication, x64
builds on ARM64 hardware, runtime/helper/protocol changes, or broad legal or
security claims.

## Evidence Basis

Inspected evidence:

- `artifacts/post-merge-enterprise-release-evidence/README.md`
- `docs/PORTABILITY_RUNTIME_MATRIX.md`
- `docs/POST_MERGE_ENTERPRISE_RELEASE_TODO.md`
- `static/downloads/manifest.json`

Optional evidence not present on this branch:

- `docs/LINUX_MULTIARCH_PACKAGING.md`
- `docs/LINUX_X64_DEB_RELEASE_RUNBOOK.md`

Current release truth:

- Linux ARM64 portable UI package is available, but portable mode is UI-only
  unless the privileged helper and host VPN tools are installed separately.
- Linux x64 `.deb`, AppImage, and portable tarball remain `coming_soon`.
- A tracked Linux x64 tarball name cannot be used as proof if the binary inside
  is not x86_64.
- Windows installer remains `coming_soon`; current Windows runtime is
  WireGuard-only and not release-proven.
- macOS Apple Silicon UI demo and Apple handoff kit are available; macOS VPN
  routing is unsupported until signed Network Extension or WireGuardKit proof
  exists.
- Hetzner fleet audit, external load testing, Terraform validation, monitoring
  evidence, public checksum verification, and final protocol docs are blocked
  or incomplete.

## Status Terms

| Term | Meaning |
| --- | --- |
| Release-proven | Artifact, install, launch, connect, routing, disconnect, cleanup, logs, and checksums are all recorded in reviewable evidence. |
| UI-only | The app/account interface can be launched, but full traffic routing is not claimable. |
| Blocked | Work must stop until the named hardware, credential, authorization, artifact, or proof exists. |
| Unsupported | The app must fail closed and user-facing docs must not imply runtime availability. |

## Platform Release Paths

### Linux ARM64

Release target:

- ARM64 Debian/Ubuntu/systemd `.deb` package for full routing after the
  privileged helper is installed.
- ARM64 portable zip can remain available as UI-only unless a separate helper
  install is documented and proven.

Artifact requirements:

- Native ARM64 package built on this ARM64/aarch64 host or another verified
  ARM64 runner.
- Package filename, version, architecture, SHA-256, file size, MIME type, and
  `dpkg-deb --info` / `dpkg-deb --contents` output.
- No overwrite of existing ARM64 artifacts without preserving prior evidence.
- Public manifest entry only after the package and checksum are final.

Install requirements:

- Clean ARM64 Debian/Ubuntu/systemd VM.
- Install-time admin authorization is acceptable and expected.
- Runtime dependencies documented: WireGuard tools, OpenVPN, strongSwan only if
  the related protocol is supported, NetworkManager/strongSwan pieces if IKEv2
  is ever promoted.

Runtime proof requirements:

- UI launch after package install.
- Login/profile fetch against the intended control plane.
- Connect, route/DNS/public-IP proof, data usage reporting, disconnect, and
  uninstall/cleanup proof.
- No mock tunnel, no fake connected state, no success claim without tunnel
  evidence.

Helper/service proof requirements:

- Helper binary path, owner, group, permissions, and checksum.
- systemd unit status, enablement state if applicable, socket or service logs,
  and journal excerpts with secrets redacted.
- Helper contract/version file if present.
- Connect/disconnect must not prompt after `.deb` helper install; if a prompt
  appears, stop the full-routing release claim.

### Linux x64

Release target:

- Linux x64 Debian/Ubuntu/systemd `.deb` package produced on native x86_64
  infrastructure.
- x64 portable tar/AppImage only after true x86_64 artifact proof; portable
  artifacts remain UI-only unless privileged helper setup is separately proven.

Artifact requirements:

- Do not build or prove x64 artifacts on the ARM64 host.
- Native x86_64 build evidence from GitHub Actions `ubuntu-latest` or an
  equivalent clean x86_64 runner.
- `uname -m=x86_64`, `dpkg --print-architecture=amd64`, package metadata,
  checksum, contents listing, and artifact retention link.
- If `docs/LINUX_MULTIARCH_PACKAGING.md` or
  `docs/LINUX_X64_DEB_RELEASE_RUNBOOK.md` is still absent, create or merge that
  runbook before publishing any x64 package.

Install requirements:

- Clean x86_64 Debian/Ubuntu/systemd VM.
- Install with the exact downloaded artifact and checksum.
- Verify no stale ARM64 archive or wrong-architecture file is referenced.

Runtime proof requirements:

- Same as Linux ARM64, captured on x86_64.
- Include `file` output for the app binary and package architecture checks.

Helper/service proof requirements:

- Same as Linux ARM64, captured on x86_64.
- x64 helper/systemd proof is the final gate before marking the x64 `.deb`
  available in the public manifest.

### Windows

Release target:

- Windows x64 installer after package, install, service, and runtime evidence.
- Current runtime claim is WireGuard-only. OpenVPN and IKEv2 are unsupported on
  Windows unless new implementation and proof are added in a separate scope.

Artifact requirements:

- Installer filename, version, architecture, SHA-256, size, MIME type, and
  signing status.
- Build log from a Windows runner or Windows host.
- Public manifest update only after artifact verification.

Install requirements:

- Clean supported Windows host.
- WireGuard for Windows installed or bundled/installed by the release flow if
  that becomes the chosen supported path.
- Administrator/service permissions documented.

Runtime proof requirements:

- UI launch, login, WireGuard profile fetch, tunnel service install/start,
  route/DNS/public-IP proof, data usage reporting, disconnect, service removal,
  and app uninstall proof.
- If WireGuard for Windows is missing, the app must return unavailable and stay
  disconnected.

### macOS

Release target:

- UI demo may remain available as UI-only.
- Full VPN routing requires signed Network Extension or WireGuardKit runtime
  proof before any public VPN claim.

Artifact requirements:

- For UI demo: architecture, checksum, size, notarization/signing status, and
  clear notes that VPN routing is disabled.
- For VPN-capable release: signed app, Network Extension entitlement evidence,
  notarization proof if distributed outside the App Store, and checksum.

Install requirements:

- Clean macOS host matching target architecture.
- Apple Developer signing identity and entitlements.
- User/system approval steps documented realistically.

Runtime proof requirements:

- UI launch and account flow for UI-only demo.
- For full routing: Network Extension install, profile approval, connect,
  route/DNS/public-IP proof, data usage reporting, disconnect, cleanup, and
  uninstall proof.
- If no Network Extension exists, connect/disconnect must return unavailable.

## Protocol Proof Requirements

| Protocol | Linux | Windows | macOS | Closeout gate |
| --- | --- | --- | --- | --- |
| WireGuard | Candidate runtime path. Requires helper/tooling proof per architecture. | Candidate runtime path through WireGuard for Windows. | Unsupported until Network Extension/WireGuardKit proof exists. | Must include profile fetch, tunnel creation, route/DNS/public-IP, disconnect, cleanup, and usage reporting. |
| OpenVPN | Implemented but not release-proven on Linux; requires host OpenVPN tooling and clean VM proof. | Unsupported in current Windows app path. | Unsupported in current macOS app path. | Missing runtime must return unavailable; no public support claim without proof. |
| IKEv2 | Unsupported/currently blocked in public Linux runtime truth unless strongSwan import/start and connected-state proof exist. | Unsupported in current Windows app path. | Unsupported in current macOS app path. | Require profile import/start, route/DNS proof, and XFRM ESP or equivalent platform-native tunnel evidence before any claim. |

## User Support And Debug Requirements

Publish a support/debug runbook before public release that covers:

- Package install logs and checksum verification.
- Helper/service status and permissions.
- WireGuard, OpenVPN, and IKEv2 unavailable-state messages.
- DNS, route, public-IP, and tunnel-interface checks.
- Usage-metering checks and backend report correlation.
- Redaction rules for configs, tokens, private keys, emails, IPs where needed,
  and payment data.
- Escalation bundle contents and owner routing.
- Clear user copy for UI-only portable packages.

## Monitoring Requirements

Before claiming production readiness, record links or exported evidence for:

- API health and readiness.
- Login/auth failures.
- VPN profile issuance failures by protocol.
- Device limit and profile reference errors.
- VPN usage reporting ingestion.
- Container, database, Redis, disk, CPU, memory, and network health.
- Protocol-specific failure alerts for WireGuard/OpenVPN/IKEv2.
- Download error rate and checksum mismatch reports.
- Named alert owners and escalation paths.

## Public Download Requirements

Do not mark an artifact `available` until all are true:

- Artifact exists at the public URL.
- Architecture is proven with native tooling (`file`, package metadata, or
  platform-specific equivalent).
- SHA-256 is published and verified from the public URL.
- File size and MIME type are recorded.
- Install and launch evidence exists for the target platform.
- Runtime claim in notes matches the proof level: full routing, UI-only,
  blocked, or unsupported.
- No stale local, branch, placeholder, or wrong-architecture URL remains.

## Prioritized Checklist

1. [ ] ARM64 local package proof: build/identify the ARM64 `.deb`, install on a
   clean ARM64 Debian/Ubuntu/systemd VM, prove helper/service status, launch,
   WireGuard routing, disconnect, and uninstall.
2. [ ] x64 GitHub Actions build evidence: create or merge the manual x64 build
   workflow/runbook, run on native x86_64, and retain package metadata,
   contents, checksum, and runner architecture evidence.
3. [ ] x64 clean VM install/helper proof: install the exact x64 artifact on a
   clean x86_64 Debian/Ubuntu/systemd VM and prove helper/no-connect-prompt
   connect/disconnect behavior.
4. [ ] Manifest/checksum publication: publish only proven artifacts, add or
   publish checksum evidence, verify public URLs, and keep unproven artifacts
   `coming_soon`.
5. [ ] Protocol docs truth update: reconcile `README.md`,
   `docs/current_release_status.md`, setup docs, and website copy with final
   WireGuard/OpenVPN/IKEv2 proof.
6. [ ] Windows packaging/runtime proof: build installer, verify install,
   WireGuard for Windows detection/service behavior, routing, disconnect,
   cleanup, and manifest/checksum publication.
7. [ ] macOS signed Network Extension/runtime proof: keep UI demo UI-only until
   signed Network Extension or WireGuardKit build, entitlement, notarization,
   install, connect, routing, disconnect, and cleanup proof exist.
8. [ ] External load test authorization: get written authorization, run only
   against SecureWave-owned infrastructure, and record p95/p99 latency, error
   rate, profile fetch, usage reporting, and protocol-specific failures.
9. [ ] Hetzner fleet audit credentials: run the fleet audit only with
   `HETZNER_API_TOKEN` or `HCLOUD_TOKEN` set, and record redacted summary
   evidence.
10. [ ] Terraform validation environment: install or provision Terraform, run
    validation/plan in the approved environment, and record redacted output.

## Stop Conditions

Stop and keep the release blocked if any of these occurs:

- Any artifact architecture does not match its filename, manifest entry, or
  target platform.
- x64 package build or runtime proof is attempted on the ARM64 host.
- A public manifest entry would mark an unproven or unavailable package
  `available`.
- A portable archive is described as full-routing without separate privileged
  helper/runtime proof.
- Linux `.deb` connect/disconnect requires a runtime privilege prompt after
  helper install.
- Helper binary, service unit, permissions, or contract evidence is missing.
- Tunnel state is inferred from UI state alone.
- Mock/demo mode is active during release proof.
- OpenVPN or IKEv2 is claimed on a platform where current code does not support
  it.
- macOS VPN routing is claimed without signed Network Extension or WireGuardKit
  proof.
- Windows VPN routing is claimed beyond WireGuard without implementation and
  proof.
- External load testing lacks explicit authorization.
- Hetzner credentials, Apple signing assets, or Terraform tooling are missing.
- Secrets, private keys, tokens, personal payment data, or unredacted sensitive
  logs would be committed or published.

## Closeout Evidence Packet

The final release packet should contain:

- Commit SHA and artifact version.
- Per-platform artifact URL, SHA-256, size, architecture, and signing status.
- Per-platform install and uninstall proof.
- Per-protocol runtime proof or explicit unsupported/blocked note.
- Linux helper/service proof for each Linux architecture.
- Public manifest verification output.
- Monitoring and alert links or exported snapshots.
- Support/debug runbook link.
- Redacted external load-test summary and authorization reference.
- Redacted Hetzner fleet audit summary.
- Terraform validation output.
