# Simulated Live Features Validation Report (2026-02-27)

## Scope
- Build/test a fully simulated live-features harness.
- Validate usage gauge data contract, free/premium account behavior, and location premium gating.
- Ensure no real Linux VPN/network runtime is used in simulated tests.

## Files Changed
- `main.py`
- `routes/user.py`
- `routes/vpn.py`
- `services/tunnel_runtime.py`
- `tools/admin/reset_usage_and_devices.py`
- `tools/sim_live_validate.sh`
- `tests/conftest.py`
- `tests/helpers/auth.py`
- `tests/fixtures/users.py`
- `tests/unit/test_reset_usage_and_devices.py`
- `tests/integration/test_simulated_live_usage_flow.py`
- `securewave_app/lib/core/config/app_config.dart`
- `securewave_app/lib/core/models/server_region.dart`
- `securewave_app/lib/core/services/vpn_service.dart`
- `securewave_app/lib/screens/locations/locations_screen.dart`
- `securewave_app/lib/screens/locations/widgets/server_tile.dart`
- `securewave_app/lib/services/api_client.dart`
- `securewave_app/test/sim_mode_vpn_service_test.dart`
- `securewave_app/test/locations_premium_gate_test.dart`

## Rerun Commands
- Backend simulated validation loop:
```bash
cd /home/sp/cyber-course/projects/securewave
./tools/sim_live_validate.sh
```

- Backend targeted suites:
```bash
cd /home/sp/cyber-course/projects/securewave
.venv/bin/pytest -q tests/unit/test_reset_usage_and_devices.py tests/integration/test_simulated_live_usage_flow.py
.venv/bin/pytest -q tests/integration/test_vpn_protocols_endpoint.py
.venv/bin/pytest -x -vv tests/integration/test_vpn_profile.py
.venv/bin/pytest -q tests/integration/test_vpn_alignment_requirements.py
.venv/bin/pytest -q tests/unit/test_region_health_watchdog.py
.venv/bin/pytest -q tests/unit/test_vpn_error_classification.py
```

- Flutter simulation-focused tests:
```bash
cd /home/sp/cyber-course/projects/securewave/securewave_app
flutter test --dart-define=SECUREWAVE_SIM_MODE=true \
  test/sim_mode_vpn_service_test.dart \
  test/locations_premium_gate_test.dart \
  test/server_region_premium_test.dart \
  test/settings_protocol_reason_message_test.dart
```

## Validation Matrix
| Scenario | Expected | Result |
|---|---|---|
| Reset usage/devices guarded by env + non-prod checks | Reset denied without guard; allowed with guard | Pass |
| Backup before reset (sqlite) | `backups/db_pre_sim_*.sqlite` created | Pass |
| Simulated tunnel connect | `/api/vpn/connect` returns success in simulated mode | Pass |
| Simulated traffic increments usage | `/api/account/usage.used_bytes` increases deterministically | Pass |
| Free user premium region connect attempt | Typed error `region_premium_required` | Pass |
| Premium user premium region connect attempt | Connect allowed | Pass |
| No real runtime calls in simulated connect path | Sim test passes with WireGuard runtime methods monkeypatched to fail | Pass |
| Flutter sim mode bypasses native channel | `ChannelVpnService` connects/disconnects in sim mode | Pass |
| Flutter premium location visual gating | Premium tile shows disabled reason when free | Pass |

## Notes
- `tools/sim_live_validate.sh` exports `SECUREWAVE_TUNNEL_MODE=simulated` and `DB_ECHO=false`.
- Reset command is intentionally destructive only in dev/test and requires `SECUREWAVE_ALLOW_DEV_RESETS=1`.
