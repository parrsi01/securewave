# Android VPN Setup (Native Integration)

SecureWave includes a placeholder VpnService and MethodChannel bridge. To enable
real WireGuard tunnels on Android, you must add a WireGuard backend.

## Steps

1. Open `securewave_app/android` in Android Studio.
2. Add a WireGuard backend dependency (wireguard-go or official library).
3. Update `SecureWaveVpnService` to:
   - Parse the WireGuard config string.
   - Start the tunnel via the backend.
   - Report status back to Flutter (optional).
4. Request VPN permission using `VpnService.prepare()` before starting.

## Current Bridge

Flutter calls the `securewave/vpn` channel. Android receives:
- `connect` with `config`
- `disconnect`

The service currently starts a foreground notification and exits.
