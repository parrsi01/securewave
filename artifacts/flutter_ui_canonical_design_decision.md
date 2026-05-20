# SecureWave Canonical UI Design Decision

## Decision

The canonical SecureWave app UI is the latest premium Flutter design system from:

- Branch: `codex/flutter-ui-design-system-foundation`
- Commit: `7040820`
- Commit title: `Polish SecureWave Flutter UI overhaul`

This design has been promoted to `master` so Linux and macOS builds from the same branch use the same visual system.

## Canonical Visual Direction

- Dark navy to rich blue SecureWave background.
- Lighter blue and restrained cyan accents.
- Premium glass/control-surface treatment.
- iOS-class spacing and interaction polish that also scales to Linux desktop, macOS, iPad/tablet, Android/mobile, and desktop/laptop.
- Truthful release messaging: Linux desktop release candidate, WireGuard primary, Free mode now, Premium coming soon.

## Historical Designs Not Canonical

| Historical source | Visual style | Current status |
| --- | --- | --- |
| Earlier `master` before this promotion | Old white + teal/green Linux RC baseline login. | Superseded on `master` by the premium dark-blue UI. |
| `2a0ef86` | Purple checkpoint with dark neutral background and neon purple centered login. | Historical reference only. Do not reintroduce as active app theme. |
| Deep Ocean / app-first era | Earlier dark ocean-blue app-first styling. | Historical reference only. |
| `origin/codex/premium-flutter-ui` | Earlier premium dark/glass pass. | Superseded by `7040820`. |

## Current Code

The current active app visual system is centered in:

- `securewave_app/lib/ui/app_ui_v1.dart`
- `securewave_app/lib/features/auth/auth_entry_shell.dart`
- `securewave_app/lib/features/vpn/vpn_page.dart`
- `securewave_app/lib/features/vpn/protocol_selection_panel.dart`
- `securewave_app/lib/features/settings/settings_page.dart`
- `securewave_app/lib/features/account/account_page.dart`
- `securewave_app/lib/features/diagnostics/diagnostics_page.dart`
- `securewave_app/lib/core/routing/app_shell.dart`

## Protected Boundaries

- Do not change VPN runtime behavior as part of visual alignment.
- Do not broaden public release scope.
- Do not claim macOS/iOS/Android/Windows VPN runtime parity until platform-specific certification is complete.
- Do not reintroduce Azure or old multi-platform readiness claims.
- Do not use historical purple or white/green palettes for active app screens unless explicitly requested.
