# Android VPN Setup (WireGuard)

SecureWave uses the official WireGuard Android library to bring up a real VPN
tunnel. The Flutter MethodChannel drives a foreground `VpnService`, and
`VpnService.prepare()` handles user permission prompts.

## Integration Summary

- MethodChannel: `securewave/vpn` (`isAvailable`, `connect`, `disconnect`)
- Permission: `VpnService.prepare()` via `MainActivity`
- Service: `SecureWaveVpnService` uses `GoBackend` and runs foreground
- Dependency: `com.wireguard.android:tunnel:1.0.20260102`

## Requirements

- Android device or emulator with VPN permission support
- WireGuard config from backend `/api/vpn/config` (or `/api/vpn/allocate`)
- Internet access to reach the WireGuard endpoint

## Verification

1. `cd securewave_app`
2. `flutter pub get`
3. `flutter run -d <android-device-id>`
4. Tap Connect and approve the VPN permission prompt.
5. Confirm the tunnel is up:
   - `adb logcat | rg "SecureWave VPN"`
   - `adb shell dumpsys vpn`

If the permission prompt is denied, Flutter receives
`missing_vpn_permission` and no mock tunnel is used.
