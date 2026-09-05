# SecureWave Portability Runtime Matrix

Last audited: 2026-07-08 UTC

Audited checkout:

- Branch: `master`
- Commit: `7dd722d8918810bba993bcc38836949ba35016eb`
- Host architecture: `aarch64` / Debian architecture `arm64`
- Pull status before audit: `git pull --ff-only origin master` returned
  `Already up to date.`

This is a docs-only truth audit. It does not change runtime, protocol,
download, package, helper, or manifest behavior.

## Status Vocabulary

| Status | Meaning |
| --- | --- |
| Proven | Current tracked source or tracked artifact has reviewable evidence for the stated claim. |
| Implemented but not release-proven | Code path exists, but clean install, launch, connect, routing, disconnect, or publish evidence is missing. |
| UI-only | Artifact can only be claimed for app/account UI. Full VPN routing is not claimable from that artifact. |
| Blocked | The claim must fail closed until a missing artifact, source path, target host, signing asset, or runtime proof exists. |
| Unsupported | No current supported runtime path exists, or the app intentionally returns unavailable. |

## High-Risk Truth Findings

1. `securewave_app/packaging/linux/` and `securewave_app/linux/helperd/` are
   absent from tracked `master`. Generated helper payloads exist under ignored
   `securewave_app/build/` output, and similar files exist in an untracked local
   `.claude/worktrees` copy, but neither is current tracked source.
2. The tracked Linux runner currently uses direct `pkexec` command execution
   for `wg-quick` and `openvpn` when not root. The no-connect-prompt helper
   model is therefore not proven from tracked `master` source in this audit.
3. `securewave_app/scripts/build_deb.sh` builds a host-architecture `.deb`
   using `dpkg --print-architecture`. On this host that means `arm64`, not x64.
4. The tracked `static/downloads/securewave-linux-x64.tar.gz` contains an ARM
   aarch64 `securewave_app` ELF binary. It must not be treated as Linux x64
   proof despite the filename and manifest entry.
5. `static/downloads/manifest.json` correctly keeps the Linux x64 `.deb` and
   Linux x64 AppImage as `coming_soon`. The route currently recommends the
   tracked tarball for a Linux x64 user-agent because that tarball exists.

## Runtime Matrix

