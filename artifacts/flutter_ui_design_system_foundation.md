# SecureWave Flutter UI Design System Foundation

Date: 2026-05-08

## Executive Summary

This pass installed the foundation for a premium SecureWave Flutter UI overhaul without rebuilding screens or changing release/runtime truth. The active app theme and shared UI primitives now define a dark navy, rich blue, lighter blue, and restrained cyan visual system suitable for iOS-first product quality while preserving Linux desktop release-candidate stability.

No protocol behavior, provider behavior, Linux helper behavior, backend behavior, package metadata, lockfiles, routing contracts, or public release scope were changed.

## Design System Files

| File | Role | Status |
| --- | --- | --- |
| `securewave_app/lib/ui/app_ui_v1.dart` | Canonical Flutter design-system foundation for this pass: colors, typography, spacing, radii, borders, glow/shadow, motion, responsive rules, theme wiring, and shared primitives. | Updated |
| `artifacts/flutter_ui_design_system_foundation.md` | Durable implementation notes, protected boundaries, and migration plan. | Added |

## Flutter UI Structure Inspected

| Area | Representative files inspected | Result |
| --- | --- | --- |
| App theme | `securewave_app/lib/ui/app_ui_v1.dart`, `securewave_app/lib/app.dart` | `AppUIv1.theme()` remains the app-wide theme entry point. |
| Shell/navigation | `securewave_app/lib/router.dart`, `securewave_app/lib/core/routing/app_shell.dart` | Existing routing and shell behavior were preserved. |
| Auth | `securewave_app/lib/features/auth/login_page.dart`, `securewave_app/lib/features/auth/register_page.dart`, `securewave_app/lib/features/auth/forgot_password_page.dart` | Screen rebuild deferred; foundation now supplies tokens and primitives for later auth migration. |
| Dashboard/VPN | `securewave_app/lib/features/vpn/vpn_page.dart` | Runtime/provider behavior left untouched. |
| Diagnostics | `securewave_app/lib/features/diagnostics/diagnostics_page.dart` | Diagnostics behavior and data display left untouched. |
| Settings/account | `securewave_app/lib/features/settings/settings_page.dart`, `securewave_app/lib/features/account/account_page.dart` | Screen rebuild deferred; settings/account stay inside safe UI-only surface for later migration. |
| Shared widgets/components | `securewave_app/lib/features/*`, `securewave_app/lib/ui/app_ui_v1.dart` | Stale white/teal app primitive was neutralized at the theme/token layer. |

## Foundation Installed

### Color Tokens

The previous white/teal app palette was replaced with a premium secure-dark palette:

| Token group | Purpose |
| --- | --- |
| `background`, `backgroundStrong`, `backgroundElevated` | App/page backing colors for dark navy depth. |
| `surface`, `surfaceRaised`, `surfaceMuted`, `surfaceGlass`, `surfaceOverlay` | Control and panel surfaces. |
| `accent`, `accentStrong`, `accentBlue`, `accentCyan`, `accentSoft` | Brand action color, blue gradient depth, and restrained cyan/teal accenting. |
| `success`, `warning`, `danger` | State colors for VPN status, diagnostics, and validation messaging. |
| `ink`, `inkMuted`, `inkSoft`, `inkDisabled`, `border`, `borderStrong`, `divider` | Text, border, disabled, and separation rules for dark surfaces. |

### Typography

`AppUIv1.theme()` now defines an explicit dark text scale:

| Scale | Rule |
| --- | --- |
| Display/headline/title | Compact premium hierarchy with strong weights and zero letter spacing. |
| Body | High contrast white/blue-gray copy on dark surfaces with readable line height. |
| Labels | Dense, clear control and status labels with zero letter spacing. |
| Linux font safety | The existing Linux system-font guard was preserved to avoid Skia rendering crashes. |

### Spacing, Radius, Border, Elevation, Glow

| Token group | Rule |
| --- | --- |
| Spacing | 8dp grid extended through `space9`. |
| Radius | Small cards remain 8px through `radiusCard`; larger radii are available for controls and panels. |
| Border | Low-alpha blue borders separate glass/dark surfaces without bright outlines. |
| Elevation | Dark-mode shadows use black alpha and restrained blur. |
| Glow | Glow is limited to component shadow tokens for selected/accent/state surfaces. No decorative background orb primitives are included. |

### Motion

Motion tokens now define fast, normal, slow, enter, exit, and emphasized curves. Platform transitions preserve Cupertino transitions on iOS/macOS and use a bounded fade/slide transition on Linux, Windows, Android, and Fuchsia.

### Responsive Layout Rules

| Rule | Value |
| --- | --- |
| Compact breakpoint | `< 600px` |
| Medium breakpoint | `600px - 899px` |
| Expanded breakpoint | `>= 900px` |
| Desktop breakpoint | `>= 1200px` |
| Auth max width | `440px` |
| Content max width | `720px` |
| Wide content max width | `1040px` |
| Shell max width | `1280px` |

`AppUIv1.pagePaddingFor()` and `AppUIv1.maxContentWidthFor()` provide the canonical responsive rules for later screen migrations.

### Shared Surface Primitives

| Primitive | Purpose |
| --- | --- |
| `SecurePageBackground` | Full-page SecureWave navy/blue gradient backing for future migrated screens. |
| `SecureResponsiveFrame` | Responsive constrained layout wrapper for phone, tablet, iPad, desktop, and Linux. |
| `SecureSurface` | Shared surface primitive with base, raised, glass, accent, success, warning, and danger variants. |
| `SecureStatePill` | Compact status label primitive for VPN, diagnostics, and account states. |
| `SecureSurfaceVariant` | Explicit enum for surface intent instead of ad hoc color choices. |

