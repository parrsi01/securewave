# SecureWave Flutter UI Refactor Report
## Native-Grade Polish Pass

**Date:** 2026-02-05
**Reviewer:** Claude Opus (Flutter Architect + UI Polish Specialist)

---

## 1) FILES CHANGED / ADDED

### Changed

| File | Reason |
|------|--------|
| `securewave_app/lib/ui/app_ui_v1.dart` | Extended design tokens: added animation durations/curves, border radii scale, shadows, layout constraints, `isApplePlatform` helper. Replaced basic fade transitions with Cupertino on iOS/macOS and fade+slide on other platforms. Added nav bar/rail theming. |
| `securewave_app/lib/router.dart` | Platform-adaptive page transitions: `CupertinoPage` on Apple, `CustomTransitionPage` with fade+slide elsewhere. Removed the old `_fadePage` helper. |
| `securewave_app/lib/core/routing/app_shell.dart` | Full navigation refactor: logo in drawer header + desktop rail. Animated status dot in app bar. Outlined/filled icon variants for nav destinations. Separated `_DesktopRail`, `_AppDrawer` into focused widgets. Removed redundant status chip from app bar (moved to VPN page hero). |
| `securewave_app/lib/features/vpn/vpn_page.dart` | Major refactor: hero circular connect button with animated ring/glow, `AnimatedSwitcher` on status text, `AnimatedOpacity` on live metrics, server selection as tappable card row, error messages in styled container. Max-width constraint for desktop. |
| `securewave_app/lib/features/bootstrap/boot_screen.dart` | Centered layout with logo, rounded progress bar, `AnimatedOpacity` on log panel, `AnimatedSwitcher` on status text. Max-width constraint. |
| `securewave_app/lib/features/auth/login_page.dart` | Center-aligned layout with `ConstrainedBox(maxWidth: 440)` for desktop. Text centered. More generous spacing. |
| `securewave_app/lib/features/auth/register_page.dart` | Same desktop centering treatment as login. |
| `securewave_app/lib/features/servers/servers_page.dart` | Max-width constraint. `AnimatedContainer` on selection border. `AnimatedSwitcher` on favorite star. |
| `securewave_app/lib/features/settings/settings_page.dart` | Max-width constraint. Merged device info + language into single card. Compact ad-block layout (rules count + update button in row). Reduced description verbosity. |
| `securewave_app/lib/features/account/account_page.dart` | Max-width constraint. Merged plan summary into single card. Responsive plan cards at 480px breakpoint (was 720px). Added chevron to portal link. |

### Added

| File | Reason |
|------|--------|
| `securewave_app/scripts/run_dev.sh` | Dev runner: detects OS, runs `flutter pub get`, launches for current platform. |

---

## 2) COMMANDS TO RUN PER PLATFORM

### Linux
```bash
cd securewave_app
flutter pub get
flutter run -d linux
# Or use the dev script:
bash scripts/run_dev.sh
```

### macOS
```bash
cd securewave_app
flutter pub get
flutter run -d macos
# For iOS:
cd ios && pod install --repo-update && cd ..
flutter run -d <device-id>
# IMPORTANT: Always use Runner.xcworkspace, never .xcodeproj
```

### Windows
```bash
cd securewave_app
flutter pub get
flutter run -d windows
```

### Android
```bash
cd securewave_app
flutter pub get
flutter run -d <device-id>
```

---

## 3) VERIFICATION OUTPUTS

### Flutter Analyze
```
8 info-level issues (all pre-existing RadioListTile deprecation warnings)
0 errors, 0 warnings
```

### Linux Build
```
Dart compilation: PASS
Native C compilation: FAIL (pre-existing issue in my_application.cc)
  - g_spawn_check_exit_status deprecated → use g_spawn_check_wait_status
  - fl_method_channel_set_method_call_handler API changed
  Note: These are Codex's native VPN bridge issues, not from this UI refactor
```

---

## 4) CHANGELOG

### What Changed (UX Before → After)

| Area | Before | After |
|------|--------|-------|
| **VPN connect** | Text button ("Connect") inside a card | Large circular hero button with animated ring, color glow on connected state |
| **Status display** | Status text + chip side-by-side in card | Centered `AnimatedSwitcher` label below hero button |
| **Server selection** | "Choose a server" outlined button inside status card | Standalone tappable card row with server name, globe icon, chevron |
| **Live metrics** | Plain text in separate card | Compact side-by-side tiles with icons, fades in on connect |
| **Page transitions** | 120ms fade on all platforms | Cupertino slide on iOS/macOS; 250ms fade+slide on others |
| **Navigation (mobile)** | Outlined icons only | Outlined (default) + filled (selected) icon variants |
| **Navigation (desktop)** | Nav rail without branding | Nav rail with logo, animated status dot, logout at bottom |
| **Drawer** | Text-only header | Logo + status indicator header |
| **App bar** | Page title + status chip + logout | "SecureWave" title with animated status dot + logout |
| **Boot screen** | Left-aligned text, full-size log | Centered logo + text, rounded progress bar, faded log panel |
| **Auth pages (desktop)** | Full-width forms stretching to edge | 440px max-width centered forms |
| **All pages (desktop)** | Content stretching full width | 720px max-width centered content |
| **Settings** | Device info + language as separate cards | Merged into single card; compact ad-block section |
| **Account plan** | Two separate cards (plan + data usage) | Single combined card |