| Platform/runtime | Artifact type in current repo | UI launches | Full VPN routing | One-time admin/install authorization | Connect/disconnect privilege prompts | Protocol paths | Current status | Proof exists | Proof missing |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Linux ARM64 Debian/Ubuntu/systemd VM | `build_deb.sh` can build a host-arch `arm64` `.deb`; manifest exposes tracked `securewave-app-linux-arm64.zip`. No tracked ARM64 `.deb` is listed in the manifest. | Implemented; tracked ARM64 zip contains an aarch64 Linux Flutter binary. Clean VM UI launch is not proven by tracked evidence. | WireGuard is implemented but not release-proven. OpenVPN is unavailable in this baseline; its binary/helper residue paths do not constitute a connect path. | `.deb` install would require admin once. Current tracked `.deb` script does not itself install a helper service or declare runtime dependencies. | Current tracked runner may invoke `pkexec` at connect/disconnect when not root. This is not the no-connect-prompt helper model. | WireGuard via `wg-quick`; OpenVPN is fail-closed; IKEv2 detects `swanctl`/`ipsec` but returns `protocol_unavailable`. | WireGuard implemented but not release-proven; OpenVPN and helper/no-prompt claims blocked. | Host architecture is arm64; `build_deb.sh` uses `dpkg --print-architecture`; Linux runner code exists; backend tests keep OpenVPN/IKEv2 blocked. | Clean ARM64 VM `.deb` install, helper service registration, no-prompt connect/disconnect, route/DNS/public-IP proof, uninstall proof, and current-source helper packaging. |
| Linux x64 Debian/Ubuntu/systemd VM | Linux x64 `.deb` is `coming_soon`; x64 AppImage is `coming_soon`; tracked `securewave-linux-x64.tar.gz` is present but contains an ARM aarch64 binary. | Blocked for x64 from current tracked artifacts. | Blocked. No valid x64 artifact proof and no clean x86_64 runtime proof. | Future `.deb` install should require admin once; current x64 `.deb` artifact is absent. | Unknown for a valid x64 release artifact. Current source would use direct `pkexec` unless the helper model is restored and packaged. | WireGuard source path only; OpenVPN is fail-closed and IKEv2 unsupported. | Blocked. | Manifest correctly marks x64 `.deb` and AppImage `coming_soon`; GitHub-hosted `ubuntu-latest` workflow can build Linux on x86_64 when run. | Valid x64 artifact, x64 checksums, clean x86_64 VM install, helper/systemd proof, UI launch, WireGuard connect/disconnect/routing proof, and uninstall proof. |
| Linux portable tar/AppImage/zip UI mode | Tracked ARM64 zip exists; tracked x64 tar exists but is mislabeled because its binary is aarch64; AppImage is `coming_soon`. | ARM64 UI binary is present. x64 UI artifact is blocked because the tracked x64 tar is not x64. | UI-only as a release claim. Portable archives do not install dependencies, helper service, tmpfiles, systemd unit, or policy. | Archive extraction itself does not install privileged components. Any system integration is manual. | Current runner can prompt via `pkexec` if host tools are present. No no-prompt portable proof exists. | WireGuard only in the current release path; OpenVPN is fail-closed and IKEv2 unsupported. | UI-only for ARM64 zip; blocked for x64 tar/AppImage claims. | Archive inspection proves both tracked Linux portable binaries are aarch64. Manifest and route behavior are understood. | Correct x64 archive, AppImage artifact, portable launch proof per architecture, and explicit docs that portable mode is UI-only unless a separate privileged install is completed. |
| Windows | Installer slot `securewave-windows-x64-setup.exe` is `coming_soon`; build script requires Windows, Flutter, NSIS, and WireGuard for Windows. | Implemented by Flutter Windows runner, but release artifact is absent. | Implemented but not release-proven for WireGuard only. The runner shells out to official WireGuard for Windows tunnel service install/uninstall. | WireGuard for Windows must be installed. The app must have privileges to install/uninstall the tunnel service. | Yes unless the installed environment grants the service operations without another prompt. Current docs require app privileges. | WireGuard only. OpenVPN and IKEv2 are unsupported in the Windows app path. | Implemented but not release-proven; artifact blocked. | Windows runner code and setup docs define the WireGuard service path and detection order. | Windows build artifact, installer proof, signed/unsigned status, service install proof, connect/disconnect proof, routing/DNS proof, and uninstall cleanup. |
| macOS | Apple handoff zip and Apple Silicon UI demo zip are available; Intel macOS UI demo is `coming_soon`. | UI demo is available for Apple Silicon. | Unsupported. macOS `AppDelegate` returns `isAvailable=false` and `vpn_not_configured` for connect/disconnect. | No VPN install authorization applies because VPN is not enabled. Packaging/signing/notarization are separate release steps. | No connect/disconnect privilege prompt because connect/disconnect are disabled. | No production macOS VPN protocol path. | UI-only; VPN unsupported. | macOS setup docs, `AppDelegate.swift`, manifest, and download manifest tests all state the UI demo/no-VPN behavior. | Signed macOS Network Extension target, entitlements, notarized package, install proof, and full routing proof. |
| Android | APK slot `securewave-android.apk` is `coming_soon`; release build requires signing config. | Implemented but not release-proven. | Implemented but not release-proven for WireGuard. Android native code uses `VpnService` and WireGuard `GoBackend`. | Android VPN permission is required through the OS. Release signing is required for a public release build. | The OS may prompt for VPN consent when `VpnService.prepare()` is not already satisfied. Disconnect does not require an admin prompt. | WireGuard only. OpenVPN and IKEv2 are unsupported in the Android app path. | Implemented but not release-proven; artifact blocked. | Android native service, manifest entry, Gradle WireGuard dependency, and release-signing guard exist. | Signed APK/AAB, device or emulator install, VPN consent flow, WireGuard connect/disconnect, route/DNS/public-IP proof, and Play distribution evidence. |
| iOS | iOS is `coming_soon` through TestFlight/App Store; Apple handoff zip exists. | Implemented but not public-release-proven. | Implemented but not release-proven for WireGuard. iOS Runner uses `NEVPNManager`; PacketTunnel uses WireGuardKit when linked. | Apple signing, Network Extension entitlement, and physical-device build are required. User/system VPN configuration approval may be required. | OS-managed VPN permission/configuration prompts may occur during profile save/start. | WireGuard only. OpenVPN and IKEv2 are unsupported in the iOS app path. | Implemented but blocked for public release. | iOS PacketTunnel target, entitlements, vendored WireGuardKit, setup docs, and Apple handoff docs exist. | Signed archive/export, physical-device install, App Store/TestFlight approval, connect/disconnect proof, route/DNS/public-IP proof, and cleanup proof. |

