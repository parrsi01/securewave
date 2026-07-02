# Apple Signing Readiness Report - 2026-07-02

## Scope

This report captures the local Apple release-signing diagnostic run from the
`Mac` branch after the repository branch model was split into `Linux`,
`Windows`, and `Mac`.

## Host

- macOS: `26.5.1`
- Architecture: `arm64`
- Xcode: `26.6`
- Flutter: `3.44.0`
- CocoaPods: `1.16.2`
- Go: available through Homebrew

## Result

`SECUREWAVE_IOS_RELEASE_SIGNING=1 bash securewave_app/scripts/doctor_flutter_ios.sh`
now reaches the signing checks successfully. The earlier `pipefail`/`head`
SIGPIPE failure in the doctor was fixed by avoiding external version pipelines.

Passing local prerequisites:

- Xcode command line tools are selected.
- Flutter packages are fetched.
- CocoaPods is installed.
- `securewave_app/ios/Runner.xcworkspace` is present and valid.
- Runner and PacketTunnel targets exist.
- Xcode reports at least one eligible iOS destination.

Release blockers:

- Only an Apple Development signing identity is installed locally.
- No Apple Distribution identity is available for App Store export.
- `APPLE_TEAM_ID` is not set in the environment.
- `~/Library/MobileDevice/Provisioning Profiles` is missing, so no local
  provisioning profile was found for either `com.securewave.vpn` or
  `com.securewave.vpn.PacketTunnel`.

## Required Next Step

Install or configure the Apple Distribution certificate, provisioning profiles
for both bundle identifiers, and `APPLE_TEAM_ID`, then rerun:

```bash
SECUREWAVE_IOS_RELEASE_SIGNING=1 bash securewave_app/scripts/doctor_flutter_ios.sh
bash securewave_app/scripts/archive_ios_release.sh
```

Do not mark the Apple release TODO complete until
`securewave_app/build/ios/export/` contains the signed exported artifact.
