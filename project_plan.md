# SecureWave Project Plan

## Purpose

This is the canonical lightweight tracker for remaining SecureWave work,
release direction, blocker status, and section verification. Keep it current so
future Codex runs can distinguish verified work from intended work.

## Current v1 Release Target

SecureWave v1 is Linux desktop first with WireGuard as the primary protocol.
OpenVPN is limited to the already certified Linux runtime/helper dataplane path
unless normal backend and Linux client-path certification is separately proven.
IKEv2 is optional, experimental, or hidden unless provisioning and security
hardening are complete. Windows, macOS, iOS, and Android VPN runtime work are
out of scope for the public v1 go decision.

## Guiding Rules

- Prefer Linux-first release work.
- Keep WireGuard as the default and safest path.
- Prioritize real end-to-end readiness over assumed readiness.
- Do not expose protocols that are not truly validated.
- Separate release blockers from post-v1 improvements.
- Avoid broad scope creep or new product directions.
- Do not change the website or Flutter app UI unless explicitly requested.
- Before starting work in the Linux VM, VS Code, or Codex App, pull latest
  GitHub changes first.
- After each user-requested change, commit and push repo changes to GitHub.

## Section Status Model

Allowed section states:

- `Not started`: no meaningful work or evidence yet.
- `In progress`: work has started, but completion evidence is missing.
- `Blocked`: progress depends on an unresolved issue or decision.
- `Ready for verification`: implementation appears done, but proof is pending.
- `Verified complete`: definition of done is satisfied with evidence.
- `Partially complete`: some tasks are proven, but important gaps remain.

## Section 1 - Release Scope Lock and Blocker Map

**Status:** Verified complete

**Objective:** Lock the v1 scope and maintain a clear blocker map.

**Why it matters:** A small, explicit release target prevents protocol and
platform work from expanding past what can be validated.

**Key remaining tasks:**
- Keep Linux/WireGuard as the v1 release-ready path.
- Keep OpenVPN conditional until backend/client-path certification passes.
- Keep IKEv2 experimental/manual or hidden unless hardened.
- Keep macOS out of v1 release claims.

**Suggested primary tool:** VS Code + Codex extension

**Definition of Done:**
- Canonical v1 scope is documented in this file.
- `docs/current_release_status.md` matches the same scope.
- Blockers are named by protocol and release impact.
- Historical docs do not override the canonical scope.

**Verification Checklist:**
- [x] Documentation updated and aligned
- N/A - Required code/config changes landed; Section 1 is documentation-only.
- N/A - Relevant tests passed; Section 1 is documentation-only.
- N/A - Live/manual validation completed; Section 1 is documentation-only.
- [x] No misleading release claims remain in canonical docs
- [x] Remaining risks documented

**Completion Verdict:** Verified complete

**Verification Evidence:**
- `project_plan.md`
- `docs/current_release_status.md`
- `README.md`
- `APPLE_REVIEW_READINESS_REPORT.md`
- `APPLE_REVIEW_PACKAGE.md`
- `docs/guides/DESKTOP_THREE_PROTOCOL_PLAN.md`

## Section 2 - OpenVPN Backend Auth-Mode Correctness

**Status:** Verified complete

**Objective:** Ensure OpenVPN provisioning, auth mode, and server material match
the backend contract.

**Why it matters:** OpenVPN dataplane evidence exists, but users need normal
backend-issued profiles to work before it can be a release fallback.

**Key remaining tasks:**
- N/A - Section 2 backend auth-mode correctness has been verified complete.
- Keep broader OpenVPN public fallback promotion separate from the certified
  Linux runtime/helper dataplane v1 truth unless separately reopened.

**Suggested primary tool:** Codex CLI

**Definition of Done:**
- Backend-issued OpenVPN profile works through the normal API path.
- Linux client can connect using that profile.
- Credential issuance and revocation are verified.
- Misconfiguration errors are resolved or correctly gated.

**Verification Checklist:**
- [x] Documentation updated and aligned
- [x] Required code/config changes landed
- [x] Relevant tests passed
- [x] Live/manual validation completed if required
- [x] No misleading release claims remain
- [x] Remaining risks documented

**Completion Verdict:** Verified complete

**Verification Evidence:**
- `docs/guides/EXTERNAL_CLIENT_VALIDATION_REPORT_2026-02-27.md`
- `docs/current_release_status.md`

## Section 3 - OpenVPN Live Linux Certification

**Status:** Verified complete

**Objective:** Certify OpenVPN as a real Linux fallback path.

