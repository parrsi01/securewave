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

## Release Signing (required for --release)

SecureWave release builds require a dedicated keystore. Do not commit keystores
or `key.properties` to git.

1. Create a keystore (once):
   ```bash
   keytool -genkey -v -keystore securewave-release.jks \
     -alias securewave -keyalg RSA -keysize 2048 -validity 10000
   ```
2. Create `securewave_app/android/key.properties`:
   ```properties
   storeFile=securewave-release.jks
   storePassword=<keystore-password>
   keyAlias=securewave
   keyPassword=<key-password>
   ```
3. Or provide environment variables instead of `key.properties`:
   - `ANDROID_KEYSTORE_PATH`
   - `ANDROID_KEYSTORE_PASSWORD`
   - `ANDROID_KEY_ALIAS`
   - `ANDROID_KEY_PASSWORD`

Release guardrails in Gradle will fail the build if signing is missing.

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
