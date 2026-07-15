# Blocked and excluded boundaries

## Current host blockers

- The rebuilt ARM64 package is not installed over the existing host package, so
  clean install, upgrade, and purge evidence for this exact package is not
  claimed.
- The current host's existing helper/service/socket are contract 13 and pass the
  read-only verifier, but that is not proof for the rebuilt package payload.
- No current authorized staging credentials or infrastructure target was
  supplied. WireGuard live route/DNS/exit-IP/data-plane proof was not run.
- The master backend intentionally refuses Linux IKEv2 profiles, so the app
  keeps IKEv2 unavailable even when local strongSwan tools are installed.
- The backend-generated OpenVPN profile includes an authentication directive,
  but the current client/profile contract does not supply a separate credential
  file. The deployed server authentication mode was not inspected or changed;
  authorized live proof is required before claiming OpenVPN readiness.
- The host is ARM64. No local x64 build/install/runtime claim is made.
- Android debug build is blocked locally because Java/JAVA_HOME is unavailable;
  this is not reported as Android build proof.

## Platform blockers

- An exact-head x64 workflow artifact and a clean x86_64 systemd VM lifecycle
  proof are required before x64 availability can change.
- Windows x64 build/install/service/routing evidence requires Windows.
- Windows ARM64 has no certified target.
- macOS has no native Network Extension provider; all VPN protocols are
  intentionally unavailable.
- Signing/certification and artifact publication were excluded.

No unavailable tool or blocked runtime boundary is reported as passing.
