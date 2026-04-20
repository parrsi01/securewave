# SecureWave v1 Release Scope Audit

Date: 2026-04-21
Scope: Internal release decision summary before implementation work.

## 1. Executive Summary

SecureWave v1 should be scoped as a Linux desktop first, WireGuard-primary release only.

The repository contains evidence that WireGuard is the real supported tunnel path and that Linux can operate through `wg-quick` when system prerequisites are present. The same evidence also shows that protocol and platform availability must be treated conservatively: daemon-level success, isolated config generation, or support code in the repository is not enough to expose a protocol publicly.

For v1, the release-critical rule is:

Only expose protocols and platforms that are proven end-to-end through the normal backend provisioning path, client runtime path, and release UI.

OpenVPN and IKEv2 are not release-ready unless the backend provisioning path, client protocol selection path, native/runtime execution path, and validation evidence all match. Current audit evidence says native client implementations support WireGuard only, while OpenVPN and IKEv2 protocol options can exist at the Dart/API level without true native backing. That is not safe to expose publicly.

The exact prompt-listed source files were not present in this Mac checkout or in `origin/master` under the requested names. This audit reused the available repository evidence listed in the Change Log.

## 2. In Scope for v1

- Linux desktop release only.
- WireGuard as the only public VPN protocol.
- Backend-issued WireGuard profile data.
- Linux client runtime using the normal WireGuard path, subject to release-machine prerequisites:
  - `wireguard-tools` installed.
  - `wg-quick` available.
  - root/sudo path configured in a supportable way.
  - live WireGuard server endpoint validated.
- Hetzner single-server deployment model, because current top-level architecture and README describe Hetzner as the supported production path.
- Honest release documentation that states operational requirements and avoids false anonymity or unsupported protocol claims.

## 3. Out of Scope for v1

- macOS VPN support.
- macOS as a release platform.
- Public multi-protocol marketing claims.
- Public OpenVPN support unless separately fixed and revalidated end-to-end.
- Public IKEv2 support unless separately hardened and revalidated end-to-end.
- Azure as the supported production deployment path.
- Claims that kill switch behavior is fully enforced by SecureWave across platforms.
- Claims that daemon-level validation alone proves app-level support.

## 4. Blocked / Conditional for v1

- OpenVPN: blocked unless there is proof that backend provisioning, generated client profiles, client protocol selection, native/runtime execution, and release UI all use OpenVPN end-to-end. A daemon working in isolation is insufficient.
- IKEv2: blocked unless provisioning, authentication, certificate/key handling, client execution, and release UI are hardened and validated end-to-end. Until then it should be hidden, manual-only, or experimental.
- Windows: blocked for this release direction unless explicitly re-scoped. Existing evidence indicates WireGuard can work with WireGuard for Windows installed, but this prompt's recommended direction is Linux desktop first.
- Android and iOS: blocked for this release direction unless explicitly re-scoped. Existing docs contain readiness notes for both, but the current release direction excludes them from the first v1 lane.
- Live release readiness: blocked until the Linux WireGuard path is validated against a real backend-issued profile and real server endpoint, not only local config generation.
- Production deployment: blocked until production secrets, environment validation, database configuration, and WireGuard key/config permissions are verified.

## 5. Post-v1 by design

- macOS VPN implementation using a real Network Extension path.
- OpenVPN public support, if the full backend-to-client path is implemented and certified.
- IKEv2 public support, if provisioning, auth, certificates, and client behavior are hardened.
- Windows release lane.
- Mobile release lanes.
- Stronger cross-platform kill switch implementation.
- Full tunnel state monitoring beyond best-effort client state.
- Larger-scale IP allocation design beyond small single-server assumptions.
- Formal performance comparison against commercial VPNs using same device, same ISP, same region, same time window, and VPN-on measurements.

## 6. Top 5 Release Blockers

1. Protocol exposure mismatch: client/API surfaces can mention OpenVPN and IKEv2 while native implementations are evidenced as WireGuard-only. Public UI must not expose protocols that are not truly supported.
2. Missing end-to-end Linux WireGuard proof against a live backend-issued profile and real server endpoint.
3. Production hardening gaps around secrets, environment configuration, and WireGuard private key/config file permissions.
4. Kill switch and tunnel-state limitations: the product must not imply traffic is protected after tunnel failure unless enforcement and state reporting are proven.
5. Documentation drift: older docs describe broader platform readiness, while the practical v1 release decision should be Linux desktop first and WireGuard only.

## 7. Recommended canonical release statement

SecureWave v1 is a Linux desktop VPN release using WireGuard as the only supported public protocol. OpenVPN and IKEv2 are not exposed in v1 unless and until they are proven end-to-end through backend provisioning, generated client configuration, client runtime execution, and release validation. macOS is out of scope for v1. Other platforms and protocols are post-v1 or experimental until explicitly hardened, documented, and revalidated.

## 8. Documentation files that should be updated next

- `README.md`: state the canonical v1 scope and remove or qualify public multi-protocol/platform claims.
- `ARCHITECTURE.md`: clarify WireGuard-only v1 data flow and mark other protocol paths as non-release or future.
- `docs/RELEASE_CHECKLIST.md`: add Linux WireGuard-only v1 gate checks and protocol exposure checks.
- `securewave_app/README.md`: align client platform claims with the Linux-first v1 decision.
- Linux setup docs under `securewave_app/`: make WireGuard prerequisites and sudo/runtime expectations explicit.
- Any protocol guide or UI-facing docs that mention OpenVPN/IKEv2: mark them hidden, experimental, or post-v1 until end-to-end proof exists.
- Add or restore a canonical `project_plan.md` / current release status document if the Linux VM has one that is not yet synchronized to this Mac checkout.

## Change Log

### What changed

- Added this internal release-scope audit artifact:
  - `artifacts/release_scope_audit.md`

### What was reused

- `ARCHITECTURE.md`
- `README.md`
- `docs/RELEASE_CHECKLIST.md`
- `artifacts/vpn_tests/20260208_113437/reports/FINAL_VPN_REVIEW_REPORT.md`
- `artifacts/vpn_tests/20260208_113437/reports/POST_FIX_VALIDATION_REPORT.md`
- `artifacts/vpn_tests/20260208_113437/raw/platform_review.md`
- `artifacts/vpn_tests/20260208_113437/raw/security_audit.md`

### What was intentionally left untouched

- Application code.
- Tests.
- Existing documentation files.
- Existing local untracked and modified files.
- Protocol implementation paths.
- Release workflow files.

### Risks introduced

- No code/runtime risk; this is a documentation artifact only.
- Git workflow risk remains: the Mac checkout has local untracked files that overlap files now present on `origin/master`, which prevented a clean pull with autostash. That must be reconciled before a normal local pull/push cycle can complete.
- Source coverage risk: the exact Linux-path files named in the prompt were not present in this Mac checkout or `origin/master`, so this audit is based on the closest available repository evidence.
