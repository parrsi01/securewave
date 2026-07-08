# Apple Release Automation

SecureWave now has a macOS GitHub Actions workflow for iOS release validation:

```bash
gh workflow run apple-release.yml
```

The workflow runs `flutter pub get`, `pod install`, workspace guard checks,
App Store metadata checks, `flutter build ios --release --no-codesign`, unsigned
`.app` collection, and unsigned artifact upload. Run `28514166181` on
`2026-07-01` passed this path on branch `flutter` at `7a182080`.

For local Mac finalization after pulling this branch:

```bash
export APPLE_TEAM_ID="<team-id>"
SECUREWAVE_IOS_RELEASE_SIGNING=1 bash securewave_app/scripts/doctor_flutter_ios.sh
bash securewave_app/scripts/archive_ios_release.sh
```

The script archives from `securewave_app/ios/Runner.xcworkspace`, never
`Runner.xcodeproj`, and exports signed output to
`securewave_app/build/ios/export/`.
The doctor command does not print or persist signing secrets; it checks for a
Mac/Xcode environment, an Apple Distribution signing identity, and provisioning
profiles for `com.securewave.vpn` and
`com.securewave.vpn.PacketTunnel`.

For the website-downloadable macOS UI demo package, run on a Mac:

```bash
bash securewave_app/scripts/package_macos_ui_demo.sh
```

That writes `static/downloads/securewave-macos-arm64-ui-demo.zip` or
`static/downloads/securewave-macos-x64-ui-demo.zip`. The Apple Silicon zip is
already published on both `flutter` and `master`. The demo app is
UI/account-only; macOS VPN tunnel start/stop still returns `vpn_not_configured`
until a signed macOS Network Extension target is added.

To let GitHub Actions build the macOS UI demo on a macOS runner and commit the
generated zip plus updated manifest back to the branch:

```bash
gh workflow run apple-release.yml --ref flutter -f publish_macos_demo=true
```

The workflow also uploads the generated macOS zip as a run artifact. Use this
path when a Mac is not available locally but a website-downloadable demo build
is needed.

The latest verified run uploaded:

- `securewave-ios-unsigned-flutter`
- `securewave-macos-ui-demo-flutter`

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

As of `2026-07-01`, `gh secret list --repo parrsi01/securewave` only reports a
legacy CI credential unrelated to the current Apple signing requirements. The
signed archive path therefore remains unrun in CI until the Apple signing
secrets above are added.

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
