# SecureWave macOS Automated Test Pass

Date: 2026-04-25

Verdict: `MACOS_AUTOMATED_TEST_PASS=PARTIAL`

This is a macOS automated evidence pass only. It does not promote macOS into
the public v1 release scope. Public v1 remains Linux desktop only.

## Test Plan Used

1. Inspect macOS project, MethodChannel runtime, entitlements, docs, tests, and
   platform/protocol UI surfaces.
2. Run Flutter static and unit/widget validation.
3. Attempt a normal Flutter macOS release build.
4. If release build is blocked, run an unsigned Xcode Debug build to separate
   compile/link viability from signing/build-hygiene failure.
5. Run the available macOS XCTest target.
6. Launch the Debug app bundle for a bounded smoke window.
7. Classify protocol and platform behavior from code, docs, and test output.

## Exact Commands Run

```bash
git status --short
git diff --name-only
git diff --cached --name-only
flutter --version
xcodebuild -version
cd securewave_app && flutter doctor -v
cd securewave_app && flutter analyze
cd securewave_app && flutter test
cd securewave_app && flutter build macos
cd securewave_app && xattr -lr build/macos/Build/Products/Release/securewave_app.app
cd securewave_app && xcodebuild -workspace macos/Runner.xcworkspace -scheme Runner -configuration Debug -sdk macosx -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO build
cd securewave_app && xcodebuild test -workspace macos/Runner.xcworkspace -scheme Runner -configuration Debug -sdk macosx -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO
<launch Debug securewave_app.app executable, wait 8 seconds, terminate if still alive>
```

## Command Results

| Command | Exit | Result |
|---|---:|---|
| `flutter --version` | 0 | Flutter 3.38.8 / Dart 3.10.7 captured. |
| `xcodebuild -version` | 0 | Xcode 26.4.1 captured. |
| `flutter doctor -v` | 0 | macOS/Xcode OK; Android SDK missing, not relevant to macOS pass. |
| `flutter analyze` | 0 | Passed with no analyzer issues. |
| `flutter test` | 0 | Passed, 10 tests. |
| `flutter build macos` | 1 | Failed during codesign. |
| `xattr -lr` on release app bundle | 0 | Captured extended attributes causing codesign blocker. |
| unsigned `xcodebuild build` | 0 | Passed Debug compile/link without codesigning. |
| unsigned `xcodebuild test` | 0 | Passed existing `RunnerTests.testExample`. |
| Debug app launch smoke | 0 | App stayed alive for 8 seconds and was terminated by smoke harness. |

## What Passed

- Flutter analyzer validation passed.
- Flutter unit/widget tests passed.
- macOS Debug app compiled and linked with `CODE_SIGNING_ALLOWED=NO`.
- Existing macOS XCTest target passed, though it currently contains only the
  default `testExample`.
- The Debug macOS app bundle launched and stayed alive for the 8-second smoke
  window.
- The macOS VPN bridge truth is explicit in source and docs: native availability
  is false, and connect/disconnect return `vpn_not_configured`.

## What Failed

- `flutter build macos` failed during codesign:

```text
resource fork, Finder information, or similar detritus not allowed
Command CodeSign failed with a nonzero exit code
```

The release bundle has extended attributes including `com.apple.FinderInfo`,
`com.apple.fileprovider.fpfs#P`, and `com.apple.provenance` on bundle/framework
paths. These were captured in `logs/macos_bundle_xattrs.log`.

## macOS Platform / Runtime Blocks

- macOS VPN is intentionally stubbed. `securewave_app/macos/Runner/AppDelegate.swift`
  exposes `securewave/vpn`, returns `false` for `isAvailable`, and returns
  `vpn_not_configured` for `connect` and `disconnect`.
- `securewave_app/MACOS_VPN_SETUP.md` states there is no macOS Packet Tunnel
  extension target and production VPN is blocked until a signed Network
  Extension target is added.
- `DebugProfile.entitlements` and `Release.entitlements` do not include Network
  Extension or Personal VPN entitlements.
- No automated macOS UI navigation/integration target exists. Navigation smoke
  evidence is limited to Flutter widget tests plus a native app launch smoke.

## Protocol Surface Truth

- WireGuard remains the primary product path in the shared Dart state.
- On macOS, no protocol has native tunnel support in this repo because the
  native MethodChannel stub refuses connect/disconnect.
- The generic settings UI still exposes WireGuard, IKEv2, and OpenVPN radio
  options. That is acceptable for this evidence pass but would need stricter
  platform gating before any macOS public release consideration.
- macOS connect attempts are blocked by design, not certified as unsupported
  because of a live runtime failure.

## Evidence Files

- `environment.txt`
- `git_status_short.txt`
- `git_diff_name_only.txt`
- `git_diff_cached_name_only.txt`
- `command_exit_summary.txt`
- `logs/*.log`
- `logs/*.exit`
- `snapshots/macos_app_delegate_method_channel.swift`
- `snapshots/macos_vpn_setup.md`
- `snapshots/macos_entitlements_and_plist.txt`
- `snapshots/vpn_page_platform_copy.dart`
- `snapshots/settings_protocol_surface.dart`

## Files Changed By This Pass

- Created this evidence bundle under
  `tools/live_qa/out/20260425_140620-macos-automated-test-pass/`.
- Build/test tooling also produced local macOS build byproducts and CocoaPods
  project state changes. These were not manually edited and should be reviewed
  before any commit:
  - `securewave_app/macos/Runner.xcodeproj/project.pbxproj`
  - `securewave_app/macos/Runner.xcworkspace/contents.xcworkspacedata`
  - `securewave_app/macos/Podfile.lock`

Pre-existing dirty files remain outside this evidence verdict.

