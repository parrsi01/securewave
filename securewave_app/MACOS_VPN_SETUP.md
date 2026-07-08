# macOS VPN Setup (Channel Prep Only)

SecureWave exposes the `securewave/vpn` MethodChannel on macOS but does not
attempt to create a tunnel. Native availability returns `false` until a signed
Network Extension or WireGuardKit integration is added.

Public macOS downloads in the current repo are UI/demo artifacts only. Do not
claim macOS VPN routing unless a signed Network Extension build and routing
proof exist.

## Current repo status (macOS)

- Workspace: `securewave_app/macos/Runner.xcworkspace`
- Workspace-only entry point is enforced by: `securewave_app/macos/scripts/ensure_workspace.sh` (scheme pre-action **Workspace Guard**)
- There is no macOS Packet Tunnel extension target under `securewave_app/macos` in this repo.
- Production VPN on macOS is blocked until a Network Extension target is added and signed.
- A website-downloadable macOS UI demo can be packaged on a Mac with
  `securewave_app/scripts/package_macos_ui_demo.sh`.

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

Build (no codesign):
```bash
xcodebuild -workspace securewave_app/macos/Runner.xcworkspace -scheme Runner -configuration Debug -sdk macosx -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO build
```

Package the current UI/account demo app for the public website:

```bash
bash securewave_app/scripts/package_macos_ui_demo.sh
```

Expected output:

```text
static/downloads/securewave-macos-arm64-ui-demo.zip
```

or:

```text
static/downloads/securewave-macos-x64-ui-demo.zip
```

The packaged demo is not notarized unless `MACOS_CODESIGN_IDENTITY` is set and
the resulting app is notarized separately.

## References

- WireGuardKit: https://github.com/WireGuard/wireguard-apple
- Apple Network Extension docs: https://developer.apple.com/documentation/networkextension
