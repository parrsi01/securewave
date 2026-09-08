# SecureWave - Current Release Status

Verified snapshot: 2026-09-08 UTC. This is a dated observation, not continuous
monitoring. GitHub, production identity, and public package bytes were checked
independently.

## Project and app

SecureWave combines FastAPI, PostgreSQL, Flutter, a static website, and Hetzner
deployment tooling. The release target is the Ubuntu 24.04 ARM64 WireGuard Beta.
The client implements Home, Account, and Diagnostics surfaces, authentication,
session handling, connection controls, usage, and visible error states.
Implementation and CI do not establish installed-product acceptance.

OpenVPN and IKEv2 are outside this Beta scope. Payment integrations and other
platform source code do not establish public runtime readiness.

## Production and GitHub

- Remote `master` and [public version](https://api.securewaveapp.com/version)
  identify `f6c1ee143a794bb99c7e31cbc23d1661d5593287`, version `4.0.0+10`.
- [Health](https://api.securewaveapp.com/api/health) returned success;
  [readiness](https://api.securewaveapp.com/api/ready) reported database connected.
- [Downloads API](https://api.securewaveapp.com/api/downloads) returned the catalog.
  The public homepage returned HTTP 200.
- GitHub CI and Deploy Production succeeded for this revision on September 6.
  Native deployment is defined in `.github/workflows/deploy-production.yml`.
- PRs [#98](https://github.com/parrsi01/securewave/pull/98) and
  [#99](https://github.com/parrsi01/securewave/pull/99) restored email verification
  and fixed retry visibility. The [page](https://securewaveapp.com/verify-email)
  returned HTTP 200 with `no-store` and `no-referrer` headers.

Earlier pending-deployment and downloads-404 statements are superseded. Their
investigation is preserved in [historical evidence](release_status_20260830_historical.md).

## Public ARM64 package

| Field | Verified value |
| --- | --- |
| Filename | `securewave-vpn_4.0.0+10_arm64.deb` |
| Package/version/architecture | `securewave-vpn` / `4.0.0+10` / `arm64` |
| Downloaded SHA-256 | `749e8c4e37fea27023d9030181e5cc36c46ff2e5d60e00519fa16082853d540a` |
| Embedded source SHA | `a4fcf9419d98d6b4fd78e8806993fb499ac408a7` |
| Embedded source state | `clean` |
| Helper contract | `13` |

Downloaded bytes match the public catalog checksum. Backend and client revisions
are independent; differing SHAs alone are not a defect. Exact-source release
gates must compare the client against its explicitly approved revision.

The catalog also advertises a Linux x64 tarball and macOS ARM64 UI demo; their
bytes and runtime were not checked here. Linux x64 `.deb`/AppImage, Windows,
Android, and iOS distribution remain `coming_soon`. The Apple handoff kit is
packaging support, not a signed VPN app.

## Remaining acceptance

1. Verify actual email delivery and the existing verification-to-login flow.
   SMTP and receiving-mailbox acceptance were not tested in this snapshot.
2. Complete installation, GUI launch, registration/login, WireGuard connect,
   routed egress, disconnect cleanup, reconnect/session restoration, and logout
   using the public package on an authorized Ubuntu 24.04 ARM64 desktop.
3. Record the approved client revision, downloaded checksum, test environment,
   and acceptance evidence together before declaring the Beta accepted.

Earlier session evidence recorded successful installation/helper checks, but
acceptance stopped before GUI/authenticated VPN because the test container
lacked a graphical session/polkit agent and usable WireGuard interface capability.
Those conditions were not rechecked on September 8. No fresh GUI, SMTP, tunnel,
or payment acceptance is claimed here.

## Concurrent Linux and Mac work

Use a unique branch and isolated checkout per session, based on freshly fetched
`origin/master`. Inspect remote changes and open PRs before selecting overlapping
files. Publish explicit paths and document touched files and validation in the PR.
Recheck the base before integration and coordinate overlapping changes in review.
Do not reset, clean, force-push, or reuse another session's branch/worktree.
Unpushed Mac changes are invisible from Linux; remote inspection cannot prove a
file is unowned. A documentation PR does not certify or deploy the application.