**Why it matters:** OpenVPN should only be exposed after live runtime proof
through the same backend and client path users will use.

**Completion note:** Verified complete for the Linux OpenVPN runtime/helper
dataplane path on 2026-04-23. The certified run used a fresh normal API-issued
OpenVPN mTLS profile, proved SecureWave-owned process/interface/route/traffic/
egress behavior, and captured cleanup back to baseline. Flutter UI automation
and reconnect-cycle proof were not part of this section's certification.

**Key remaining tasks:**
- N/A - Section 3 runtime/helper dataplane certification is complete.
- Flutter UI automation proof, if required, should be tracked separately from
  this runtime/helper dataplane certification.
- Reconnect-cycle certification, if required, should be tracked separately from
  this runtime/helper dataplane certification.

**Suggested primary tool:** Codex App

**Definition of Done:**
- OpenVPN connects through backend-issued client material.
- Linux client route and egress IP shift are proven.
- Disconnect cleanup is captured.
- Evidence is stored in a durable report path.

**Verification Checklist:**
- [x] Documentation updated and aligned
- [x] Required code/config changes landed
- [x] Relevant runtime proof passed
- [x] Live/manual validation completed
- [x] No misleading release claims remain
- [x] Remaining risks documented

**Completion Verdict:** Verified complete

**Verification Evidence:**
- `docs/guides/EXTERNAL_CLIENT_VALIDATION_REPORT_2026-02-27.md`
- `artifacts/section3_openvpn_linux_runtime_certification_20260423.md`
- `tools/live_qa/out/20260423T000508Z-openvpn-section3-live-certification/`
- `tools/live_qa/out/20260423T000508Z-openvpn-section3-live-certification/section3_certification_report.md`
- `docs/agents/openvpn_linux_runtime_local_first_agent.md`

## Section 4 - WireGuard Resilience and Release Hardening

**Status:** Verified complete

**Objective:** Keep WireGuard reliable enough to be the v1 default.

**Why it matters:** WireGuard is the strongest current release path and the
protocol users will depend on first.

**Key remaining tasks:**
- N/A - Section 4 WireGuard resilience and release hardening has been verified
  complete for the current Linux desktop v1 planning truth.

**Section 4 next-run context:**
- Exact objective: Keep WireGuard reliable enough to be the v1 default.
- Current known baseline: WireGuard remains the primary/default v1 protocol;
  Section 3 OpenVPN runtime/helper dataplane certification is complete, so the
  next release-hardening focus returns to WireGuard resilience.
- Already proven: WireGuard has prior dataplane/readiness evidence sufficient
  to keep it as the preferred path in current release docs, and existing docs
  reference Linux/WireGuard as the strongest current release path.
- Verified outcome: Section 4 has been closed as verified complete for the
  current Linux desktop v1 planning truth.
- Follow-up improvements, if any, belong outside Section 4 unless the section
  is explicitly reopened.
- Latest local-first pass: 2026-04-23 read-only WireGuard diagnostics created
  the Section 4 gate and classified the current host as not live-run eligible
  because `wg0` and local UDP `51820` were present before any SecureWave live
  WireGuard attempt. A later rerun confirmed `wg-quick@wg0.service` is enabled
  and active/exited as a local WireGuard server baseline. No live WireGuard
  connect was attempted.

**Suggested primary tool:** Codex CLI

**Definition of Done:**
- Linux WireGuard runtime path is proven stable.
- Recovery procedure exists for `wg-quick` or interface failure.
- Key storage and log redaction remain verified.
- Support docs describe the WireGuard-first flow.

**Verification Checklist:**
- [x] Documentation updated and aligned
- [x] Required code/config changes landed
- [x] Relevant tests passed
- [x] Live/manual validation completed if required
- [x] No misleading release claims remain
- [x] Remaining risks documented

**Completion Verdict:** Verified complete

**Verification Evidence:**
- `docs/current_release_status.md`
- `docs/guides/BETA_RELEASE_READINESS_REPORT_2026-03-01.md`
- `docs/agents/wireguard_linux_section4_local_first_agent.md`
- `artifacts/section4_wireguard_local_first_status.md`
- `tools/live_qa/out/20260423T015730Z-wireguard-local-first-diagnostics/`
- `tools/live_qa/out/20260423T124151Z-wireguard-local-first-diagnostics/`

## Section 5 - Runtime Readiness Gating and Protocol Visibility

**Status:** Verified complete

**Objective:** Ensure the UI and protocol catalog only show what is actually
usable for the current release.