### What Reused
- All colors, logo, font (Manrope) — brand identity untouched
- All existing Riverpod state management — no state changes
- All VPN platform bridges (Android/Windows/Linux/iOS) — untouched
- All backend API integration — untouched
- All feature logic (login, register, servers, settings, account) — untouched

### What Intentionally Left Untouched
- `language_page.dart` — Pre-existing RadioListTile deprecation, not in scope
- Native platform code (Kotlin, Swift, C++, C) — out of scope for UI refactor
- `pubspec.yaml` — No new dependencies needed
- CI/CD workflows — no changes
- Release scripts — no changes

### Risks Introduced
| Risk | Severity | Mitigation |
|------|----------|------------|
| `CupertinoPageTransitionsBuilder` import | LOW | Already bundled with Flutter material; no extra dep |
| AnimatedContainer in connect button | LOW | Uses implicit animations, no custom controller jank |
| `ConstrainedBox` on all pages | LOW | Falls back gracefully on small screens (no effect below maxWidth) |
| `flutter_svg` now used in boot_screen + app_shell | LOW | Already a dependency in pubspec.yaml |

---

## 5) REMAINING HUMAN-ONLY TASKS

### Apple Signing & Entitlements

**Task:** Configure iOS/macOS code signing and Network Extension entitlement.

```bash
# 1. In Apple Developer Portal:
#    - Create App ID: com.securewave.app
#    - Enable "Network Extensions" capability
#    - Enable "Personal VPN" capability
#    - Create provisioning profiles (Development + Distribution)

# 2. In Xcode (open Runner.xcworkspace, NOT .xcodeproj):
#    - Set Team to your Apple Developer Team
#    - Set Bundle Identifier to com.securewave.app
#    - Under Signing & Capabilities, add:
#      - Network Extensions → Packet Tunnel
#      - Personal VPN

# 3. For the PacketTunnel extension:
#    - Same App ID prefix: com.securewave.app.PacketTunnel
#    - Same Network Extension + Personal VPN capabilities
```

**Files that need entitlement updates:**
```
securewave_app/macos/Runner/Release.entitlements
  ADD: com.apple.developer.networking.networkextension → packet-tunnel-provider
```

### PrivacyInfo.xcprivacy (iOS)

**Task:** Already created by Codex. Verify it's included in the Xcode project.

```bash
# Verify in Xcode:
# Runner target → Build Phases → Copy Bundle Resources
# Must include PrivacyInfo.xcprivacy for both Runner and PacketTunnel
```

### SMTP Credentials

**Task:** Configure email delivery for production.

```bash
# In GitHub Secrets:
SMTP_HOST=smtp.sendgrid.net          # or your provider
SMTP_PORT=587
SMTP_USER=apikey                     # for SendGrid
SMTP_PASSWORD=SG.xxxxx              # your API key
FROM_EMAIL=noreply@securewave.app
```

### Encryption Keys

**Task:** Generate and store Fernet keys.

```bash
pip install cryptography
python -c 'from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())'
# → Copy to GitHub Secret: AUTH_ENCRYPTION_KEY

python -c 'from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())'
# → Copy to GitHub Secret: WG_ENCRYPTION_KEY
```

### Android Keystore

**Task:** Create release signing keystore.

```bash
keytool -genkey -v -keystore securewave-release.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias securewave

base64 -w 0 securewave-release.jks > keystore-base64.txt
# → Copy to GitHub Secret: ANDROID_KEYSTORE_BASE64
# → Set ANDROID_KEYSTORE_PASSWORD, ANDROID_KEY_ALIAS, ANDROID_KEY_PASSWORD
```

### Linux Native Build Fix

**Task:** Update `my_application.cc` for newer GTK/Flutter API.

```c
// Replace all occurrences of:
g_spawn_check_exit_status(exit_status, &error)
// With:
g_spawn_check_wait_status(exit_status, &error)

// Update fl_method_channel_set_method_call_handler call
// to match Flutter 3.32+ API signature
```

### macOS VPN Bridge

**Task:** Implement VPN MethodChannel handler in `AppDelegate.swift`.
Currently only logs errors. Needs WireGuardKit integration similar to iOS PacketTunnel.

---

## UI POLISH CHECKLIST (for future changes)

When making UI changes, verify:

- [ ] Uses `AppUIv1.space*` for all spacing (never raw pixel values)
- [ ] Uses `AppUIv1.radius*` for border radii
- [ ] Uses `AppUIv1.duration*` and `AppUIv1.curve*` for animations
- [ ] Pages wrapped in `Center` + `ConstrainedBox(maxWidth: contentMaxWidth)` for desktop
- [ ] Auth pages use `authMaxWidth` (440px)
- [ ] Content pages use `contentMaxWidth` (720px)
- [ ] Status colors use the canonical switch on `VpnStatus`
- [ ] No hardcoded colors — use `AppUIv1.*` constants
- [ ] All pages have `SafeArea` wrapping
- [ ] Interactive elements have clear tap targets (48px minimum)
- [ ] Animations are implicit where possible (`AnimatedContainer`, `AnimatedSwitcher`)
- [ ] No `Hero` widgets unless genuinely transitioning between routes
