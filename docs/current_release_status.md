# SecureWave — Current Release Status

## Canonical v1 Release Statement

SecureWave v1 is a Linux desktop first release with WireGuard as the primary
protocol. OpenVPN is limited to the already certified Linux runtime/helper
dataplane path unless normal backend and Linux client-path certification is
separately proven. IKEv2 is experimental/manual or hidden unless provisioning
and security hardening are complete. Windows, macOS, iOS, and Android VPN
runtime work are out of scope for the public v1 go decision.

Only protocols proven end-to-end through the normal backend and client path
should be visible or enabled by default.

## Current Stable Release

- Version: `4.0.0+2`
- Platform: Linux
- Status: Production-ready for the Linux/WireGuard-primary release path

## Release-Ready

- Login/auth-ready flow
- Protocol-aware connect/readiness
- Usage accounting under live traffic
- Disconnect/cleanup
- Reconnect stability
- Domain/TLS correctness
- API + download endpoints
- Artifact integrity with checksum verification
- Linux/WireGuard is the strongest current release path

## Limited / Non-Public Release Evidence

- OpenVPN Linux runtime/helper dataplane evidence exists, but public fallback
  visibility beyond that covered path requires separate promotion.
- IKEv2 dataplane evidence exists, but it is not public-release-ready.

## Public Promotion Gated

- OpenVPN remains limited to the certified Linux runtime/helper dataplane path
  unless separately promoted.
- IKEv2 remains unavailable for public release until provisioning and security
  hardening are complete and the release decision is reopened.

## Experimental / Manual

- IKEv2 may be kept experimental/manual or hidden unless hardened enough for
  release.

## Post-v1

These items are deferred backlog only. They do not change the public v1 release
scope, platform support, protocol visibility, packaging behavior, or release
readiness claims.

- macOS runtime enablement, including any Network Extension work.
- Mobile OpenVPN/IKEv2 expansion after platform-specific evidence exists.
- Automated live multi-protocol CI with controlled test infrastructure.
- IKEv2 hardening, including provisioning, packaging, and EAP-TLS evaluation.
- Stronger packaging, signing, distribution, and artifact controls.
- Optional UI-level certification follow-ups for protocol and failure flows.
- Optional stricter runtime evidence improvements.

## Branch Model Summary

- `release/linux-4.0.0+2` -> stable release branch
- `develop/protocols-linux` -> Linux protocol work
- `develop/apple-openvpn-runtime` -> Apple runtime work

## Contributor Rules

- No experimental work on `release/linux-4.0.0+2`
- All protocol work must go through the appropriate development branch
- Promotion into a release branch requires the full Linux validation gate
- Do not expose OpenVPN or IKEv2 as default-visible release protocols unless
  they are proven through the normal backend and client path.

## Quick Verification Commands

```bash
curl -fsS https://api.securewaveapp.com/api/health

curl -fsS https://api.securewaveapp.com/api/downloads

curl -fLo /tmp/securewave-linux-arm64-4.0.0-2.deb \
  https://securewaveapp.com/downloads/securewave-linux-arm64-4.0.0-2.deb

echo "7c2301ce2353d8d3a1a135413a4cb8ec5574ccbf8e59a790612397a0782572ff  /tmp/securewave-linux-arm64-4.0.0-2.deb" | sha256sum -c -

cd securewave_app && flutter analyze && flutter test

cd securewave_app && flutter test integration_test/session_lifecycle_test.dart -d linux --reporter expanded
```
