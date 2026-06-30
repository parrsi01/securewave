# SecureWave Apple Review Handoff

This packet is for finishing SecureWave on a Mac with Xcode after pulling the
latest repository branch.

## Entitlement Scope

SecureWave is a user-initiated VPN client. The iOS target uses Apple
NetworkExtension with a Packet Tunnel Provider extension:

- App bundle ID: `com.securewave.vpn`
- Packet Tunnel extension bundle ID: `com.securewave.vpn.PacketTunnel`
- Entitlement: `com.apple.developer.networking.networkextension`
- Entitlement value: `packet-tunnel-provider`

SecureWave does not use Hotspot Helper. It does not scan, classify,
authenticate, or manage captive Wi-Fi networks.

## Mac Finalization Steps

Run from a Mac with Xcode, CocoaPods, Go, Flutter, Apple signing certificates,
and the matching provisioning profiles installed:

```bash
git checkout flutter
git pull origin flutter
export APPLE_TEAM_ID="<team-id>"
bash securewave_app/scripts/archive_ios_release.sh
```

The script uses `securewave_app/ios/Runner.xcworkspace`, verifies iOS store
metadata, archives the `Runner` scheme, and exports the signed artifact to:

```text
securewave_app/build/ios/export/
```

## macOS Website Demo Build

The repository also includes a Mac-only script that packages the current macOS
UI/account demo app for the website:

```bash
bash securewave_app/scripts/package_macos_ui_demo.sh
```

That script writes one of these files, depending on the Mac architecture:

```text
static/downloads/securewave-macos-arm64-ui-demo.zip
static/downloads/securewave-macos-x64-ui-demo.zip
```

This is not a production macOS VPN release. The current macOS app returns
`vpn_not_configured` for tunnel start/stop until a signed macOS Network
Extension target is added.

If a local Mac is not available, GitHub Actions can build the same demo on a
macOS runner and commit the generated zip plus updated manifest back to the
branch:

```bash
gh workflow run apple-release.yml --ref flutter -f publish_macos_demo=true
```

## Public Review URLs

- Product website: `https://securewaveapp.com`
- Apple review page: `https://securewaveapp.com/apple-review.html`
- Downloads: `https://securewaveapp.com/download.html`
- Privacy: `https://securewaveapp.com/privacy.html`
- Terms: `https://securewaveapp.com/terms.html`
- Support: `https://securewaveapp.com/contact.html`

## Review Account

Create a dedicated reviewer account after production SMTP and billing are live.
Do not submit placeholder credentials to Apple.
