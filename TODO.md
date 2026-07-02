# SecureWave Codex TODO

Canonical sources: `docs/current_release_status.md`,
`docs/CODEX_PLAN_LIVE_PRODUCTION_READINESS.md`, and
`docs/CODEX_PLAN_SMTP_EMAIL.md`.

## In Progress

- [x] Pull latest repository changes from `origin/flutter`.
- [x] Preserve current single-file Flutter app architecture after the pull.
- [x] Add app-visible platform/runtime release truth so non-Linux builds cannot
  overstate VPN readiness.
- [x] Run the Flutter analyzer and focused UI tests after conflict resolution.
- [x] Add P0 regression guards for the Linux `.deb` helper, polkit rule,
  postinst install path, and helper-scoped runtime documentation.
- [x] Confirm `scripts/demo_preflight.sh --live-go-no-go` source coverage for
  P0/P1/P2/P3 checks and guard it with DevOps contract tests.
- [x] Confirm P2 synthetic-bootstrap inventory filtering is covered by unit
  tests.
- [x] Confirm P3 email verification, password reset, provider config, and
  release-gate source coverage with focused pytest tests.
- [x] Confirm P5 billing source coverage for production Stripe config, checkout,
  webhook sync, portal configuration, and private env provisioning.
- [x] Confirm P4 source coverage for reconnect state, device-limit messaging,
  stale-device recovery, disconnect ordering, and backend device/profile flows.

## Remaining Product Features And Release Blockers

- [x] P0 source/package guard: the Linux `.deb` package path installs
  `securewave_app/packaging/linux/50-securewave-wg.rules`, substitutes the
  allowed user, sets mode `0644`, reloads polkit when available, and removes
  the rule on uninstall.
- [ ] P0 live host proof: install the current `.deb` on a clean Linux host and
  verify prompt-free real WireGuard connect/disconnect for an authorized
  sudo-group user.
- [ ] P1: Prove real tunnel egress and DNS correctness through the Hetzner VPN
  node while connected: live API health succeeds, DNS resolves, and public
  egress IP shifts to the VPN node.
- [x] P2 source guard: synthetic bootstrap region aliases that share one public
  IP are suppressed outside testing unless explicitly exposed.
- [ ] P2 live catalog proof: with live credentials, confirm
  `/vpn/servers?device_type=linux` returns real, connectable, deduplicated
  regions and never returns an empty catalog during the release window.
- [x] P3 source/test guard: email verification, password reset, provider config,
  `/api/health/email`, and release gate behavior are covered with mocked
  outbound mail transport.
- [ ] P3 live provider proof: provision production SMTP/SendGrid/SES credentials,
  confirm `/api/health/email` reports `ok`, complete register -> verify against
  a real inbox, and complete password reset end to end.
- [x] P4 source/test guard: Flutter state and backend profile/device tests cover
  reconnect state, stale-device recovery, actionable device-limit errors,
  disconnect ordering, usage reporting, and device/profile endpoints.
- [ ] P4 live host proof: validate real-tunnel reconnect after network loss,
  device revoke from a real capped account, and cleanup after abnormal app exit
  on a Linux host.
- [x] P5 source/test guard: production Stripe config, no demo fallback in
  production, checkout session creation, webhook subscription sync, billing
  portal configuration, and private env provisioning are covered.
- [ ] P5 live billing proof: provision live Stripe/PayPal credentials, run the
  billing release gate against live-mode keys, and verify app plan/usage matches
  backend subscription truth.
- [x] P6 source/contract guard: `scripts/demo_preflight.sh --live-go-no-go`
  covers polkit, tunnel egress, inventory, email health, and build readiness.
- [ ] P6 live execution proof: run `scripts/demo_preflight.sh --live-go-no-go`
  on a connected Linux host with live credentials and attach the pass/fail
  evidence to the release handoff.
- [ ] Apple release: Add Apple signing secrets to GitHub or run
  `securewave_app/scripts/archive_ios_release.sh` locally on macOS with the
  required Apple signing assets to produce the final signed iOS archive/export.
- [ ] Apple review: Create the App Store reviewer account after SMTP is live;
  do not submit placeholder review credentials.
- [ ] Apple entitlement: If App Store Connect asks for entitlement
  justification again, request NetworkExtension Packet Tunnel Provider only,
  not Hotspot Helper.
- [ ] macOS downloads: Produce and publish the Intel macOS UI demo zip if Intel
  Mac download support is required. The Apple Silicon macOS UI demo zip is
  already published.

## Deferred Post-v1 Backlog

- [ ] macOS VPN runtime enablement with a signed macOS Network Extension target.
- [ ] Mobile OpenVPN/IKEv2 expansion after platform-specific evidence exists.
- [ ] Automated live multi-protocol CI backed by controlled test infrastructure.
- [ ] IKEv2 hardening, including provisioning, packaging, and EAP-TLS review.
- [ ] Stronger packaging, signing, distribution, and artifact controls.
