# Rescue Build & Test Report (2026-02-26)

## Scope
Recovery validation after reverting regression commits `b7b5254` and `7c02065` and re-applying only minimal safe fixes.

## Build Verification

### Commands
```bash
cd securewave/securewave_app
flutter clean
flutter pub get
flutter build linux
```

### Results
- `flutter clean`: success
- `flutter pub get`: success
- `flutter build linux`: success (`build/linux/arm64/release/bundle/securewave_app`)

## Runtime Verification

### Command
```bash
cd securewave/securewave_app
flutter run -d linux -v
```

### Results
- Linux desktop app launches and attaches to VM service.
- No compile/runtime blocker in startup path.
- Auto protocol now resolves to WireGuard-first when multiple runtimes are present.
- Connection attempts require valid auth/profile as expected (401 observed when token invalid).

## Test Verification

### First run
```bash
cd securewave/securewave_app
flutter test
```
- Failed initially due test harness drift:
  - `test/state_machine/state_machine_test_harness.dart` still referenced removed `VpnPrivilegeAutomationStatus` methods.

### Minimal fix applied
- Removed stale privilege-automation overrides from `ControlledVpnService` in test harness to match current `VpnService` interface.

### Post-fix runs
```bash
cd securewave/securewave_app
flutter test --no-pub test/protocol_selector_test.dart test/state_machine/auto_connect_listener_test.dart test/vpn_state_test.dart
flutter test
```
- Targeted tests: passed
- Full test suite: passed

## Deterministic Tunnel Probe Verification

### Command
```bash
cd securewave
./tools/runtime_probe/tunnel_probe.sh \
  --connect-cmd 'pkexec /usr/local/libexec/securewave-wg-quick up /home/sp/.config/securewave/sw-wg.conf' \
  --disconnect-cmd 'pkexec /usr/local/libexec/securewave-wg-quick down /home/sp/.config/securewave/sw-wg.conf'
```

### Latest output
- Probe run: `tools/runtime_probe/out/20260226_231936`
- Report: `tools/runtime_probe/out/20260226_231936/REPORT.md`

### Summary verdicts (from report)
- Tunnel up post-connect: yes
- Policy route/rule present (table 51820/fwmark): yes
- Route decision switched to `sw-wg`: yes
- Egress IP changed to VPN egress and reverted on disconnect: yes
- Post-disconnect tunnel interface removed: yes

## Notes
- Probe script was retained as the deterministic runtime harness.
- No broad native/backend rewrites were reintroduced in this rescue pass.
