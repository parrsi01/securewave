# UI-only handoff after 4.0.0+11

The user confirmed the installed SecureWave app is fully functional on
2026-10-04. Save this release as the behavior baseline before visual work.
The user will provide a separate prompt for the next changes.

## Intended scope

Change visual presentation: colors, typography, spacing, alignment, icons,
assets, and screen/control styling. Follow the user's upcoming design prompt.
Keep the existing website black/blue visual system unless that prompt changes
it. Do not start redesign work while publishing this baseline.

## Preserve

- Production API host and request shapes: email/password registration,
  login, authenticated `/auth/me`, and client-public-key `/vpn/config`.
- Correct handling of duplicate accounts, rejected credentials, and expired
  sessions; expired users return to Sign in.
- Secure storage of access tokens and per-account WireGuard identity.
- Client-generated private keys remaining local and public keys sent to the API.
- Helper contract 14 and the socket/allowlist privilege boundary.
- Real Connect, Disconnect, Reconnect, peer/handshake checks, routing, DNS,
  egress verification, cleanup, and RX/TX usage accounting.
- Installed desktop integration and the package's end-user runtime requirements.
- Production database, server peers, infrastructure, and secrets.

Changes to auth, backend architecture, VPN protocols, dependencies, or runtime
behavior need a concrete defect and separate scope. Preserve all protected
historical artifacts and the pre-existing untracked mobile directories.

## Handoff checks

Review diffs for accidental functional changes, run Flutter analysis and
relevant regression tests, and verify the rebuilt installed app. Record GUI
evidence separately from API/unit tests. The outstanding independent reboot
acceptance must not be silently described as completed.
