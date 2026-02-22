# Production Hardening Report

Date: 2026-02-22
Branch: `release/multiprotocol-live-only`
Scope: Flutter client production hardening pass (routing, boot, session lifecycle, protocol adapter, validation hygiene)

## Outcome

Status: PASS (for requested local validation scope)

Evidence-based checks completed:
- `flutter clean` ✅
- `flutter analyze` ✅ (`No issues found!`)
- `flutter test` ✅ (`All tests passed!`)
- Demo/mock grep scan ✅ (no matches for runtime/test/workflow patterns queried)
- Silent catch grep scan (Flutter app runtime) ✅ (no `catch (_) {` matches)

## What Changed

### 1) Environment separation / hidden flag hardening
- Audited Flutter app code for debug/release divergence flags.
- Confirmed only expected hits remain:
  - `securewave_app/lib/core/logging/app_logger.dart` (`kReleaseMode` for log verbosity/in-memory retention only; non-behavioral)
  - `securewave_app/lib/core/config/app_config.dart` (`String.fromEnvironment(...)` for production config injection; expected)
- No hidden demo/mock/simulate flags found in scanned app/workflow scope.

### 2) Router hardening
- `securewave_app/lib/navigation/app_router.dart`
  - (existing prior fix retained) explicit redirect off `/boot` after boot completes
- `securewave_app/test/navigation/app_router_redirect_test.dart`
  - Added regression check for redirect convergence (no loop)

### 3) Session lifecycle hardening (JWT + secure storage)
- `securewave_app/lib/core/services/auth_session.dart`
  - Validates restored access token JWT `exp` on startup
  - Rejects and purges expired/invalid persisted JWTs during restore
  - Clears persisted VPN session artifacts on session clear/purge:
    - cached VPN profile config
    - profile expiry timestamp
    - VPN device id
  - Adds storage operation timeout protection
  - Adds structured error logging for restore/token parse failures
  - Compatibility: `setSession()` only enforces JWT validation for JWT-shaped tokens (keeps existing placeholder-token tests/flows working)
- `securewave_app/test/auth_session_lifecycle_test.dart` (new)
  - Valid JWT restores session
  - Expired JWT is purged on restore
  - Invalid token (reinstall-style stale secure storage) is purged
  - `clearSession()` removes persisted tokens and VPN session artifacts

### 4) Boot controller hardening
- `securewave_app/lib/core/bootstrap/boot_controller.dart`
  - Structured boot logs (`[BOOT] {...}` format)
  - Boot step logging for each startup phase
  - Restore-server failure now logs error details (not warning-only)
  - Step-level timeouts remain enforced (from prior patch) and are now part of this validation pass

### 5) Protocol adapter / no silent fallback hardening
- `securewave_app/lib/core/services/protocol_selector.dart`
  - `Automatic` protocol selection is no longer allowed when multiple runtimes are available
  - User must choose a concrete protocol explicitly in multi-runtime environments
  - `Automatic` still resolves when exactly one runtime exists (compatibility/single-runtime hosts)
- `securewave_app/lib/core/state/vpn_state.dart`
  - Removed cached WireGuard profile fallback on profile fetch failure (no silent local fallback)
  - Added explicit logging that fallback is disabled
  - Fixed startup race where async `_loadProtocol()` could overwrite a user-selected protocol back to `auto`
  - Replaced silent catch blocks in core VPN paths with logged best-effort handling
- `securewave_app/lib/core/services/vpn_service.dart`
  - Replaced silent unexpected catch in native status refresh path with logged failure
- `securewave_app/test/protocol_selector_test.dart`
  - Added/updated tests proving:
    - unsupported concrete protocols do not fallback to WireGuard
    - `Automatic` errors explicitly when multiple runtimes exist
    - `Automatic` resolves only when exactly one runtime exists

## Validation Evidence

### Commands Run (required)

1. `flutter clean`
- Result: PASS

2. `flutter analyze`
- Result: PASS
- Final output: `No issues found!`

3. `flutter test`
- Result: PASS
- Final output: `All tests passed!`

4. Demo/mock grep scan
- Command pattern:
  - `rg -n "DEMO_MODE|WG_MOCK_MODE|WG_SIMULATE|mock tunnel|simulate connect|fake success" securewave_app/lib securewave_app/test .github/workflows`
- Result: no matches (command exited with code `1`, expected for no matches)

5. Silent catch grep scan
- Command:
  - `rg -n "catch \\(_\\) \\{" securewave_app/lib -g'*.dart'`
- Result: no matches (command exited with code `1`, expected for no matches)

### Additional targeted proof runs used during hardening
- `flutter test test/auth_session_lifecycle_test.dart test/navigation/app_router_redirect_test.dart test/protocol_selector_test.dart -r expanded` ✅
- `flutter test test/state_machine/auto_connect_listener_test.dart -r expanded` ✅
- `flutter test test/performance/multiprotocol_performance_profile_test.dart -r expanded` ✅

## Files Changed (this pass)

- `securewave_app/lib/core/bootstrap/boot_controller.dart`
- `securewave_app/lib/core/services/auth_session.dart`
- `securewave_app/lib/core/services/protocol_selector.dart`
- `securewave_app/lib/core/services/vpn_service.dart`
- `securewave_app/lib/core/state/vpn_state.dart`
- `securewave_app/test/auth_session_lifecycle_test.dart` (new)
- `securewave_app/test/navigation/app_router_redirect_test.dart`
- `securewave_app/test/protocol_selector_test.dart`
- `securewave_app/lib/features/auth/register_page.dart` (analyze lint-only fixes)
- `securewave_app/lib/features/onboarding/feedback_sheet.dart` (analyze lint-only fixes)
- `securewave_app/test/state_machine/state_machine_stress_cycles_test.dart` (analyze lint-only fix)

## Risks Introduced

- `Automatic` protocol mode now errors when multiple runtimes are available; users on upgraded installs with `auto` selected must explicitly choose a protocol before connecting. This is intentional hardening but is a UX behavior change.
- `AuthSession` now purges invalid/expired persisted JWTs at startup; if a backend or test fixture stores non-JWT tokens directly in secure storage, users will be signed out on restart. (`setSession()` remains compatible with non-JWT placeholders.)
- `clearSession()` now removes cached VPN profile artifacts and VPN device ID. This improves security but may force reprovisioning on next connect.

## What Was Not Touched

- Backend JWT refresh / token rotation logic (server-side and client refresh flow)
- Native VPN connector implementations (Linux/Windows/macOS method-channel runtime code)
- Protocol capability matrix definitions (`protocol_capabilities.dart`)
- Release packaging/manifest pipeline
- Website download UX

## Remaining Blockers

- No blocker for the requested local hardening validation scope.
- Follow-up recommendation (not required for this pass): implement explicit client-side access-token refresh/401 session invalidation flow if not already handled elsewhere; this pass hardens restore-time JWT expiry and logout cleanup but does not add a refresh protocol.
