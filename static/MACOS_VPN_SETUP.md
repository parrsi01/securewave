# macOS VPN Setup (Not Available In Unsigned Builds)

SecureWave exposes the `securewave/vpn` MethodChannel on macOS with explicit
"not available" responses for OpenVPN and IKEv2 when required entitlements are
missing.

## Current repo status (macOS)

- Workspace: `securewave_app/macos/Runner.xcworkspace`
- Workspace-only entry point is enforced by: `securewave_app/macos/scripts/ensure_workspace.sh` (scheme pre-action **Workspace Guard**)
- There is no macOS Packet Tunnel extension target under `securewave_app/macos` in this repo.
- Production OpenVPN/IKEv2 on macOS is blocked until a Network Extension target is added and signed.

## Integration Summary

- MethodChannel: `securewave/vpn` (`isAvailable`, `getCapabilities`, `getStatus`, `connect`, `disconnect`)
- `isAvailable`: `false`
- `getCapabilities`: all protocols `false`, with explicit `macos_entitlement_warning`
- `connect`: returns `protocol_unavailable` with protocol-specific reason
- No signing or Network Extension entitlements are added in this repo

## Next Steps (when ready)

1. Choose a backend:
   - Network Extension (NEVPNManager + NEPacketTunnelProvider)
   - WireGuardKit Swift package
2. Add required entitlements:
   - Network Extensions
   - Personal VPN
3. Add a Packet Tunnel extension target and embed it in `Runner`.
4. Codesign Runner + extension with a valid Apple Developer certificate and matching provisioning profiles.

## Verification (current state)

- `isAvailable` returns `false` on macOS.
- OpenVPN/IKEv2 connect attempts return `protocol_unavailable` with actionable details.

Build (no codesign):
```bash
xcodebuild -workspace securewave_app/macos/Runner.xcworkspace -scheme Runner -configuration Debug -sdk macosx -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO build
```

## References

- WireGuardKit: https://github.com/WireGuard/wireguard-apple
- Apple Network Extension docs: https://developer.apple.com/documentation/networkextension
