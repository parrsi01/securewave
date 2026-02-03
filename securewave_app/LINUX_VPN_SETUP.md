# Linux VPN Setup (wg-quick)

SecureWave uses `wg-quick` to bring up a WireGuard tunnel on Linux. The Flutter
MethodChannel writes the config to disk and executes `wg-quick up/down`.

## Integration Summary

- MethodChannel: `securewave/vpn` (`isAvailable`, `connect`, `disconnect`)
- Backend: `wg-quick`
- Config file: `~/.config/securewave/securewave.conf`

## Requirements

- WireGuard tools installed (`wg-quick` on PATH)
- Permission to run `wg-quick` (typically via sudo)
- WireGuard config from backend `/api/vpn/config` (or `/api/vpn/allocate`)

## Verification

1. Install WireGuard tools:
   - Ubuntu/Debian: `sudo apt-get install wireguard`
2. `flutter run -d linux`
3. Tap Connect (allow elevation if prompted).
4. Verify the interface:
   - `sudo wg show securewave`
   - `ip addr show securewave`

If `wg-quick` is not found, Flutter receives `vpn_unavailable` and the app
falls back to mock mode only when native tools are unavailable.