## Linux Architecture Truth

- This audit host is `aarch64` and Debian reports `arm64`.
- `securewave_app/scripts/build_deb.sh` uses `dpkg --print-architecture`; a
  local `.deb` built here is therefore ARM64.
- An ARM64 `.deb` can be validly built on this VM if the current tracked source
  and dependencies are correct.
- A Linux x64 `.deb` cannot be validly built or runtime-proven on this ARM64
  host.
- GitHub Actions `ubuntu-latest` can provide x64 build evidence because the
  `flutter-release.yml` Linux package job runs on `ubuntu-latest`.
- Final x64 helper/systemd proof is best performed on a clean `x86_64`
  Debian/Ubuntu/systemd VM after the artifact is built.

## Inspected Source And Evidence

Requested paths inspected:

- `securewave_app/scripts/build_deb.sh`
- `securewave_app/packaging/linux/` - absent from tracked `master`
- `securewave_app/linux/helperd/` - absent from tracked `master`
- `securewave_app/linux/runner/`
- `securewave_app/LINUX_VPN_SETUP.md`
- `securewave_app/WINDOWS_VPN_SETUP.md`
- `securewave_app/MACOS_VPN_SETUP.md`
- `static/downloads/manifest.json`
- `routes/downloads.py`
- `tests/unit/test_downloads_manifest.py`
- `docs/POST_MERGE_ENTERPRISE_RELEASE_TODO.md`
- `artifacts/post-merge-enterprise-release-evidence/README.md`

Additional current-tree checks:

- Windows, macOS, Android, and iOS native bridge code was inspected to avoid
  claiming VPN routing from setup docs alone.
- `static/downloads/securewave-linux-x64.tar.gz` and
  `static/downloads/securewave-app-linux-arm64.zip` were inspected with `file`;
  both contain an ARM aarch64 Linux binary.
- Download route detection was checked in the project virtualenv. A Linux x64
  user-agent currently receives `/downloads/securewave-linux-x64.tar.gz`,
  which is not a valid x64 runtime artifact.

## Release Gate Summary

Proven:

- Current host architecture is ARM64.
- Linux x64 `.deb` and x64 AppImage are not marked available in the manifest.
- macOS production VPN is disabled in current macOS code.
- Linux IKEv2 is blocked by backend tests and current runner behavior.

Implemented but not release-proven:

- Linux WireGuard command path. OpenVPN source command/helper paths remain in
  the baseline for audit context but are fail-closed and not release-proven.
- Windows WireGuard service path.
- Android WireGuard `VpnService` path.
- iOS WireGuard Network Extension path.

UI-only:

- macOS Apple Silicon UI demo.
- Linux portable ARM64 zip unless a separate privileged runtime install and
  protocol proof are completed.

Blocked:

- Linux x64 `.deb` publication and proof.
- Linux x64 tar claim, because the tracked tar contains an ARM64 binary.
- Linux x64 AppImage, because it is `coming_soon` and not built.
- Current no-connect-prompt Linux helper claim from tracked source, because the
  helper source/package paths are absent and the tracked runner still has
  direct `pkexec` paths.
- Windows installer publication.
- Android public APK/AAB publication.
- iOS TestFlight/App Store release.
- macOS production VPN release.

Unsupported:

- macOS VPN routing in current app.
- Linux IKEv2 runtime in current app.
- Windows OpenVPN/IKEv2 in current app.
- Android/iOS OpenVPN and IKEv2 in current app.
