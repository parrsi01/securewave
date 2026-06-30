# Apple Release Automation

SecureWave now has a macOS GitHub Actions workflow for iOS release validation:

```bash
gh workflow run apple-release.yml
```

The workflow runs `flutter pub get`, `pod install`, workspace guard checks,
App Store metadata checks, and `flutter build ios --release --no-codesign`.
That proves the iOS project is buildable on a macOS runner without requiring
Apple signing material.

For local Mac finalization after pulling this branch:

```bash
export APPLE_TEAM_ID="<team-id>"
bash securewave_app/scripts/archive_ios_release.sh
```

The script archives from `securewave_app/ios/Runner.xcworkspace`, never
`Runner.xcodeproj`, and exports signed output to
`securewave_app/build/ios/export/`.

Signed App Store/TestFlight archive automation requires these repository
secrets:

- `APPLE_TEAM_ID`
- `APP_STORE_CONNECT_KEY_ID`
- `APP_STORE_CONNECT_ISSUER_ID`
- `APP_STORE_CONNECT_PRIVATE_KEY`
- `IOS_SIGNING_CERTIFICATE_P12`
- `IOS_SIGNING_CERTIFICATE_PASSWORD`
- `IOS_PROVISIONING_PROFILE`

To verify secret presence without publishing an app, run the workflow manually
with `require_signing=true`.

Local Linux hosts cannot prove iOS signing because Xcode, CocoaPods, and Apple
signing services require macOS.

## Entitlement clarification

SecureWave’s iOS VPN path uses Apple NetworkExtension with a Packet Tunnel
Provider extension:

- `com.securewave.vpn`
- `com.securewave.vpn.PacketTunnel`
- `com.apple.developer.networking.networkextension`
- `packet-tunnel-provider`

SecureWave does not use Hotspot Helper. A Hotspot Helper entitlement is not the
right request for this VPN app because SecureWave does not manage captive Wi-Fi
hotspot authentication.
