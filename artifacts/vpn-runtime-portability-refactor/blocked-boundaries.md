# Blocked and excluded boundaries

## Current host blockers

- Helper daemon, wrapper, contract, systemd unit, allowlist, and socket are not
  installed.
- `sudo -n` is unavailable, so package install/service/socket proof was not
  attempted.
- The read-only verifier found an unqualified IKEv2 pref-220 routing-loop rule.
  It was not removed because root access is required.
- No authorized live credentials or infrastructure change was available.
  WireGuard, OpenVPN, and IKEv2 live route/DNS/exit-IP/data-plane proof was not
  run.
- The master backend intentionally refuses Linux IKEv2 profiles, so the app
  keeps IKEv2 unavailable even when local strongSwan tools are installed.
- The backend-generated OpenVPN profile includes an authentication directive,
  but the current client/profile contract does not supply a separate credential
  file. The deployed server authentication mode was not inspected or changed;
  authorized live proof is required before claiming OpenVPN readiness.
- The host is ARM64. No local x64 build/install/runtime claim is made.

## Platform blockers

- Historical x64 workflow run `29036573515` and supplied checksum
  `f2718810c7dea6e2c298c159f25d904321423ab3a359c1d1428b3e824d7b4d92`
  predate contract 10. A new reviewed-commit x64 build and clean VM run are
  required.
- Windows x64 build/install/service/routing evidence requires Windows.
- Windows ARM64 has no certified target.
- macOS has no native Network Extension provider; all VPN protocols are
  intentionally unavailable.
- Signing/certification and artifact publication were excluded.

No unavailable tool or blocked runtime boundary is reported as passing.
