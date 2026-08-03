# SecureWave Cross-Platform Linux Parity Conversion

## Executive Summary

This pass aligns convertible Flutter UI surfaces with the canonical Linux release-candidate truth while preserving runtime and certificate boundaries.

The app now has a shared release-truth model for platform messaging. Auth, VPN home, diagnostics, settings, account, and the mobile drawer all read the same Linux RC / WireGuard-primary / Free-now / Premium-coming-soon truth instead of carrying separate hand-written platform copy.

No VPN runtime, protocol behavior, backend/provider logic, native Apple entitlement scope, Linux helper behavior, packaging truth, or dependency versions were changed.

## Files Added

| File | Purpose |
| --- | --- |
| `securewave_app/lib/core/release/platform_release_truth.dart` | Central read-only product/release truth for Linux, macOS, iOS, Android, Windows, web, and unsupported platforms. |
| `securewave_app/lib/ui/platform_truth_card.dart` | Shared premium SecureWave UI primitive for platform runtime and release-scope messaging. |

## Files Updated

| File | Convertible surface aligned |
| --- | --- |
| `securewave_app/lib/features/vpn/vpn_page.dart` | Uses the shared platform truth card and release-boundary copy for runtime notices. |
| `securewave_app/lib/features/diagnostics/diagnostics_page.dart` | Native VPN bridge diagnostics and copied diagnostic payload now include canonical release/runtime truth. |
| `securewave_app/lib/features/auth/auth_entry_shell.dart` | Auth footer now pairs the Linux RC label with the current platform runtime status. |
| `securewave_app/lib/features/account/account_page.dart` | Free plan feature copy now uses canonical WireGuard and release labels. |
| `securewave_app/lib/features/settings/settings_page.dart` | Security/About sections now expose the same platform truth and release scope. |
| `securewave_app/lib/core/routing/app_shell.dart` | Mobile drawer branding now shows the canonical Linux release-candidate label. |

## Product Truth Preserved

- Public v1 remains Linux desktop only.
- WireGuard remains the primary public release protocol.
- OpenVPN remains limited to the covered Linux helper path.
- IKEv2 remains not public v1 release-visible.
- Free mode remains current.
- Premium remains coming soon.
- macOS/iOS remain demo/UI paths unless Apple Network Extension entitlement, signing, packet tunnel, and physical-device validation are completed.
- iOS Simulator remains UI-demo only and cannot claim packet-tunnel runtime parity.

## Protected Boundaries

- No changes to `securewave_app/lib/core/services/vpn_service.dart`.
- No changes to `securewave_app/lib/core/state/vpn_state.dart`.
- No changes to Linux helper/native runner behavior.
- No changes to backend/provider contracts.
- No dependency or lockfile changes.
- No Apple signing team, provisioning profile, or entitlement broadening.
- No release-scope broadening.

## Conversion Notes

The converted surfaces are presentation-only and can be reused across Linux, macOS, iOS, Android, Windows, and web builds. The platform helper makes the distinction explicit:

- Linux: public RC runtime.
- macOS: demo UI only until Network Extension release work is complete.
- iOS: simulator/demo UI only; real VPN needs entitlement and physical device.
- Android/Windows/web: shared UI can be demonstrated, but public VPN runtime remains out of scope.

## Remaining Work

- Full macOS VPN runtime parity requires Apple entitlement/certificate approval, a macOS packet tunnel target, signing, notarization, and release-grade validation.
- Full iOS VPN runtime parity requires physical-device packet tunnel testing under an entitled Apple team.
- Android and Windows require separate runtime certification before public release claims.
