# SecureWave Multi-Protocol Phase 3 Client Report

Date: 2026-02-21
Branch: `release/multiprotocol-live-only`
Scope: Desktop client runtime/connectivity path for WireGuard + OpenVPN + IKEv2/IPsec.

## Summary

This phase removes desktop protocol placeholders and wires protocol-specific native connectors into the live method-channel path for Linux and Windows, with explicit unavailability handling on macOS when required entitlements/signing are missing.

## Platform Status

| Platform | WireGuard | OpenVPN | IKEv2/IPsec | Notes |
|---|---|---|---|---|
| Linux | Implemented | Implemented | Implemented (system-component path) | IKEv2 uses `nmcli` + strongSwan plugin and requires system packages. |
| Windows | Implemented | Implemented | Implemented (EAP-MSCHAPv2 automation) | IKEv2 EAP-TLS is intentionally blocked with actionable error. |
| macOS | Not available in this build | Not available in this build | Not available in this build | Requires signed Network Extension/NEVPNManager entitlements and extension target. |

## Implemented Runtime Paths

### Linux
- WireGuard: existing `wg-quick` + `pkexec` flow retained.
- OpenVPN: `openvpn --config ... --writepid ... --daemon` via `pkexec`.
- IKEv2: NetworkManager strongSwan profile creation/up (`nmcli connection add ... vpn-type strongswan` + `nmcli connection up`) via `pkexec`.
- Capability reporting now includes protocol-specific install/setup hints:
  - `openvpn_install_hint`
  - `ikev2_install_hint`
  - existing elevation hints

### Windows
- WireGuard: existing `wireguard.exe` tunnel-service flow retained.
- OpenVPN:
  - Detects `openvpn.exe` (or `SECUREWAVE_OPENVPN_PATH`).
  - Launches elevated process (`runas`) and waits for `Initialization Sequence Completed` in log.
  - Disconnect terminates managed process / pid fallback.
- IKEv2:
  - Upserts profile via PowerShell `Add-VpnConnection`.
  - Connect/disconnect via `rasdial`.
  - Auth mode supported by automation: `eap-mschapv2`.
- Capability reporting now exposes real `openvpn` + `ikev2` availability and hints.

### macOS
- `securewave/vpn` now returns explicit capability map and protocol-specific `protocol_unavailable` errors.
- No fake connect path remains.
- Status is always honest (`isAvailable=false`, `getStatus=disconnected`).

## Flutter/UI/State Machine Changes

- Protocol capability and selector messaging now uses protocol-specific hints from native layer (`openvpn_install_hint`, `ikev2_install_hint`).
- Home status error surface now provides terminal-state actions:
  - `Retry`
  - `Setup help` (platform/protocol-specific guidance + Settings shortcut)
- Protocol gating tests added for capability matrix behavior.
- State-machine protocol transition tests added:
  - protocol selection honoring
  - unsupported protocol terminal failure
  - timeout terminal failure for non-WireGuard protocol

## Verification Run

### Flutter
- `flutter analyze`: completed with existing informational lint items in unrelated files.
- `flutter test`: passed.

### Backend
- `pytest`: initial host invocation failed due missing global deps.
- `.venv/bin/pytest`: passed (`337 passed, 3 skipped`).

### Desktop Build Checks
- `flutter build linux`: passed.
- `flutter build windows`: not runnable on Linux host (`only supported on Windows hosts`).
- `flutter build macos`: not runnable on Linux host (`subcommand unavailable on this host/toolchain`).

### Mock/Demo Flag Sweep
- Grep run for demo/mock/simulate flags in runtime paths.
- No active demo/simulate tunnel flags found in desktop runtime code paths.

## Remaining Constraints / Risks

1. Windows IKEv2 automation currently supports `eap-mschapv2` only; backend `eap-tls` profiles are rejected with actionable error.
2. Linux IKEv2 depends on host packages (`network-manager-strongswan`, `strongswan`, `nmcli`) and root-elevation path.
3. macOS remains unavailable until signed Network Extension integration is added (explicitly surfaced, not hidden/faked).
4. Windows/macOS native build compilation could not be executed from this Linux environment.

## Files Added/Updated (phase-3 scope)

- `securewave_app/linux/runner/my_application.cc`
- `securewave_app/windows/runner/flutter_window.cpp`
- `securewave_app/macos/Runner/AppDelegate.swift`
- `securewave_app/lib/core/services/vpn_service.dart`
- `securewave_app/lib/core/services/protocol_selector.dart`
- `securewave_app/lib/core/vpn/protocol_capabilities.dart`
- `securewave_app/lib/screens/home/widgets/status_display.dart`
- `securewave_app/lib/ui/widgets/platform_notice.dart`
- `securewave_app/LINUX_VPN_SETUP.md`
- `securewave_app/WINDOWS_VPN_SETUP.md`
- `securewave_app/MACOS_VPN_SETUP.md`
- `securewave_app/test/protocol_capability_matrix_test.dart`
- `securewave_app/test/state_machine/protocol_transition_test.dart`
- `securewave_app/test/state_machine/state_machine_test_harness.dart`
- `securewave_app/test/protocol_selector_test.dart`

## Verification Refresh (2026-02-22)
This branch already contained the Phase 3 desktop client implementation. This run revalidated the desktop protocol runtime wiring and recorded current Flutter/build evidence.

Commands executed:
- `cd securewave_app && flutter analyze`
- `cd securewave_app && flutter test`
- `cd securewave_app && flutter build linux`
- `cd securewave_app && flutter build windows`
- `cd securewave_app && flutter build macos`

Results:
- `flutter analyze`: completed with lint/info-only findings in unrelated UI/test files (no new compile errors).
- `flutter test`: passed (`All tests passed`).
- `flutter build linux`: passed (`build/linux/arm64/release/bundle/securewave_app`).
- `flutter build windows`: not runnable on this host (`"build windows" only supported on Windows hosts.`).
- `flutter build macos`: not runnable from this Linux toolchain (`Could not find a subcommand named "macos" for "flutter build".`).
