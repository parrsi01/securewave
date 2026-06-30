# iOS VPN Setup (Xcode Required)

## 1) Workspace-only entry point (enforced)

SecureWave iOS must be built from `Runner.xcworkspace`, not `Runner.xcodeproj`.

This repo enforces it at build time:
- `securewave_app/ios/scripts/ensure_workspace.sh`
- Schemes (pre-action): **Workspace Guard** (`Runner`, `PacketTunnel`)
- Targets (build phase): **Workspace Guard** (`Runner`, `PacketTunnel`)

Open the workspace:
```bash
open securewave_app/ios/Runner.xcworkspace
```

## 2) Deterministic dependencies (CocoaPods + vendored WireGuardKit)

### CocoaPods
```bash
cd securewave_app/ios
pod install
```

### WireGuardKit (vendored)
WireGuardKit is vendored at:
- `securewave_app/ios/ThirdParty/wireguard-apple`

### Go toolchain requirement (wg-go)
PacketTunnel links `-lwg-go`. The build phase **Build WireGuard Go Backend** invokes:
- `securewave_app/ios/scripts/build_wg_go.sh`

If Go is missing, the build fails fast with a clear error. Install Go:
```bash
brew install go
```

## 3) Signing & entitlements (cannot be automated)

Files in this repo (minimal entitlements):
- App: `securewave_app/ios/Runner/Runner.entitlements`
- Extension: `securewave_app/ios/PacketTunnel/PacketTunnel.entitlements`

Xcode requirements:
1. Set the same Apple Team for **Runner** and **PacketTunnel**
2. Ensure the **Network Extensions** capability is enabled (Packet Tunnel)
3. Ensure bundle identifiers are consistent:
   - Runner: `com.securewave.vpn`
   - PacketTunnel: `com.securewave.vpn.PacketTunnel`

Important: the **Network Extension entitlement** is granted by Apple. Without it, preference load/save/start will fail and the app will return a descriptive error.

SecureWave does not use Hotspot Helper. The iOS VPN request should be scoped to
NetworkExtension / Packet Tunnel Provider.

## 4) Build verification (CLI)

Preflight:
```bash
bash securewave_app/scripts/verify_ios_build.sh
```

Debug compile (device SDK, no codesign):
```bash
xcodebuild -workspace securewave_app/ios/Runner.xcworkspace -scheme Runner -configuration Debug -sdk iphoneos -destination "generic/platform=iOS" CODE_SIGNING_ALLOWED=NO build
```

Release compile (no codesign):
```bash
xcodebuild -workspace securewave_app/ios/Runner.xcworkspace -scheme Runner -configuration Release -sdk iphoneos -destination "generic/platform=iOS" CODE_SIGNING_ALLOWED=NO build
```

Guard verification (this must FAIL with the workspace message):
```bash
xcodebuild -project securewave_app/ios/Runner.xcodeproj -scheme Runner -configuration Debug -sdk iphoneos -destination "generic/platform=iOS" CODE_SIGNING_ALLOWED=NO build
```

## 5) Production/TestFlight checklist (Apple-specific)

- Confirm PacketTunnel is embedded: `Runner.app/PlugIns/PacketTunnel.appex`
- Confirm connect/disconnect works on a physical device
- Confirm failures are explicit (no silent “mock success”)
- Archive from Xcode with valid signing for both targets

Mac CLI archive/export:

```bash
export APPLE_TEAM_ID="<team-id>"
bash securewave_app/scripts/archive_ios_release.sh
```
