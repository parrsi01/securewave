# macOS VPN Setup (Native Integration)

SecureWave includes a macOS MethodChannel handler that returns a
`vpn_not_configured` error until a WireGuard backend is added.

## Steps

1. Decide on backend:
   - Network Extension (NEVPNManager + NEPacketTunnelProvider)
   - WireGuardKit Swift package integration
   - Go-based embedded backend
2. Implement a native bridge in `macos/Runner`:
   - Accept the WireGuard config string via method channel
   - Configure and start/stop a VPN tunnel
   - Report connection status back to Flutter
3. Add required entitlements:
   - Network Extensions
   - Personal VPN
4. Code sign with a valid Apple Developer certificate

## Current Bridge

`securewave/vpn` MethodChannel exists in [macos/Runner/AppDelegate.swift](macos/Runner/AppDelegate.swift:20-34)
and returns a clear error if no backend is configured.

## References

- WireGuardKit: https://github.com/WireGuard/wireguard-apple
- Apple Network Extension docs: https://developer.apple.com/documentation/networkextension
