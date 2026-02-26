# SecureWave Rescue Restore Functionality Report (2026-02-26)

## Objective
Recover from regressions introduced by commits `b7b5254` and `7c02065`, restore stable Linux desktop behavior, and keep only minimal verified fixes.

## What Was Reverted
- Reverted commit `b7b5254` (large multiprotocol/UI/native/backend changes).
- Reverted commit `7c02065` (follow-up CI/config changes that came with the regression window).

Rationale:
- Regressions were broad and high-risk; rollback to the known-good baseline behavior (`d92b458`) was safer than debugging forward.

## What Was Re-Applied (Minimal)
1. `securewave_app/pubspec.yaml`
- Kept `.env` removed from Flutter assets to avoid CI/runtime asset packaging issues.

2. `securewave_app/lib/core/services/protocol_selector.dart`
- Minimal deterministic `auto` behavior when multiple local runtimes are present:
  - Priority: WireGuard > OpenVPN > IKEv2
  - Returns warning instead of hard error.

3. `securewave_app/test/protocol_selector_test.dart`
- Updated expectation for deterministic `auto` resolution.

4. `securewave_app/test/state_machine/state_machine_test_harness.dart`
- Removed stale privilege-automation method overrides no longer present in the service interface.

5. `tools/runtime_probe/tunnel_probe.sh` and `tools/runtime_probe/run_probe.sh`
- Restored deterministic runtime probe harness (manual-friendly, no GUI automation required).

## Functional Verification
### Build + run
- `flutter build linux`: success
- `flutter run -d linux -v`: app launches successfully
- Startup connect path is live; unauthenticated session correctly fails with HTTP 401 (expected without valid token/session).

### Tests
- `flutter test`: passed (full suite)

### Runtime dataplane probe
- Probe output: `tools/runtime_probe/out/20260226_231936/REPORT.md`
- Verified:
  - Tunnel interface up on connect
  - Route decision switches through `sw-wg`
  - Egress IP changes on connect and reverts on disconnect
  - Post-disconnect cleanup succeeds

## What Remains Broken / External
- OpenVPN and IKEv2 availability depends on backend/server provisioning and local runtime/elevation readiness.
- Rescue pass does not force-enable unavailable protocols; it preserves truthful capability behavior.

## Re-run Commands
```bash
cd /home/sp/cyber-course/projects/securewave/securewave_app
flutter clean
flutter pub get
flutter build linux
flutter test
flutter run -d linux -v
```

```bash
cd /home/sp/cyber-course/projects/securewave
./tools/runtime_probe/tunnel_probe.sh \
  --connect-cmd 'pkexec /usr/local/libexec/securewave-wg-quick up /home/sp/.config/securewave/sw-wg.conf' \
  --disconnect-cmd 'pkexec /usr/local/libexec/securewave-wg-quick down /home/sp/.config/securewave/sw-wg.conf'
```

## Risk Notes
- Auto-protocol deterministic selection now prefers WireGuard when multiple runtimes exist; this is intentional for reliability but changes previous strict-manual selection behavior.
- Runtime probe scripts are shell-based operational tooling and should be run in controlled environments.