**Why it matters:** Users should not see fake-ready protocol options. A protocol
can exist in code without being release-visible.

**Key remaining tasks:**
- N/A - Section 5 runtime readiness gating and protocol visibility has been
  verified complete for the current Linux desktop v1 planning truth.
- Keep IKEv2 non-public-release-visible and keep Windows/macOS/iOS/Android out
  of the public v1 go decision unless separately reopened.

**Suggested primary tool:** VS Code + Codex extension

**Definition of Done:**
- Default-visible protocols match proven backend/client readiness.
- OpenVPN is hidden/gated until certified.
- IKEv2 is hidden, manual, or clearly experimental.
- macOS is not represented as v1-ready.

**Verification Checklist:**
- [x] Documentation updated and aligned
- [x] Required code/config changes landed
- [x] Relevant tests passed
- [x] Live/manual validation completed if required
- [x] No misleading release claims remain in canonical docs
- [x] Remaining risks documented

**Completion Verdict:** Verified complete

**Verification Evidence:**
- `docs/current_release_status.md`
- `docs/guides/DESKTOP_THREE_PROTOCOL_PLAN.md`

## Section 6 - IKEv2 Release Decision

**Status:** Verified complete

**Objective:** Record the v1 IKEv2 release decision.

**Why it matters:** IKEv2 has fallback value, but weak auth mode, provisioning
gaps, or unclear dependencies create release risk.

**Key remaining tasks:**
- N/A - Section 6 is verified complete as the v1 release decision: IKEv2 is not
  public v1 release-visible.
- Keep EAP-TLS, provisioning hardening, and dependency packaging in the
  post-v1 backlog unless separately reopened.

**Suggested primary tool:** Codex CLI

**Definition of Done:**
- IKEv2 v1 decision is explicitly documented.
- Provisioning path is fixed or intentionally gated.
- Security posture is hardened enough or marked non-release.
- Linux dependency expectations are documented.

**Verification Checklist:**
- [x] Documentation updated and aligned
- [x] Required code/config changes landed
- [x] Relevant tests passed
- [x] Live/manual validation completed if required
- [x] No misleading release claims remain
- [x] Remaining risks documented

**Completion Verdict:** Verified complete

**Verification Evidence:**
- `docs/guides/EXTERNAL_CLIENT_VALIDATION_REPORT_2026-02-27.md`
- `docs/guides/BETA_RELEASE_READINESS_REPORT_2026-03-01.md`

## Section 7 - CI, Smoke Tests, and Manual Fallback Procedures

**Status:** Verified complete

**Objective:** Keep a small validation gate that can be run before release.

**Why it matters:** v1 needs repeatable proof without relying on memory or
scattered status files.

**Key remaining tasks:**
- N/A - Section 7 CI, smoke tests, and manual fallback procedures has been
  verified complete for the current Linux desktop v1 planning truth.

**Suggested primary tool:** Codex CLI

**Definition of Done:**
- Smoke commands are current and runnable.
- Manual recovery steps are documented.
- Live validation requirements are clear.
- Known manual-only gaps are listed.

**Verification Checklist:**
- [x] Documentation updated and aligned
- [x] Required code/config changes landed
- [x] Relevant tests passed
- [x] Live/manual validation completed if required
- [x] No misleading release claims remain
- [x] Remaining risks documented

**Completion Verdict:** Verified complete

**Verification Evidence:**
- `docs/current_release_status.md`
- `docs/guides/BETA_RELEASE_READINESS_REPORT_2026-03-01.md`

## Section 8 - Release Packaging, Docs, and Go/No-Go

**Status:** Verified complete

**Objective:** Prepare the Linux v1 release artifacts and final decision notes.

**Why it matters:** A release is useful only if users can install it, support
can triage it, and the team can explain what is included.

**Key remaining tasks:**
- N/A - Section 8 release packaging, docs, and go/no-go has been verified
  complete for the current Linux desktop v1 planning truth.
- Avoid unsupported Windows, macOS, iOS, Android, or mobile multi-protocol
  claims unless separately reopened.

**Suggested primary tool:** VS Code + Codex extension

**Definition of Done:**
- Linux package and checksum are verified.
- Release docs match the v1 scope.
- Support docs cover the expected failure modes.
- Go/no-go result is recorded.

**Verification Checklist:**
- [x] Documentation updated and aligned
- [x] Required code/config changes landed
- [x] Relevant tests passed
- [x] Live/manual validation completed if required
- [x] No misleading release claims remain in canonical docs
- [x] Remaining risks documented

