# SecureWave Flutter UI Supporting Surfaces Overhaul

Date: 2026-05-09

## Executive Summary

This pass rebuilt the supporting SecureWave Flutter surfaces around the new premium dark navy / blue / cyan design system while preserving runtime, telemetry, protocol, backend, and release-candidate truth.

Diagnostics remain read-only and provider/API-backed. Usage and plan presentation still comes from `userPlanProvider`. Speed values were not invented or moved into supporting screens. Premium messaging now stays aligned with the current truth: Free mode is available now, Premium is coming soon.

## Supporting Surfaces Rebuilt

| Surface | Files | What changed | Truth preserved |
| --- | --- | --- | --- |
| Full diagnostics | `securewave_app/lib/features/diagnostics/diagnostics_page.dart` | Rebuilt as a premium technical status surface with read-only check cards, OK/warning/failure counts, clear empty/error states, copy diagnostics, and cache clear action styling. | Existing check functions, endpoints, secure-storage reads, copy payload, and cache clear behavior preserved. |
| Quick connection diagnostics | `securewave_app/lib/features/diagnostics/connection_diagnostics_sheet.dart` | Rebuilt the modal into a polished glass diagnostic sheet with status rows, refresh affordance, and constrained desktop/tablet sizing. | Existing backend/auth/profile/native tunnel checks preserved. |
| Account, usage, and plan | `securewave_app/lib/features/account/account_page.dart` | Rebuilt plan and usage presentation with provider-backed usage ring, usage metrics, portal access, Free active state, and Premium coming-soon card. | No fake paid state, no fake unlimited state, no fake speed values, no provider changes. |
| Settings | `securewave_app/lib/features/settings/settings_page.dart` | Rebuilt settings into responsive device, language, connection, security, diagnostics, and about sections using shared surfaces. | Existing navigation/actions preserved. Protocol selection still uses the existing UI selector and provider notifier. |
| Language | `securewave_app/lib/features/settings/language_page.dart` | Rebuilt language selection with SecureWave surfaces and retained the existing preference update path. | Existing `preferencesProvider.notifier.setLanguage` behavior preserved. |
| Panic recovery | `securewave_app/lib/features/panic/panic_page.dart` | Rebuilt the emergency recovery presentation and progress/status panels. | Existing disconnect, secure-storage clear, server preference rotation, sign-out, and haptics behavior preserved. |
| Startup fallback diagnostics | `securewave_app/lib/features/bootstrap/fallback_error_screen.dart` | Rebuilt fallback error diagnostics into a premium support surface with a stronger diagnostic payload area. | Existing diagnostic payload generation and copy-to-clipboard flow preserved. |
| Drawer premium label | `securewave_app/lib/core/routing/app_shell.dart` | Changed the drawer label from "Upgrade plan" to "Premium updates". | Existing configured URL target preserved; no paid-state activation implied. |

## Protected Boundaries

- No runtime/protocol logic changes.
- No Linux helper behavior changes.
- No backend/provider/release truth changes.
- No dependency upgrades or lockfile changes.
- No fake connected, diagnostic, speed, usage, premium, or readiness state.
- No change to public v1 protocol scope: Linux desktop remains the public release-candidate scope, WireGuard remains primary, OpenVPN remains restricted, and IKEv2 remains not public v1-visible.

## Design Rules Applied

- Premium high-tech control surfaces using the existing SecureWave design-system foundation.
- Dark navy/blue glass surfaces, cyan/blue accents, restrained warning/danger states.
- Responsive single-column mobile layouts and two-column tablet/desktop layouts where appropriate.
- Diagnostics are technical but structured: status first, details second, copy/export preserved.
- Usage and plan data are presented as measured values from providers, not as marketing promises.
- Premium language is non-blocking and explicitly coming soon.

## Validation

- `flutter analyze`: PASS.
- `flutter test`: PASS.
- `git diff --check`: PASS.

Note: Flutter reported newer package versions during dependency resolution, but no dependency constraints or lockfiles were changed in this pass.

## Remaining Visual Debt

- No dedicated help/legal screen exists in the current Flutter route set; only fallback diagnostics, settings diagnostics, account portal, and panic recovery were available to rebuild.
- App shell/drawer was only minimally touched for truth-aligned premium labeling; a full shell visual rebuild remains outside this supporting-surfaces prompt.
- Speed values remain on the operational VPN home surface where they are sourced from VPN state; supporting screens do not duplicate or simulate live speed gauges.

## Strict Change Log

What changed:
- Rebuilt diagnostics, quick diagnostics, account/usage, settings, language, panic recovery, and startup fallback diagnostics presentations.
- Updated drawer premium wording to "Premium updates".
- Tightened settings security copy to profile/platform-dependent language.

What was reused:
- Existing SecureWave design-system foundation.
- Existing Riverpod providers, route targets, diagnostics functions, VPN state, auth session, secure storage, external link service, and app configuration.
- Existing account portal and upgrade URL configuration.

What was intentionally left untouched:
- Runtime protocol logic and Linux helper behavior.
- Backend/catalog/provider semantics.
- Dependency manifests and lockfiles.
- Release visibility rules for WireGuard, OpenVPN, and IKEv2.
- VPN speed generation/state semantics.

Risks introduced:
- Visual/layout risk only: the supporting surfaces now use denser custom SecureWave surfaces, so final device screenshot QA should still verify small phone heights and wide desktop drawer/modal composition.
