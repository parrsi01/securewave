# Apple Release Automation

SecureWave now has a macOS GitHub Actions workflow for iOS release validation:

```bash
gh workflow run apple-release.yml
```

The workflow runs `flutter pub get`, `pod install`, workspace guard checks,
App Store metadata checks, and `flutter build ios --release --no-codesign`.
That proves the iOS project is buildable on a macOS runner without requiring
Apple signing material.

Signed App Store/TestFlight upload still requires these repository secrets:

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
