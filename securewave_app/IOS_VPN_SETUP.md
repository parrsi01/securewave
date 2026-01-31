# iOS VPN Setup (Xcode Required)

## DO NOT OPEN Runner.xcodeproj

**Always open `Runner.xcworkspace`.** The workspace includes CocoaPods-managed
dependencies and the Flutter engine. If you open the `.xcodeproj` directly,
the build will fail with missing framework errors.

```bash
# CORRECT
open ios/Runner.xcworkspace

# WRONG - will break the build
open ios/Runner.xcodeproj
```

Guard scripts enforce this rule automatically. If the error appears anyway,
close Xcode completely, then re-open with the workspace.

---

## Xcode-Only Steps (Cannot Be Automated)

1. **Open workspace**: `securewave_app/ios/Runner.xcworkspace` in Xcode
2. **Runner target -> Signing & Capabilities**:
   - Set your Apple Team
   - Confirm the bundle identifier (e.g., `com.example.securewaveApp`)
3. **PacketTunnel target -> Signing & Capabilities**:
   - Set the same Apple Team
   - Enable **Network Extensions** capability (+ Capability -> Network Extensions)
   - Bundle ID must be `<Runner-bundle-id>.PacketTunnel`
4. **Wait for dependency resolution**:
   - CocoaPods pods are already installed via `pod install`
   - Xcode may also resolve WireGuardKit via SPM automatically
5. **Build on physical device**:
   - Plug in a physical iPhone (simulators cannot start VPN tunnels)
   - Select device in Xcode
   - Product -> Run

## Requirements

- macOS with Xcode 14+ installed
- Active Apple Developer account (free or paid)
- Physical iOS device (iOS 14+)

## Implementation Status

- Packet Tunnel Extension exists and compiles
- VPNManager Swift bridge implemented
- Flutter MethodChannel integration complete
- Signing & Capabilities must be configured per-developer in Xcode UI
- WireGuardKit dependency resolves via SPM

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| "Runner.xcodeproj won't build" | Close Xcode. Open `Runner.xcworkspace` instead. |
| "No such module WireGuardKit" | File -> Packages -> Resolve Package Versions |
| "VPN tunnel won't start" | Must use physical device, not simulator |
| "Signing failed" | Both Runner and PacketTunnel need the same team |
| Pods out of sync | `cd ios && rm -rf Pods Podfile.lock && pod install` |

## Recovery Checklist

If the workspace error keeps appearing:

1. Quit Xcode completely (Cmd+Q)
2. `cd securewave_app/ios`
3. `rm -rf Pods Podfile.lock build`
4. `cd .. && flutter clean && flutter pub get`
5. `cd ios && pod install`
6. `open Runner.xcworkspace`

## References

- Apple Network Extension docs: https://developer.apple.com/documentation/networkextension
- WireGuardKit source: https://github.com/WireGuard/wireguard-apple