## Visual Language Rules

1. Use dark navy as the dominant app environment.
2. Use rich blue and lighter blue for primary brand action and hierarchy.
3. Use cyan/teal sparingly for technical/security accents, connection emphasis, and selected state.
4. Keep surfaces quiet: glass, subtle borders, restrained component glow, and precise typography.
5. Do not reintroduce the old split-login white/teal residue.
6. Do not introduce generic fintech/SaaS hero cards, marketing clutter, chatbot surfaces, or fake readiness copy.
7. Keep UI copy consistent with product truth: Linux desktop public v1, WireGuard primary, OpenVPN only where already certified, IKEv2 not public release-visible, free mode now, premium coming soon.
8. Favor iPhone-quality interaction density and polish, but keep layout constraints suitable for desktop, iPad, tablet, Android/mobile, and Linux.

## Safe UI Edit Surface

Future UI-only migration prompts may edit:

| Surface | Allowed scope |
| --- | --- |
| `securewave_app/lib/ui/**` | Tokens, theme, shared visual primitives, UI-only helper widgets. |
| `securewave_app/lib/core/routing/app_shell.dart` | Visual shell and navigation presentation only. |
| `securewave_app/lib/features/auth/**` | Auth screen layout/styling only. |
| `securewave_app/lib/features/vpn/vpn_page.dart` | Dashboard presentation only; no provider/runtime actions. |
| `securewave_app/lib/features/diagnostics/**` | Diagnostics presentation only; no diagnostics data collection changes. |
| `securewave_app/lib/features/settings/**` | Settings presentation only; no runtime/config semantics changes. |
| `securewave_app/lib/features/account/**` | Account presentation only; no billing/auth/provider semantics changes. |
| `securewave_app/test/**` | Narrow widget/regression tests when UI behavior changes. |

## Protected Boundaries

Do not touch these areas during UI foundation or screen migration work unless a later prompt explicitly authorizes it:

| Boundary | Protection rule |
| --- | --- |
| `securewave_app/lib/core/services/**` | No runtime, subprocess, WireGuard/OpenVPN/helper, network, auth, storage, or provider behavior changes. |
| `securewave_app/lib/core/state/**` | No VPN state-machine, connection, kill-switch, or protocol behavior changes. |
| `securewave_app/linux/**` | No Linux helper, desktop integration, CMake, native runner, or release-candidate runtime changes. |
| `securewave_app/macos/**`, `securewave_app/ios/**`, `securewave_app/android/**`, `securewave_app/windows/**` | No platform scope broadening or native runtime changes. |
| `securewave_app/pubspec.yaml`, `securewave_app/pubspec.lock` | No dependency or lockfile changes for visual migration unless separately approved. |
| `backend/**`, `api/**`, `server/**` if present | No backend/provider/API truth changes from UI work. |
| `scripts/**`, `packaging/**`, release artifacts | No install/package/release truth changes from UI work. |
| Security/remediation artifacts | Do not rewrite previous audit/remediation truth from UI work. |

## State Color Rules

| State | Color rule |
| --- | --- |
| Connected/healthy | `AppUIv1.success` |
| Connecting/syncing/transient | `AppUIv1.accentSun` |
| Warning/setup/unavailable | `AppUIv1.warning` |
| Error/unreachable/attention required | `AppUIv1.danger` |
| Neutral/unknown | `AppUIv1.inkSoft` |

`AppUIv1.statusColorForLabel()` exists as a lightweight bridge for current label-driven screens. Later migrations should prefer explicit state enums where available rather than parsing user-visible copy.

## Migration Plan For Later Prompts

1. Auth migration: rebuild login, register, and forgot-password screens using `SecurePageBackground`, `SecureResponsiveFrame`, and `SecureSurface` while removing old split-login residue.
2. Shell migration: update app shell navigation presentation with dark glass surfaces and responsive rail/bottom-nav rules, without route changes.
3. VPN dashboard migration: rebuild `vpn_page.dart` presentation around connection status, primary action, server selection, and release-truth messaging, without touching providers or runtime actions.
4. Diagnostics migration: restyle diagnostic surfaces and status pills, preserving diagnostic data flow and failure semantics.
5. Settings/account migration: restyle settings and account surfaces while preserving free-now, premium-coming-soon, and Linux-only public v1 truth.
6. Regression coverage: add widget tests only where migrated screen behavior or layout contracts materially change.

## Validation Snapshot

| Command | Result |
| --- | --- |
| `flutter analyze` from `securewave_app/` | Passed: no issues found. |
| `flutter test` from `securewave_app/` | Passed: all tests passed. |
| `git diff --check` | Passed: no whitespace errors. |

## Intentional Non-Changes

1. No screen rebuild was performed.
2. No runtime/protocol/provider/backend behavior was changed.
3. No Linux helper behavior was changed.
4. No Flutter dependency or lockfile was changed.
5. No public release scope was broadened.
6. No Azure, IKEv2, premium readiness, or unsupported platform claim was introduced.

## Risks And Controls

| Risk | Control |
| --- | --- |
| Existing screens now inherit a dark theme before full screen-by-screen polish. | Kept public `AppUIv1` names stable and ran `flutter analyze` plus `flutter test`. |
| Future migrations may accidentally cross into runtime behavior. | Protected boundaries and safe UI edit surface are explicitly defined above. |
| Visual consistency depends on later adoption of shared primitives. | Migration plan uses one primitive set instead of per-screen ad hoc styling. |
