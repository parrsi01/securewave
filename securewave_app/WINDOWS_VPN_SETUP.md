# Windows VPN Setup (WireGuard)

SecureWave uses the official WireGuard for Windows tooling (`wireguard.exe`)
to install and start a tunnel service from a WireGuard config string.

## Integration Summary

- MethodChannel: `securewave/vpn` (`isAvailable`, `connect`, `disconnect`)
- Backend: `wireguard.exe /installtunnelservice` and `/uninstalltunnelservice`
- Config file: `%APPDATA%\SecureWave\SecureWave.conf`
- Optional override: `SECUREWAVE_WIREGUARD_PATH` (full path to `wireguard.exe`)

## Requirements

- WireGuard for Windows installed
- App running with privileges to install the tunnel service
- WireGuard config from backend `/api/vpn/config` (or `/api/vpn/allocate`)

## Verification

1. Install WireGuard for Windows.
2. `flutter run -d windows` (or run the packaged build).
3. Tap Connect.
4. Verify the service:
   - PowerShell: `Get-Service -Name "WireGuardTunnel$SecureWave"`
   - Or check the WireGuard UI for the SecureWave tunnel.

If `wireguard.exe` is missing, Flutter receives `vpn_unavailable` and the app
falls back to mock mode only when native tools are unavailable.
