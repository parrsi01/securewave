# iOS VPN Setup (Xcode Required)

This repo includes the Packet Tunnel extension ([ios/PacketTunnel](ios/PacketTunnel)) and native VPN bridge ([ios/Runner/VPNManager.swift](ios/Runner/VPNManager.swift:1-62), [ios/Runner/AppDelegate.swift](ios/Runner/AppDelegate.swift:13-38)),
but you must finish configuration in Xcode on macOS.

## Xcode-Only Steps (Cannot Be Automated)

**IMPORTANT**: You MUST use `Runner.xcworkspace`, NOT `Runner.xcodeproj`. The workspace includes Swift Package dependencies.

1. **Open workspace**: `securewave_app/ios/Runner.xcworkspace` in Xcode
2. **Runner target → Signing & Capabilities**:
   - Set your Apple Team
   - Confirm the bundle identifier (e.g., `com.example.securewaveApp`)
3. **PacketTunnel target → Signing & Capabilities**:
   - Set the same Apple Team
   - Enable **Network Extensions** capability (click + Capability → Network Extensions)
   - Bundle ID must be `<Runner-bundle-id>.PacketTunnel`
4. **Wait for Swift Package Manager**:
   - Xcode will resolve WireGuardKit from `https://github.com/WireGuard/wireguard-apple`
   - This happens automatically; watch the status bar
5. **Build on physical device**:
   - Plug in a physical iPhone (simulators cannot start VPN tunnels)
   - Select device in Xcode
   - Product → Run (⌘R)

## Required

- macOS with Xcode 14+ installed
- Active Apple Developer account (free or paid)
- Physical iOS device (iOS 15+)

## Implementation Status

- ✅ Packet Tunnel Extension exists and compiles
- ✅ VPNManager Swift bridge implemented
- ✅ Flutter MethodChannel integration complete
- ⚠️  Signing & Capabilities must be configured per-developer in Xcode UI
- ⚠️  WireGuardKit dependency resolves automatically via SPM

## Troubleshooting

- **"Runner.xcodeproj won't build"**: Use `Runner.xcworkspace` instead
- **"No such module WireGuardKit"**: Wait for SPM to finish resolving packages (File → Packages → Resolve Package Versions)
- **"VPN tunnel won't start"**: Must use physical device, not simulator
- **"Signing failed"**: Ensure both Runner and PacketTunnel targets have the same team selected

## References

- Apple Network Extension docs: https://developer.apple.com/documentation/networkextension
- WireGuardKit source: https://github.com/WireGuard/wireguard-apple

