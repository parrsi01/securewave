# Linux Client Bridge Validation Report (2026-02-27)

## Scope
- Native runner: `securewave_app/linux/runner/my_application.cc`
- Flutter bridge: `securewave_app/lib/core/services/vpn_service.dart`
- Protocol selector audit: `securewave_app/lib/core/services/protocol_selector.dart`

## Goals Verified
1. WireGuard
- Stale `sw-wg` cleanup remains scoped and safe (`wg_preflight_cleanup` only touches SecureWave-owned interface/rules/table).
- Duplicate interface risk reduced via preflight teardown + bridge pre-connect status sync.
- Policy route/rule cleanup retained and now validated on connect (route or table `51820` rule expected).
- Reconnect race reduced by bridge-side status sync before connect.

2. OpenVPN
- Runtime detection still explicit (`openvpn` binary check in capabilities/connect path).
- Elevation enforced for connect/disconnect.
- Clear error path preserved when runtime/elevation missing.
- Silent-daemon failure mitigated by post-connect sanity (PID + `tun0` + route required).

3. IKEv2
- Auth mode compatibility enforced (`eap-mschapv2` only for Linux automation path).
- `nmcli` automation path kept and now post-validated (`nmcli` active + interface sanity).
- Disconnect cleanup strengthened: `nmcli connection down` followed by `nmcli connection delete` (ignoring unknown profile only).

4. Post-connect sanity checks (fail-fast)
- WireGuard: interface + route/policy rule validation.
- OpenVPN: daemon PID alive + interface + route validation.
- IKEv2: active NetworkManager connection + interface validation (route-or-policy semantics for IPsec paths).

## Code Changes
### `securewave_app/linux/runner/my_application.cc`
- Added runtime verification helpers:
  - `verify_wireguard_runtime`
  - `verify_openvpn_runtime`
  - `verify_ikev2_runtime`
  - `refresh_runtime_connection_state`
- Added command helpers for route/rule/activity checks.
- `getStatus` now refreshes from real runtime state (WG/OVPN/IKEv2), not only cached flag.
- `getTrafficStats` now refreshes runtime state before reporting.
- WireGuard async connect now enforces sanity check before returning success.
- OpenVPN connect now fails fast if daemon launches but tunnel never becomes operational.
- IKEv2 connect now fails fast if NM activation/interface sanity is not met.
- OpenVPN disconnect now removes stale PID file after successful stop.
- IKEv2 disconnect now removes NM connection profile after down.

### `securewave_app/lib/core/services/vpn_service.dart`
- Added pre-connect `refreshStatus()` sync in non-sim mode to prevent duplicate connect attempts when native tunnel is already up.
- Added Linux post-connect bridge validation (`getStatus == connected`) to fail fast if native runtime did not establish an active tunnel.

### `securewave_app/lib/core/services/protocol_selector.dart`
- Audited for protocol-selection behavior; no functional changes required.

## Regression Tests Added
- `securewave_app/test/channel_vpn_service_linux_bridge_test.dart`
  - `recovers status after native crash mid-session`
  - `avoids duplicate connect when native tunnel is already up`
  - `supports reconnect and protocol switching sequence`

## Commands Run
```bash
cd /home/sp/cyber-course/projects/securewave/securewave_app
flutter test test/channel_vpn_service_linux_bridge_test.dart test/protocol_selector_test.dart
flutter build linux --debug
```

## Results
- Flutter tests: PASS
- Linux desktop build (native runner compile): PASS

## Notes
- No simulation mode changes were made.
- No UI changes were made.
- Protocol selector was reviewed; behavior already aligned with deterministic selection/error rules.
