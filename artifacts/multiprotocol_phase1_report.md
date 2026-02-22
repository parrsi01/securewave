# SecureWave Multiprotocol Phase 1 Report

Date: 2026-02-21  
Branch: `release/multiprotocol-live-only`

## Scope
This phase converts control-plane and app protocol selection from WireGuard-only placeholders to live-only protocol-aware behavior with explicit support paths for:
- WireGuard (implemented)
- OpenVPN (profile generation + backend contract implemented)
- IKEv2/IPsec (profile generation + backend contract implemented)

Explicitly **not implemented in this phase**:
- Shadowsocks
- SOCKS5 proxy mode

Both were removed from app protocol UI paths/config enums so the app does not advertise unsupported modes.

## A) Capability Matrix (Single Source of Truth)
Created:
- `securewave_app/lib/core/vpn/protocol_capabilities.dart`

What it provides:
- Per-platform protocol declarations
- Per-protocol requirements metadata
- Runtime availability evaluation that combines:
  - platform declaration
  - backend-enabled catalog (`/api/vpn/protocols`)
  - native runtime capability detection (`getCapabilities`)
- Explicit unavailable reasons (including macOS entitlement/runtime readiness messaging)

Protocol interface added:
- `securewave_app/lib/core/vpn/vpn_protocol_driver.dart`

## B) Protocol-Aware Backend API Contract
Updated:
- `routes/vpn.py`
- `docs/openapi/securewave-openapi.json`
- `docs/vpn_profile_schema.md`

### `/api/vpn/profile`
Now returns protocol-specific payloads:
- WireGuard: `profile.type = wireguard`, `wireguard_config`
- OpenVPN: `profile.type = openvpn`, `ovpn_config`, `username`, `password`
- IKEv2: `profile.type = ikev2`, `server`, `remote_id`, `username`, `password`, optional `ca_cert_pem`

Input hardening:
- strict `device_type` validation
- strict explicit protocol validation (no silent fallback)

Typed protocol errors added/used:
- `unsupported_protocol`
- `protocol_not_supported_on_platform`
- `protocol_not_supported_on_server`
- `protocol_plan_restricted`
- `protocol_disabled_server_side`
- `protocol_temporarily_unavailable`
- `no_protocol_available`

### `/api/vpn/protocols`
Added endpoint returning protocol availability matrix per user/device context:
- server policy enabled
- plan enabled
- platform supported
- active fleet support
- protocol requirements
- reason codes when unavailable

## C) DNS / Kill-Switch Truth Model
Implemented in `routes/vpn.py`:

Server-side response truthfulness by protocol:
- WireGuard/OpenVPN:
  - DNS list included (from `SECUREWAVE_TUNNEL_DNS` or secure default)
  - `ad_malware_blocking = on`
  - `enforcement = config`
- IKEv2:
  - no claimed DNS enforcement (`servers = []`, `ad_malware_blocking = off`, `enforcement = none`)

Kill switch claims now protocol/platform-scoped:
- Linux + WireGuard only:
  - `mode = enabled`
  - `enforcement = wg-quick hooks`
- all other protocol/platform combinations:
  - `mode = disabled`
  - `enforcement = none`
  - explicit note to rely on OS always-on controls where available

## D) UI Placeholder Removal / Availability-Only Rendering
Updated:
- `securewave_app/lib/core/models/vpn_protocol.dart`
- `securewave_app/lib/core/services/vpn_service.dart`
- `securewave_app/lib/core/services/protocol_selector.dart`
- `securewave_app/lib/core/state/app_state.dart`
- `securewave_app/lib/core/state/vpn_state.dart`
- `securewave_app/lib/services/api_client.dart`
- `securewave_app/lib/screens/settings/settings_screen.dart`
- `securewave_app/lib/core/models/vpn_protocol_catalog.dart`

Behavior:
- Removed protocol placeholders from app enum/config:
  - L2TP
  - Shadowsocks
  - TCP fallback/QUIC placeholders
- Added backend protocol catalog fetch (`/vpn/protocols`)
- Settings protocol selector now renders only protocols with all checks true:
  - declared for platform
  - backend enabled/allowed
  - native runtime ready
- Removed mock provider path (`MockVpnService`) and demo connect behavior

## Mock/Demo Purge
Removed/disabled in runtime paths:
- `WG_SIMULATE` behavior removed from `services/wireguard_server_manager.py`
- demo docs gate removed from `main.py`
- `MockVpnService` removed from Flutter app runtime and tests updated
- client-side fake throughput generation removed (rates now not fabricated)

## Validation Executed
### Flutter
- `flutter analyze` (completed; informational lints remain in unrelated files)
- `flutter test` (pass)

### Backend
- `./.venv/bin/pytest` (pass: `334 passed, 3 skipped`)

### Grep checks
- `rg -n "DEMO_MODE|DEMO_OK|WG_SIMULATE" -S .` -> no matches
- `rg -n "DEMO_MODE|DEMO_OK|WG_SIMULATE|MockVpnService|mock tunnel|simulate connect|fake success" -S --glob '!securewave_app/ios/ThirdParty/**' .` -> no matches

### OpenAPI
- `./.venv/bin/python scripts/generate_openapi.py`
- Artifact updated: `docs/openapi/securewave-openapi.json`

## Remaining Gaps / Risks
1. Native desktop OpenVPN/IKEv2 tunnel runtime paths are still build/runtime dependent on platform bridge support; protocol selector now hides non-ready protocols instead of claiming support.
2. macOS still depends on entitlements/network extension setup; app now reports explicit unavailable reason when runtime not ready.
3. Vendored third-party iOS upstream code (`securewave_app/ios/ThirdParty/...`) still contains simulator-only mock symbols; app runtime paths do not use mock tunnel providers.
4. Data-plane credential provisioning for OpenVPN/IKEv2 depends on server helper scripts (`securewave-openvpn-upsert-user`, `securewave-ikev2-upsert-user`) being installed on nodes.

## Next Prompt Prerequisites
1. Complete native desktop OpenVPN/IKEv2 runtime integration for Linux/Windows/macOS channel implementations.
2. Enforce production entitlements and packaging checks for macOS NetworkExtension.
3. Add end-to-end live tests that bring up OpenVPN and IKEv2 tunnels on desktop CI runners.
4. Add operational runbooks for protocol-specific rollout/rollback and alerting.

## Change Log
1. What changed:
- Added protocol capability matrix, protocol-aware API endpoints/contracts, strict typed protocol errors, truthful DNS/kill-switch metadata, and availability-only protocol UI rendering.
2. What reused:
- Existing WireGuard peer lifecycle, server allocation, latency optimizer, and app state machine scaffolding.
3. What left untouched:
- Legacy DB columns for non-phase protocols (e.g., L2TP fields) and broader non-VPN product surfaces.
4. Risks introduced:
- More strict explicit protocol validation can surface errors where old behavior silently fell back; clients must handle typed errors correctly.

## Cleanup Update (2026-02-22)
- Removed remaining CI workflow environment references to `DEMO_MODE` and `WG_MOCK_MODE`.
- Renamed demo-labeled integration test file to `tests/integration/test_vpn_session_endpoints.py`.
- Reworded test comments/messages that previously referred to demo/mock behavior; tests now describe test-environment behavior honestly.
