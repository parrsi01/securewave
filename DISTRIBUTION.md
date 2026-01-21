# SecureWave Distribution & Install Flow

## Website Download Section

The marketing homepage now includes a "Download Apps" section with links to
platform-specific builds. Links should point to GitHub Releases or store
pages once published.

## Release Pipeline (GitHub Actions)

Workflow: `.github/workflows/flutter-release.yml`

Triggered on:
- Tag push `app-v*`
- Manual `workflow_dispatch`

Builds:
- Linux (release bundle)
- Windows (release build)
- macOS (release build)
- Android (release APK) if signing secrets exist
- iOS (unsigned build) if Apple Team ID is present

## Required Secrets

Android signing:
- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

iOS:
- `APPLE_TEAM_ID`

## Store Distribution (Future)

- iOS: TestFlight → App Store
- Android: Internal testing → Play Store
- Windows/macOS: Signed installers via GitHub Releases

## Website CTA Flow (Recommended)

1. User clicks Download App on website.
2. Platform build delivered via GitHub Releases.
3. App signs in with SecureWave credentials and provisions device.
