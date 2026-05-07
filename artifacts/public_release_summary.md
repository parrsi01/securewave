# SecureWave Linux Free Release Candidate Summary

## Current Public Scope

SecureWave is preparing a Linux desktop free release candidate for public testing. The current public v1 scope is Linux desktop only, with WireGuard as the primary VPN protocol.

The release candidate is grounded in the current Linux/WireGuard release path documented in `docs/current_release_status.md` and the Linux runtime setup in `securewave_app/LINUX_VPN_SETUP.md`.

## What Users Can Test Now

- Linux desktop client release-candidate flow.
- WireGuard-based VPN connection through the Linux `wg-quick` runtime path.
- Account sign-in and authenticated VPN profile retrieval.
- Protocol-aware connection readiness.
- Usage accounting under the current free mode.
- Disconnect, cleanup, and reconnect behavior.
- Linux release artifact verification using the documented checksum process.

## What Is Coming Later

- Premium plan availability and paid account flows after the production billing launch is ready to promote.
- Broader protocol exposure only after each protocol has matching backend, client-path, runtime, packaging, and validation evidence.
- Windows, macOS, iOS, and Android VPN runtime support after platform-specific release gates are complete.
- IKEv2 public visibility only after provisioning and security hardening are complete and the release decision is reopened.

## Protocol Positioning

WireGuard is the primary public release protocol for Linux v1.

OpenVPN is not being broadly promoted for public v1. It remains limited to the already certified covered Linux runtime/helper dataplane path unless separately promoted later through normal certification.

IKEv2 is not public v1 release-visible.

## Public Claim Boundaries

SecureWave should not be described as a production-scale SaaS, multi-platform VPN, or paid subscription product currently live unless separate release evidence exists. Public messaging should describe the current truth: Linux desktop free release candidate now, Premium coming soon, and additional platforms/protocols gated by future validation.
