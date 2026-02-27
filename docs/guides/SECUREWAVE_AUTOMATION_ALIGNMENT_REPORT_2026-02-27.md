# SecureWave Automation Alignment Report (2026-02-27)

## Scope Executed

- Live traffic/routing telemetry wiring (Linux runner -> Flutter state -> UI).
- Login quick-account autofill support for test accounts.
- Backend compatibility + metadata checks for:
  - 3 protocol capability endpoints
  - region/server payload compatibility
  - premium location markers
- Automated full-stack validation harness with markdown evidence output.

## Implemented Changes

1. Linux runtime traffic stats
- Added `getTrafficStats` channel method in `securewave_app/linux/runner/my_application.cc`.
- Exposes connected flag, active interface, rx/tx bytes, protocol, timestamp.

2. Real upload/download/session gauge movement
- Added `VpnTrafficStats` and `fetchTrafficStats()` in `securewave_app/lib/core/services/vpn_service.dart`.
- Replaced zeroed "simulation" path with live polling in `securewave_app/lib/core/state/vpn_state.dart`.
- UI now shows:
  - Download Mbps
  - Upload Mbps
  - Session MB
  in `securewave_app/lib/screens/home/widgets/metrics_display.dart`.
- Account usage gauge now includes live-session estimate in `securewave_app/lib/screens/account/account_screen.dart`.

3. Login quick autofill (recent accounts)
- Added recent-email persistence in `securewave_app/lib/core/services/secure_storage.dart`.
- Auth success now stores recent login email in `securewave_app/lib/services/auth_service.dart`.
- Login UI displays recent account chips in `securewave_app/lib/features/auth/login_page.dart`.

4. Protocol/location backend compatibility and metadata
- Added `/api/vpn/protocol-capabilities` alias to `/api/vpn/protocols`.
- Added `/api/vpn/regions` alias with `regions` payload key.
- Added server premium metadata in API responses:
  - `tier_restriction`
  - `premium_only`
- Updated model/UI parsing and display:
  - `securewave_app/lib/core/models/server_region.dart`
  - `securewave_app/lib/screens/locations/widgets/server_tile.dart`

5. User-friendly elevation path for reset/connect
- Linux runner now prefers scoped helper path when available:
  - `/usr/local/libexec/securewave-wg-quick`
- Packaging script now installs helper + polkit rule for no repeated password prompts on WG reset/connect:
  - `securewave_app/scripts/build_deb.sh`
- Updated Linux setup guidance:
  - `securewave_app/LINUX_VPN_SETUP.md`

6. Automated alignment runner
- Added executable harness:
  - `tools/runtime_probe/full_stack_alignment.sh`
- Captures baseline/post network state, backend checks, flutter validation slice, runtime probe outcome, and writes markdown report.

## Validation Executed

### Flutter tests (targeted)

Command:

```bash
cd /home/sp/cyber-course/projects/securewave/securewave_app
flutter test test/recent_login_accounts_test.dart test/server_region_premium_test.dart test/protocol_selector_test.dart test/protocol_capability_matrix_test.dart test/state_machine/auto_connect_listener_test.dart test/state_machine/multiple_concurrent_connect_requests_test.dart test/vpn_state_test.dart
```

Result: `PASS`

### Backend integration tests (targeted)

Command:

```bash
cd /home/sp/cyber-course/projects/securewave
.venv/bin/pytest -q tests/integration/test_vpn_alignment_requirements.py tests/integration/test_vpn_protocols_endpoint.py
```

Result: `PASS (4 passed)`

### Linux runner build

Command:

```bash
cd /home/sp/cyber-course/projects/securewave/securewave_app
flutter build linux
```

Result: `PASS`

## Automated Full-Stack Runs

Primary run artifact:

- `tools/runtime_probe/out/fullstack_20260227_011144/FULL_STACK_ALIGNMENT_REPORT.md`

Observed blockers in this environment:

1. Backend not reachable at `http://127.0.0.1:8000/api/health`.
2. Runtime probe elevation blocked in this sandbox (`pkexec must be setuid root`).
3. Flutter validation invoked inside harness is blocked by sandbox write restrictions on Flutter cache.

These are environment/runtime blockers, not code compilation failures.

## Connectivity/Wi-Fi Debug Evidence

The harness captures and preserves:

- Baseline network:
  - `baseline_nmcli_devices.txt`
  - `baseline_ip_route.txt`
  - `baseline_ip_rule.txt`
- Post-run network:
  - `post_nmcli_devices.txt`
  - `post_ip_route.txt`
  - `post_ip_rule.txt`

Per-run evidence directory:

- `tools/runtime_probe/out/fullstack_20260227_011144/`

## Rerun Commands (Host Machine)

1. Start backend and run alignment:

```bash
cd /home/sp/cyber-course/projects/securewave
./tools/runtime_probe/full_stack_alignment.sh \
  --base-url "http://127.0.0.1:8000" \
  --free-email "FREE_ACCOUNT_EMAIL" \
  --free-password "FREE_ACCOUNT_PASSWORD" \
  --premium-email "PREMIUM_ACCOUNT_EMAIL" \
  --premium-password "PREMIUM_ACCOUNT_PASSWORD"
```

2. Force runtime probe with helper:

```bash
cd /home/sp/cyber-course/projects/securewave
./tools/runtime_probe/full_stack_alignment.sh \
  --connect-cmd "pkexec /usr/local/libexec/securewave-wg-quick up /home/sp/.config/securewave/securewave-wireguard.conf" \
  --disconnect-cmd "pkexec /usr/local/libexec/securewave-wg-quick down /home/sp/.config/securewave/securewave-wireguard.conf"
```

3. App launch for manual verification:

```bash
cd /home/sp/cyber-course/projects/securewave/securewave_app
flutter run -d linux -v
```

## Current Status vs Requested Target

- `Implemented`: live gauge movement, account autofill chips, backend capability aliases, premium markers, deterministic automation harness.
- `Blocked by environment`: full runtime pass (backend offline in this run, pkexec/sandbox limitations).
- `Exception notes required`: yes, captured in run report and evidence files.
