# SecureWave macOS/iOS Demo Readiness Report

Date: 2026-05-11

## Executive Summary

SecureWave is now demo-runnable locally on macOS and on the iOS Simulator without Apple VPN certificate/provisioning setup. The demo path remains truthful: macOS native VPN still reports unavailable, iOS Simulator VPN still fails preflight because Network Extension packet tunnels require a physical device, and the UI continues to label the public release truth as Linux desktop release candidate.

No Linux release-candidate scope, protocol catalog, backend/provider truth, Apple entitlement scope, or dependency versions were changed. Physical iOS VPN testing still requires an Apple team with packet tunnel entitlement and a real device.

## What Is Demo Runnable Now

| Surface | Current status | Evidence | Notes |
| --- | --- | --- | --- |
| macOS Flutter app | Demo runnable | `./script/build_and_run.sh --verify` builds and launches `securewave_app` | Builds into guarded `/tmp` paths and strips xattrs that can break signing. |
| iOS Simulator app | Demo runnable | `./script/build_and_run_ios_simulator.sh --verify` builds, installs, launches, and writes `/tmp/securewave_ios_simulator.png` | Uses explicit workspace `xcodebuild` with `COPYFILE_DISABLE=1`. |
| macOS native VPN | Not production configured | `macos/Runner/AppDelegate.swift` returns unavailable / `vpn_not_configured` | Truthful blocker preserved. |
| iOS Simulator VPN | Not available by design | `ios/Runner/VPNManager.swift` returns simulator preflight error | Simulator can demo UI/app flows only, not a real packet tunnel. |
| iOS physical VPN | Still entitlement/certificate gated | Runner/PacketTunnel entitlements declare packet tunnel provider | Requires valid Apple signing and physical device. |
| macOS release packaging | Blocked by design | macOS release guard reports missing Network Extension entitlement | Correct until Apple entitlement and macOS tunnel target are added. |

## Local Xcode Runtime Note

This Mac had Xcode 26.4.1 SDK build `23E252` but only an installed ready iOS 26.2 Simulator runtime build `23C54` after the broken/duplicate iOS 26.4 runtime was removed. Xcode destination resolution was repaired locally with:

```bash
xcrun simctl runtime match set iphoneos26.4 23C54 --sdkBuild 23E252
```

That is a local toolchain preference, not repository product behavior.

## Validation Results

| Command | Result | Meaning |
| --- | --- | --- |
| `./script/build_and_run.sh --verify` | Pass | macOS app builds, launches, and process is detected. |
| `./script/build_and_run_ios_simulator.sh --verify` | Pass | iOS Simulator app builds, installs, launches, and screenshot is captured. |
| `xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -showdestinations` | Pass | Runner now exposes iOS Simulator destinations. |
| `COPYFILE_DISABLE=1 xcodebuild ... -sdk iphonesimulator ... build` | Pass | Signed simulator workspace build succeeds. |
| `flutter analyze` | Pass | Flutter/Dart static analysis reports no issues. |
| `flutter test` | Pass | Existing Flutter tests all pass. |
| `./scripts/verify_ios_build.sh` | Pass | iOS project prerequisites are present. |
| `flutter build ios --simulator --debug --no-pub` | Non-canonical fail | Flutter generic simulator packaging still reports terse CodeSign failure; explicit workspace build is the reliable simulator path. |

## Protected Boundaries

- No Linux runtime, helper, packaging, or public release truth changed.
- No WireGuard/OpenVPN/IKEv2 runtime behavior or release visibility changed.
- No Azure, premium, or multi-platform release claim was introduced.
- No macOS Network Extension entitlement was added.
- No iOS signing team, provisioning profile, bundle ID, or entitlement behavior was changed.
- No dependency upgrade or lockfile churn occurred.
- No fake connected state was introduced.

## Implementation Notes

- `script/build_and_run_ios_simulator.sh` is a demo helper only. It builds via `Runner.xcworkspace`, boots an available simulator, installs `Runner.app`, launches `com.example.securewaveApp`, and optionally captures a screenshot.
- `ios/scripts/build_wg_go.sh` adds simulator-only cgo stubs to the local simulator `libwg-go.a` when Xcode is building `PLATFORM_NAME=iphonesimulator` and the vendored Go archive exposes unresolved Darwin ARM cgo exception-port symbols. Device builds are untouched.
- `ios/PacketTunnel/Info.plist` now includes `CFBundleExecutable=$(EXECUTABLE_NAME)`, which is required for app extension install/package correctness.
- `SUPPORTED_PLATFORMS` now includes `iphonesimulator` at the iOS project configuration level so Xcode can resolve simulator destinations.

## Recommended Next Order

1. Demo locally: use `./script/build_and_run.sh` for macOS or `./script/build_and_run_ios_simulator.sh` for iOS Simulator.
2. For iOS real VPN testing: use a physical iOS device with valid Runner and PacketTunnel signing under an Apple team that has Network Extension packet tunnel entitlement.
3. For macOS production parity: add the macOS Network Extension packet tunnel target and release entitlements only after the Apple entitlement/certificate path is available.
4. Before any macOS/iOS production release claim: add signing, notarization/TestFlight, entitlement, packet tunnel, and install/upgrade regression checks.

## Strict Change Log

What changed:

- Added repeatable macOS and iOS Simulator demo run scripts.
- Added Codex Run actions for macOS and iOS Simulator.
- Hardened iOS doctor destination checks.
- Enabled Xcode iOS Simulator destination resolution in the iOS project.
- Added missing `CFBundleExecutable` to PacketTunnel extension Info.plist.
- Added simulator-only WireGuard Go archive cgo stub patching for local simulator builds.
- Updated this readiness artifact.

What was reused:

- Existing Flutter UI, providers, mock/demo fallback policy, and test suite.
- Existing macOS native method channel unavailable behavior.
- Existing iOS Runner, PacketTunnel, WireGuardKit, CocoaPods, and preflight scripts.
- Existing Linux release-candidate truth and macOS release NO-GO guard.

What was intentionally left untouched:

- Linux release candidate behavior.
- VPN protocol runtime semantics.
- Apple signing/provisioning configuration.
- macOS release entitlements.
- iOS runtime preflight that blocks Simulator VPN.
- Dependency versions and lockfiles.

Risks introduced:

- Low local-build risk: simulator-only cgo stubs affect only the generated simulator archive, not the physical-device PacketTunnel build.
- Low tooling risk: run scripts remove only guarded `/tmp/securewave_app_*` build paths and generated iOS native assets.
- Residual release risk remains: physical iOS VPN and production macOS VPN still require Apple entitlement/certificate work.
