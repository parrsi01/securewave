# WireGuard Runtime Fix Report

Date: 2026-06-01

## Executive summary

WireGuard was failing before it reached a truthful connected state because the Flutter Linux runner used the wrong runtime identity for the tunnel. It wrote `securewave.conf`, which makes `wg-quick` create an interface named `securewave`, while the installed SecureWave helper and policy route setup expect `sw-wg`. The runner then verified routes and traffic counters against the same wrong interface name, so the runtime path was not aligned with the helper that is installed on the host.

The fix changes WireGuard only. The runner now writes `sw-wg.conf`, uses the installed `/usr/local/libexec/securewave-wg-quick` helper through `pkexec --disable-internal-agent` when not running as root, verifies the `sw-wg` interface and route before returning success, and reads traffic counters from `sw-wg`.

## What was broken

| Area | Failure | Result |
| --- | --- | --- |
| Config path | Runner wrote `~/.config/securewave/securewave.conf` | `wg-quick` would create `securewave`, not the helper's expected `sw-wg` |
| Helper invocation | Runner invoked `wg-quick` directly under `pkexec` | Installed helper and its policy-route path were bypassed |
| Interface detection | Runner checked `ip link show securewave` | Real helper-backed WireGuard path would not satisfy the check |
| Route evidence | Runner required `ip route get 1.1.1.1` to contain `dev securewave` | Correct helper-backed route via `sw-wg` would be rejected |
| Data usage | WireGuard counters were read from `/sys/class/net/securewave/statistics/*` | Correct tunnel usage on `sw-wg` would be reported as zero |

## Runtime path after fix

Expected WireGuard runtime path:

1. Flutter app fetches `/api/vpn/profile` for protocol `wireguard`.
2. Native runner writes config to `~/.config/securewave/sw-wg.conf`.
3. Non-root runner starts `pkexec --disable-internal-agent /usr/local/libexec/securewave-wg-quick up ~/.config/securewave/sw-wg.conf`.
4. Helper delegates to `wg-quick up`, creating interface `sw-wg`.
5. Runner only reports success after both checks pass:
   - `ip link show sw-wg`
   - `ip route get 1.1.1.1` contains `dev sw-wg`
6. Data usage reads:
   - `/sys/class/net/sw-wg/statistics/rx_bytes`
   - `/sys/class/net/sw-wg/statistics/tx_bytes`

## Files changed

- `securewave_app/linux/runner/my_application.cc`
- `scripts/linux_vpn_runtime_verifier.py`
- `scripts/linux_app_vpn_tunnel_proof.py`
- `tests/unit/test_linux_vpn_runner_contract.py`
- `tests/unit/test_linux_vpn_runtime_verifier.py`
- `tests/unit/test_linux_app_vpn_tunnel_proof.py`
- `artifacts/wireguard_runtime_fix_report.md`

## Validation results

| Check | Result |
| --- | --- |
| `.venv/bin/python -m py_compile scripts/linux_vpn_runtime_verifier.py scripts/linux_app_vpn_tunnel_proof.py` | Pass |
| `.venv/bin/python -m pytest -q tests/unit/test_linux_vpn_runner_contract.py tests/unit/test_linux_vpn_runtime_verifier.py tests/unit/test_linux_app_vpn_tunnel_proof.py` | Pass, 20 passed |
| `.venv/bin/python -m pytest -q tests/integration/test_vpn_profile.py -k "profile_returns_config_and_metadata or protocol_catalog_reports_all_enabled_protocols or servers_endpoint_returns_supported_protocols or stale_device_id_falls_back_to_device_name_lookup or linux_profile_includes_wg_quick_kill_switch_hooks or mobile_profile_does_not_include_wg_quick_hooks"` | Pass, 5 passed, 6 deselected |
| `.venv/bin/python -m pytest -q tests/integration/test_vpn_profile.py -k "protocols_endpoint_exposes_linux_protocols_when_metadata_exists"` | Pass, 1 passed, 10 deselected |
| `flutter analyze` | Pass, no issues found |
| `flutter test test/vpn_state_test.dart test/mock_vpn_service_test.dart test/live_payload_parsing_test.dart` | Pass, all tests passed |
| `flutter build linux --debug` | Pass, built `build/linux/arm64/debug/bundle/securewave_app` |
| `git diff --check` | Pass |
| `which wg` | `/usr/bin/wg` |
| `which wg-quick` | `/usr/bin/wg-quick` |
| `timeout 8s sudo wg show` | Fail: sudo requires a password/TTY |
| `ip addr` | No `sw-wg` or `securewave` tunnel interface present |
| `ip route` | Default route remains via `enp0s1`; no WireGuard route present |
| `.venv/bin/python scripts/linux_vpn_runtime_verifier.py --json` | Expected host-gate fail: `privilege:pkexec_authorization` timed out; runner/helper/residue checks passed |
| `pkexec --disable-internal-agent /usr/local/libexec/securewave-wg-quick probe wireguard` | Pass |
| `timeout 12s securewave_app/build/linux/arm64/debug/bundle/securewave_app` | App launched to Dart VM service, then stopped by timeout |

Full `flutter test` was also run. It failed in pre-existing `test/fresh_ui_state_test.dart` finder taps with `Bad state: No element`; this is outside the WireGuard runtime path changed here.

## Remaining WireGuard risks

- Full live tunnel proof still needs an auth-capable desktop PolicyKit session or root execution. This non-interactive shell cannot run `sudo wg show` and `pkexec /usr/bin/true` times out waiting for authorization.
- No real WireGuard tunnel was started in this pass. The fix compiles and the helper probe passes, but live connect still requires valid backend credentials/server reachability and an interactive privilege prompt.
- The runner still relies on `ip route get 1.1.1.1` containing `dev sw-wg` as route evidence. That is intentional for “do not mark connected unless runtime evidence supports it,” but unusual policy-route layouts may need a future more detailed WireGuard evidence collector.
