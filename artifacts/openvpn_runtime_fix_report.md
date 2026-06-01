# OpenVPN Runtime Fix Report

Date: 2026-06-01

## Executive summary

OpenVPN already had a Linux runtime implementation, but it used a broad privileged shell path:

`pkexec /bin/sh -c "openvpn --config ... --daemon ..."`

That bypassed the installed scoped SecureWave helper even though the helper already supports real OpenVPN actions:

- `openvpn-start <config-path> <pid-path> [auth-path]`
- `openvpn-stop <pid>`

The fix keeps OpenVPN scoped to the existing Linux app architecture. The runner now starts and stops OpenVPN through `/usr/local/libexec/securewave-wg-quick`, then verifies real runtime evidence before reporting connected or disconnected.

## What was broken

| Area | Failure | Result |
| --- | --- | --- |
| Privileged execution | OpenVPN used `pkexec /bin/sh -c` instead of the scoped helper | Broader command surface and inconsistent with the installed SecureWave runtime helper |
| Start state | The old shell script waited for evidence, but the app-side helper path was not used | OpenVPN was not on the same real helper path as previously certified diagnostics |
| Disconnect state | Stop used shell `kill` logic instead of helper `openvpn-stop` | Disconnect was not tied to the helper contract and could drift from package/runtime behavior |
| Profile truth | OpenVPN profile tests only checked a loose non-empty shape | Placeholder or incomplete profile regressions were easier to miss |
| Protocol state | There was no focused test proving OpenVPN selection sends OpenVPN config to the native service | A future WireGuard fallback regression could pass silently |

## Runtime path after fix

Expected OpenVPN runtime path:

1. Flutter app fetches `/api/vpn/profile` for protocol `openvpn`.
2. Native runner writes config to `~/.config/securewave/securewave.ovpn`.
3. Native runner starts:
   - `pkexec --disable-internal-agent /usr/local/libexec/securewave-wg-quick openvpn-start ~/.config/securewave/securewave.ovpn ~/.config/securewave/securewave-openvpn.pid`
4. Runner reports connected only after both are true:
   - OpenVPN PID file exists and the PID is running.
   - Either `ip route get 1.1.1.1` contains `dev tun` or a `tun*` interface exists.
5. Native runner stops:
   - `pkexec --disable-internal-agent /usr/local/libexec/securewave-wg-quick openvpn-stop <pid>`
6. Runner reports disconnected only after:
   - PID is no longer running.
   - No `ip route get 1.1.1.1` tunnel route through `tun*` remains.

## Files changed

- `securewave_app/linux/runner/my_application.cc`
- `scripts/linux_vpn_runtime_verifier.py`
- `securewave_app/test/vpn_state_test.dart`
- `tests/integration/test_vpn_profile.py`
- `tests/unit/test_linux_vpn_runner_contract.py`
- `tests/unit/test_linux_vpn_runtime_verifier.py`
- `artifacts/openvpn_runtime_fix_report.md`

## Validation results

| Check | Result |
| --- | --- |
| `.venv/bin/python -m py_compile scripts/linux_vpn_runtime_verifier.py scripts/linux_app_vpn_tunnel_proof.py` | Pass |
| `.venv/bin/python -m pytest -q tests/unit/test_linux_vpn_runner_contract.py tests/unit/test_linux_vpn_runtime_verifier.py tests/unit/test_linux_app_vpn_tunnel_proof.py` | Pass, 21 passed |
| `.venv/bin/python -m pytest -q tests/unit/test_linux_vpn_runner_contract.py tests/unit/test_linux_vpn_runtime_verifier.py tests/unit/test_linux_app_vpn_tunnel_proof.py tests/integration/test_vpn_profile.py -k "openvpn_profile_returns_protocol_config_when_server_supports_it or openvpn_profile_requires_server_support or runner_contract_covers_all_protocol_runtime_evidence or openvpn_start"` | Pass, 5 passed, 27 deselected |
| `flutter analyze` | Pass, no issues found |
| `flutter test test/vpn_state_test.dart test/mock_vpn_service_test.dart test/live_payload_parsing_test.dart` | Pass, all tests passed |
| `flutter build linux --debug` | Pass, built `build/linux/arm64/debug/bundle/securewave_app` |
| `git diff --check` | Pass |
| `which openvpn` | `/usr/sbin/openvpn` |
| `openvpn --version` | OpenVPN 2.6.19 present |
| `pkexec --disable-internal-agent /usr/local/libexec/securewave-wg-quick probe openvpn` | Pass |
| `ip addr` / `ip route` / process scan | No active `tun0`, no OpenVPN process, route remains via `enp0s1` |
| `.venv/bin/python scripts/linux_vpn_runtime_verifier.py --json` | Expected host-gate fail: `privilege:pkexec_authorization` timed out; OpenVPN helper contract and residue checks passed |
| `timeout 12s securewave_app/build/linux/arm64/debug/bundle/securewave_app` | App launched to Dart VM service, then stopped by timeout |

Full `flutter test` was also run. It still fails in pre-existing `test/fresh_ui_state_test.dart` finder taps with `Bad state: No element`; this is unrelated to the OpenVPN runtime path changed here.

## Remaining OpenVPN risks

- Full live OpenVPN tunnel proof was not completed in this pass. The host has OpenVPN and the helper probe works, but this non-interactive shell still cannot complete the generic `pkexec /usr/bin/true` authorization check.
- Existing local `.ovpn` files under `~/.config/securewave` were not used for a live start because their basic non-secret metadata was not safely readable through the simple scan, so starting them would not be reliable evidence.
- The runner now proves PID plus `tun*` interface/route evidence before reporting connected, but the actual data-plane still depends on a reachable OpenVPN server and a fresh backend-issued profile.
- Disconnect verification checks PID and default route evidence. It intentionally does not fail just because an unrelated `tun*` interface exists, to avoid breaking users with another VPN active.
