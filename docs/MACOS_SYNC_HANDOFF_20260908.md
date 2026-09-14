# macOS release synchronization — 8 September 2026

## Ownership while the Linux VM works

This branch owns the macOS UI-demo ZIP, its download metadata, the macOS
packaging script, and its integrity check. Linux installation/VPN acceptance,
backend/email changes, and production deployment remain with the Linux work.
Merge this focused branch; do not replace the Linux checkout with the older
Mac working directory or copy the entire downloads manifest over newer changes.

## Build source and scope

Shared Flutter application source is from master commit
`f6c1ee143a794bb99c7e31cbc23d1661d559328`, version `4.0.0+10`.
No shared Dart application or native VPN behavior was edited here.
Flutter 3.44.0 / Dart 3.12.0 resolved `meta` to 1.18.0 and `test_api` to
0.7.11; the lockfile records these SDK dependency changes. The packaging
script now enforces that lockfile and retains the existing CocoaPods model
instead of automatically migrating the Xcode project to Swift Package Manager.

The macOS package remains an ad-hoc-signed UI/account demo, not a notarized
VPN release. Windows, Android, iOS, and Intel Mac availability are unchanged.
Matching version numbers do not certify native runtime parity.

## Release check

The packaging script reads the actual app Info.plist version and computes the
ZIP SHA-256 for the existing macOS ARM64 manifest entry. Apple CI verifies these
values before uploading artifacts:

```bash
python3 scripts/verify_macos_download.py
python3 -m unittest discover -s tests/unit -p test_macos_download_integrity.py
```

GitHub branch/PR publication is not website deployment. After the normal
reviewed deployment, independently download the public ZIP, check its embedded
version, and compare its SHA-256 with the deployed manifest. Do not claim the
public download is updated until that check passes.
