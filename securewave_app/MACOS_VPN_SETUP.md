# macOS VPN Setup (Channel Prep Only)

SecureWave exposes the `securewave/vpn` MethodChannel on macOS but does not
attempt to create a tunnel. Native availability returns `false` until a signed
Network Extension or WireGuardKit integration is added.

## Integration Summary

- MethodChannel: `securewave/vpn` (`isAvailable`, `connect`, `disconnect`)
- Current behavior: returns `vpn_not_configured` for connect/disconnect
- No signing or entitlements are added in this repo

## Next Steps (when ready)

1. Choose a backend:
   - Network Extension (NEVPNManager + NEPacketTunnelProvider)
   - WireGuardKit Swift package
2. Add required entitlements:
   - Network Extensions
   - Personal VPN
3. Codesign the app with a valid Apple Developer certificate.

## Verification (current state)

- `isAvailable` returns `false` on macOS.
- Connect attempts return `vpn_not_configured` until entitlements exist.

## References

- WireGuardKit: https://github.com/WireGuard/wireguard-apple
- Apple Network Extension docs: https://developer.apple.com/documentation/networkextension
