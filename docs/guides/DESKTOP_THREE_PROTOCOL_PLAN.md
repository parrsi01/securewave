# SecureWave Desktop Three-Protocol Plan

## Current Scope Note

This document describes the broader desktop multi-protocol target. It does not
override the active SecureWave v1 release scope. For v1, SecureWave is Linux
desktop first with WireGuard primary; OpenVPN is limited to the already
certified Linux runtime/helper dataplane path unless separately promoted after
normal backend/client-path certification; IKEv2 is experimental/manual or hidden
unless hardened; Windows, macOS, iOS, and Android runtime work is post-v1.

The desktop three-protocol target is post-v1 backlog only until each platform
and protocol has release-grade backend, runtime, packaging, and validation
evidence. It must not be used to broaden public v1 support claims.

## Summary
- Post-v1 target: evaluate `WireGuard`, `OpenVPN`, and `IKEv2` across desktop:
  Linux, Windows, and macOS.
- Keep `WireGuard` as the default protocol everywhere for speed, stability, privacy, and live-stream resilience.
- Treat `OpenVPN` as the compatibility and restrictive-network fallback.
- Treat `IKEv2` as the fast-reconnect and OS-native-stack fallback.
- Use runtime readiness gating so a protocol can be part of the desktop product without pretending it is always packaged and healthy on every build.

## Product Strategy
- Primary/default protocol:
  - `WireGuard` on Linux, Windows, macOS
- Fallback protocols:
  - `OpenVPN` for blocked/restrictive networks, TCP fallback, and legacy compatibility
  - `IKEv2` for fast reconnect and native stack integration
- Do not present all three as equally recommended in the UI.
- Let backend support, native runtime readiness, and per-build packaging state determine whether a protocol is currently connectable.

## Desktop Target Matrix
- `Linux`
  - Product target: `WireGuard + OpenVPN + IKEv2`
  - Initial confidence order: `WireGuard`, then `OpenVPN`, then `IKEv2`
- `Windows`
  - Product target: `WireGuard + OpenVPN + IKEv2`
  - Initial confidence order: `WireGuard`, then `OpenVPN`, then `IKEv2`
- `macOS`
  - Product target: `WireGuard + OpenVPN + IKEv2`
  - Initial confidence order: `WireGuard`, then `IKEv2`, then `OpenVPN`

## Implementation Changes
- App/runtime gating:
  - In post-v1 work, enable additional desktop protocol flags only after the
    target platform has release-grade runtime and packaging evidence.
  - Preserve native capability checks so unavailable runtimes surface as explicit reasons instead of fake support.
  - Preserve backend protocol catalog gating from `/api/vpn/protocols`.
- Protocol ordering and fallback:
  - Keep automatic selection order anchored on `WireGuard`.
  - Use `OpenVPN` as the first general fallback if `WireGuard` is unavailable.
  - Use `IKEv2` when it is the only remaining healthy runtime or proves better for a specific OS/runtime case.
- Backend/control plane:
  - Keep strict server-material validation for `OpenVPN` and `IKEv2`.
  - Ensure protocol catalog and profile issuance stay authoritative.
- UX and automation:
  - Adapt automation surfaces to the current Flutter redesign.
  - Do not revert or reshape Claude’s UI to satisfy older tests.

## Test Plan
- Feature-flag tests:
  - Post-v1 Linux, Windows, and macOS flags expose only protocols with matching
    runtime and packaging evidence.
  - iOS/Android remain independently gated by current mobile policy.
- Capability matrix tests:
  - Desktop platforms can declare all three protocols.
  - Missing runtime produces explicit unavailable reasons, not “not supported on this platform.”
- Backend profile tests:
  - `WireGuard`, `OpenVPN`, and `IKEv2` profile issuance stay typed and validated.
  - Misconfigured `OpenVPN` and `IKEv2` remain blocked with specific error codes.
- Live/E2E tests:
  - Keep one live path per protocol per OS as the eventual target.
  - Prioritize Linux `WireGuard/OpenVPN/IKEv2` runtime readiness first, then Windows and macOS parity.

## Assumptions
- For this post-v1 plan, “all three must work” means the future desktop product
  must support and expose all three protocols only after each platform-specific
  runtime is proven.
- Runtime readiness can still vary by build, entitlement state, or missing local dependencies; unsupported runtime must be surfaced clearly.
- `WireGuard` remains the only recommended default for streaming stability, privacy, and speed.
- `OpenVPN` and `IKEv2` are strategic fallbacks, not equal defaults.