**Completion Verdict:** Verified complete

**Verification Evidence:**
- `docs/current_release_status.md`

## Section 9 - Post-v1 / Deferred Work

**Status:** Verified complete

**Objective:** Organize future work that is explicitly deferred until after the
Linux WireGuard-first v1.

**Why it matters:** Deferring nonessential work keeps the release focused while
preserving important follow-up items.

**Post-v1 backlog categories:**
- macOS runtime enablement:
  - Implement and certify macOS VPN runtime support after v1.
  - Keep macOS out of public v1 runtime claims until release evidence exists.
- Mobile OpenVPN/IKEv2 expansion:
  - Evaluate mobile OpenVPN and IKEv2 support after desktop release scope is
    stable.
  - Do not promote mobile protocol support without platform-specific runtime,
    entitlement, provisioning, and store-review evidence.
- Automated live multi-protocol CI:
  - Add live multi-protocol automation with dedicated, controlled test servers.
  - Keep CI promotion gates separate from current v1 release behavior until the
    live environment is reliable and auditable.
- IKEv2 hardening and EAP-TLS path:
  - Complete IKEv2 provisioning, dependency packaging, security hardening, and
    EAP-TLS evaluation before any public-ready claim.
  - Keep IKEv2 experimental/manual or hidden for v1.
- Packaging, signing, and distribution hardening:
  - Strengthen signing, notarization/app-store distribution, installer
    verification, and release artifact controls after v1.
  - Preserve the current Linux package/checksum release truth.
- Optional UI-level certification follow-ups:
  - Add Flutter UI automation for protocol selection, fallback, reconnect, and
    failure messaging where it provides release-quality evidence.
  - Keep UI certification follow-ups separate from already completed runtime
    dataplane certification sections.
- Optional stricter runtime evidence improvements:
  - Improve reconnect-cycle proof, route/DNS/kill-switch evidence, cleanup
    evidence, and artifact retention without changing current release claims.

**Post-v1 prioritization order:**
1. Preserve the closed Linux v1 gates before promoting deferred work.
2. Harden IKEv2 provisioning/security and automated live multi-protocol CI.
3. Improve packaging, signing, distribution, and runtime evidence controls.
4. Evaluate macOS runtime enablement.
5. Evaluate mobile OpenVPN/IKEv2 expansion.
6. Add optional UI-level certification follow-ups where they reduce release
   risk.

**Suggested primary tool:** Codex App

**Definition of Done:**
- Deferred items are grouped without blocking or broadening v1.
- Future protocol/platform work has clear promotion gates before release scope
  changes.
- Post-v1 claims do not leak into v1 release docs.
- Current public v1 truth remains Linux desktop first and WireGuard primary.

**Verification Checklist:**
- [x] Documentation updated and aligned
- N/A - Required code/config changes landed; Section 9 is backlog
  organization only.
- N/A - Relevant tests passed; Section 9 is documentation-only.
- N/A - Live/manual validation completed; Section 9 does not certify runtime
  behavior.
- [x] No misleading release claims remain in canonical docs
- [x] Remaining risks documented

**Completion Verdict:** Verified complete

**Verification Evidence:**
- `project_plan.md`
- `docs/current_release_status.md`

## Priority Order

Recommended execution order: `1 -> 2 -> 3 -> 4 -> 5 -> 6 -> 7 -> 8`.

All Sections 1 through 8 are verified complete for the current Linux desktop v1
planning truth. Section 9 is verified complete as deferred backlog organization
only.

## Definition of Done for v1

- Linux app is stable through login, account, subscription, connect, disconnect,
  and reconnect flows.
- WireGuard is reliable under real Linux runtime validation.
- OpenVPN is limited to the already certified Linux runtime/helper dataplane
  path unless separately promoted later.
- IKEv2 is not public v1 release-visible.
- No fake-ready protocol is visible.
- Basic recovery and observability are documented.
- Release packaging, checksum verification, setup docs, and support docs are
  ready.

## Maintenance Note

Future work should update this file instead of creating scattered planning docs
whenever possible. Mark sections complete only when the definition of done and
verification checklist are supported by repo evidence.

**Final closeout note:** Sections 1 through 9 now establish the canonical
planning truth for the current public v1 decision: Linux desktop only,
WireGuard primary, OpenVPN limited to the certified Linux runtime/helper
dataplane evidence unless separately promoted, and IKEv2 not
public-release-visible. Section 9 is deferred backlog organization only; later
platform, protocol, CI, packaging, and certification work must be reopened
separately before it can affect release scope.
