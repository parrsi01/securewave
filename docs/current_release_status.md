# SecureWave — Current Release Status

## Canonical v1 Release Statement

SecureWave is currently a Linux desktop first app. WireGuard is the primary and
most stable runtime path. OpenVPN is enabled only when the backend issues a real
OpenVPN profile and the Linux helper confirms startup. IKEv2 is enabled only
when the backend issues an app-consumable Linux IKEv2 profile and strongSwan
start/status/cleanup are verified.

Only protocols proven end-to-end through the normal backend and client path
should be called release-ready. The client must show backend/native errors
instead of substituting fake connected states.

## Current Stable Release

- Version: `4.0.0+2`
- Platform: Linux
- Status: Fresh Flutter UI is organized across `Linux`, `Windows`, and `Mac`
  branches, with `master` kept as the hub. Linux/WireGuard remains
  the strongest runtime path. Apple packaging is prepared for Mac/Xcode
  finalization but is not yet runtime-certified through App Store review.
- Latest manual runtime check: on `2026-07-01`, the Linux Flutter app connected
  through the real WireGuard path, public egress was verified on a "test my IP"
  site, and the in-app data usage gauge updated correctly during the session.

## Release-Ready

- Login/register against the live API with visible errors
- Session restore/logout/re-login flow in the Flutter client
- Account email shown after startup/login
- Server catalog loading with empty/error states
- Usage gauge on Connect, Account, and Settings screens, with live WireGuard
  transfer usage correctly reflected in the app
- Native Linux single-instance window lifecycle
- Domain/TLS correctness for `https://api.securewaveapp.com/api/health`

## Limited / Non-Public Release Evidence

- OpenVPN profile issuance works on the live API for the verified Hetzner node;
  full app connect still depends on local OpenVPN installation and privileges.
- IKEv2 is selectable when the backend returns complete IKEv2 metadata and the
  Linux host has strongSwan `swanctl`/`ipsec` tooling installed.
- The live backend smoke now requires all three Linux protocols to be enabled,
  advertised by server inventory, and backed by app-consumable profile payloads.
- The iOS project now uses production-style bundle identifiers
  `com.securewave.vpn` and `com.securewave.vpn.PacketTunnel`, with the Packet
  Tunnel Provider Network Extension entitlement. A signed iOS archive/export
  still must be produced on macOS with Xcode and Apple signing assets.
- The Apple Silicon macOS Flutter target is published as a
  website-downloadable UI/account demo zip at
  `static/downloads/securewave-macos-arm64-ui-demo.zip`. macOS VPN tunneling is
  still not enabled; connect/disconnect returns `vpn_not_configured` until a
  macOS Network Extension target exists.

## Apple Release Packaging Handoff

- SecureWave's Apple VPN path is NetworkExtension Packet Tunnel Provider, not
  Hotspot Helper.
- Public Apple reviewer support content is available at
  `static/apple-review.html`, with links to privacy, terms, support, and
  downloads.
- The public download manifest is `static/downloads/manifest.json`; the Apple
  handoff download is `static/downloads/securewave-apple-release-handoff.zip`.
- The Apple Silicon macOS UI demo package is available as
  `static/downloads/securewave-macos-arm64-ui-demo.zip`; the Intel macOS demo
  slot remains `coming_soon` until an Intel Mac or matching runner publishes
  `securewave-macos-x64-ui-demo.zip`.
- GitHub Actions run `28514166181` on `2026-07-01` passed unsigned iOS release
  validation, unsigned `.app` artifact collection/upload, macOS UI demo
  build/upload, and macOS demo branch publishing on the former `flutter`
  branch. Current Apple work should use the `Mac` branch.
- Local Mac archive/export command:

```bash
export APPLE_TEAM_ID="<team-id>"
bash securewave_app/scripts/archive_ios_release.sh
```

- Local Mac website demo package command:

```bash
bash securewave_app/scripts/package_macos_ui_demo.sh
```

- GitHub Actions can run unsigned iOS validation by default and signed
  archive/export when manually dispatched with Apple signing secrets. As of
  `2026-07-01`, the repository only exposes `AZURE_CREDENTIALS` through
  `gh secret list`, so signed iOS export remains blocked until Apple signing
  secrets are configured or the archive is produced locally on a Mac.
- Local Mac release-signing diagnostics on `2026-07-02` reached the signing
  checks successfully and found a development identity only, no `APPLE_TEAM_ID`,
  and no provisioning profile directory. See
  `docs/DEVOPS_REPORT_APPLE_SIGNING_READINESS_2026-07-02.md`.
- GitHub Actions can build the macOS UI demo on a macOS runner and optionally
  publish the generated zip back to the branch with
  `publish_macos_demo=true`.

## Public Promotion Gated

- The live backend currently suppresses synthetic region aliases that point at
  the same Hetzner IP. Public catalog count should reflect verified inventory,
  not placeholder region names.
- IKEv2 public promotion depends on live profile provisioning plus strongSwan
  start/status verification and cleanup evidence.

## Experimental / Manual

- IKEv2 may be kept experimental/manual outside the Linux release app unless
  hardened enough for release.

## Post-v1

These items are deferred backlog only. They do not change the public v1 release
scope, platform support, protocol visibility, packaging behavior, or release
readiness claims.

- macOS runtime enablement, including a separate signed macOS Network Extension
  target if macOS VPN support is promoted beyond the iOS handoff path.
- Mobile OpenVPN/IKEv2 expansion after platform-specific evidence exists.
- Automated live multi-protocol CI with controlled test infrastructure.
- IKEv2 hardening, including provisioning, packaging, and EAP-TLS evaluation.
- Stronger packaging, signing, distribution, and artifact controls.
- Optional UI-level certification follow-ups for protocol and failure flows.
- Optional stricter runtime evidence improvements.

## Branch Model Summary

- `master` -> hub for backend, docs, infra, app runtime truth, and release logistics
- `Linux` -> Linux desktop release candidate and live tunnel proof work
- `Windows` -> Windows app and packaging work
- `Mac` -> macOS/iOS Apple packaging, signing, and review work

## Contributor Rules

- Do not claim protocol readiness without normal backend + client-path proof.
- Do not turn synthetic region aliases into public regions unless they are
  explicitly labeled as placeholders or backed by real infrastructure.
- Do not expose OpenVPN or IKEv2 as default-visible release protocols unless
  they are proven through the normal backend and client path.

## Quick Verification Commands

```bash
curl -fsS https://api.securewaveapp.com/api/health

curl -fsS https://api.securewaveapp.com/api/downloads

python3 scripts/live_flutter_runtime_smoke.py --profile-repeats 3

curl -fLo /tmp/securewave-linux-arm64-4.0.0-2.deb \
  https://securewaveapp.com/downloads/securewave-linux-arm64-4.0.0-2.deb

echo "7c2301ce2353d8d3a1a135413a4cb8ec5574ccbf8e59a790612397a0782572ff  /tmp/securewave-linux-arm64-4.0.0-2.deb" | sha256sum -c -

cd securewave_app && flutter analyze && flutter test

cd securewave_app && flutter test integration_test/session_lifecycle_test.dart -d linux --reporter expanded
```
