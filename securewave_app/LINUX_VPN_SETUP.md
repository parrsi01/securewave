# Linux VPN Setup (wg-quick)

SecureWave uses `wg-quick` to bring up a WireGuard tunnel on Linux. The Flutter
MethodChannel writes the config to disk and executes `wg-quick up/down`.

## Integration Summary

- MethodChannel: `securewave/vpn` (`isAvailable`, `connect`, `disconnect`)
- Backend: `wg-quick`
- Config file: `~/.config/securewave/securewave.conf`

## Requirements

- WireGuard tools installed (`wg-quick` on PATH)
- Permission to run `wg-quick` (via PolicyKit/pkexec prompt)
- Tunnel profile from backend `POST /api/vpn/profile` (JSON; the app fetches this automatically after sign-in)

## Verification

1. Install WireGuard tools:
   - Ubuntu/Debian: `sudo apt-get install wireguard`
2. `flutter run -d linux`
3. Tap Connect (approve the PolicyKit/pkexec elevation prompt).
4. Verify the interface:
   - `sudo wg show securewave`
   - `ip addr show securewave`

If `wg-quick` is not found, Flutter receives `vpn_unavailable`. In demo mode
(`SECUREWAVE_USE_MOCK_API=true`) the app can simulate a tunnel; in live mode it
will not connect until the tools are installed.
