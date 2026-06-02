# Full Linux Protocol And Usage Regression Report

Date: 2026-06-02

## Executive summary

The data usage display now separates real runtime tunnel usage from backend account/monthly usage.

Runtime session usage is derived only from native tunnel byte counters returned by the Linux runner. The runner marks counters unavailable when `/sys/class/net/<vpn-interface>/statistics/rx_bytes` and `tx_bytes` cannot be read, so missing interfaces no longer become fake zero-byte sessions. Mock VPN mode no longer emits synthetic traffic counters.

Monthly/account usage remains tied to backend `UserPlan` data and is hidden in demo/mock API mode. The UI shows a clear unavailable state when session counters are not present.

Full live WireGuard/OpenVPN/IKEv2 connect-disconnect regression could not complete because the app-driven proof is blocked by non-interactive PolicyKit authorization. Tooling and helper probes pass, and no tunnel residue is present, but no real tunnel was started in this shell.

## Files changed

- `securewave_app/linux/runner/my_application.cc`
- `securewave_app/lib/core/services/vpn_service.dart`
- `securewave_app/lib/core/state/vpn_state.dart`
- `securewave_app/lib/core/utils/formatters.dart`
- `securewave_app/lib/app.dart`
- `securewave_app/test/formatters_test.dart`
- `securewave_app/test/usage_ui_test.dart`
- `securewave_app/test/vpn_state_test.dart`
- `securewave_app/test/fresh_ui_state_test.dart`
- `tests/unit/test_linux_vpn_runner_contract.py`
- `artifacts/full_linux_protocol_and_usage_regression_report.md`

## Data usage implementation

| Area | Result |
| --- | --- |
| Native counter source | Linux runner reads `/sys/class/net/<interface>/statistics/rx_bytes` and `tx_bytes` |
| Counter availability | Native response now includes `counters_available` and `unavailable_reason` |
| WireGuard interface | `sw-wg` |
| OpenVPN interface | `tun0`, then first `tun*` |
| IKEv2 interface | first `ipsec*` or `xfrm*`; otherwise `ip -s xfrm state` lifetime bytes when readable and classifiable |
| Session baseline | First available sample after connect becomes the baseline |
| Session deltas | Subsequent positive rx/tx deltas are added to session totals |
| Counter reset | Negative deltas are treated as counter reset and are not added |
| Disconnect behavior | Final poll runs before disconnect; session totals remain visible after rate polling stops |
| Backend report | Only positive deltas from available counters are posted to `/vpn/usage/report` |
| Mock mode | Mock VPN stats return unavailable instead of synthetic byte growth |
| Monthly/account usage | Shown only when not in mock API mode and backed by `UserPlan` provider data |

## Protocol results table

| Protocol | Dependency/helper check | Connect/disconnect | Route/DNS state | IP change | Data bar traffic increase | Result |
| --- | --- | --- | --- | --- | --- | --- |
| WireGuard | `wg`, `wg-quick`, helper probe pass | Not attempted by proof script; baseline failed before protocol run | No `sw-wg`; no SecureWave route residue | Baseline public IP `92.105.134.148`; no tunnel IP change tested | No `sw-wg` counter files, so unavailable fallback is correct | Blocked by `pkexec` authorization |
| OpenVPN | `openvpn`, helper probe pass | Not attempted by proof script; baseline failed before protocol run | No `tun0`; no OpenVPN process or tun routes | Baseline public IP `92.105.134.148`; no tunnel IP change tested | No `tun0` counter files, so unavailable fallback is correct | Blocked by `pkexec` authorization |
| IKEv2 | `nmcli`, `ipsec`, helper probe pass | Not attempted by proof script; baseline failed before protocol run | No active `SecureWave-IKEv2:vpn`; DNS remains on `enp0s1` | Baseline public IP `92.105.134.148`; no tunnel IP change tested | No `ipsec0`/`xfrm0` counter files, so unavailable fallback is correct | Blocked by `pkexec` authorization |

## Data usage accuracy result

Verdict: implementation is accurate for runtime interfaces that expose Linux byte counters, but not billing-grade.

What is proven:

- The UI no longer shows static `Bridge rates: Not exposed`.
- Runtime session bytes are accumulated from measured native rx/tx counter deltas.
- Missing tunnel counters produce an unavailable state and do not report backend usage.
- Mock VPN mode does not generate fake usage counters.
- Backend monthly usage remains a separate account meter and is not shown as real monthly usage in mock API mode.

What is not proven:

- No live tunnel traffic increase was observed because no protocol could be started in this non-interactive shell.
- IKEv2 usage may remain unavailable on NetworkManager/strongSwan policy-based tunnels unless an `ipsec*`/`xfrm*` interface exists or XFRM state byte counters are readable and match local tunnel direction.
- These counters are session-display counters, not billing-grade accounting. Billing-grade accuracy would require server-side authoritative counters.

## Validation results

| Check | Result |
| --- | --- |
| `git diff --check` | Pass |
| `flutter analyze` | Pass, no issues found |
| `flutter test` | Pass, all tests passed |
| `flutter test test/formatters_test.dart test/vpn_state_test.dart test/usage_ui_test.dart test/mock_vpn_service_test.dart test/live_payload_parsing_test.dart` | Pass, all tests passed |
| `flutter build linux --debug` | Pass |
| `.venv/bin/python -m py_compile scripts/linux_vpn_runtime_verifier.py scripts/linux_app_vpn_tunnel_proof.py` | Pass |
| Targeted pytest for runner/verifier/proof/profile usage | Pass, 6 passed, 26 deselected |
| `which wg` / `which wg-quick` | `/usr/bin/wg`, `/usr/bin/wg-quick` |
| `which openvpn` | `/usr/sbin/openvpn` |
| `which nmcli` / `which ipsec` | `/usr/bin/nmcli`, `/usr/sbin/ipsec` |
| `pkexec --disable-internal-agent /usr/local/libexec/securewave-wg-quick probe wireguard` | Pass |
| `pkexec --disable-internal-agent /usr/local/libexec/securewave-wg-quick probe openvpn` | Pass |
| `pkexec --disable-internal-agent /usr/local/libexec/securewave-wg-quick probe ikev2` | Pass |
| `ip -brief addr` / `ip route` | No `sw-wg`, `tun0`, `ipsec0`, or `xfrm0`; default route via `enp0s1` |
| `resolvectl status` | DNS remains on `enp0s1` |
| `nmcli -t -f NAME,TYPE,DEVICE connection show --active` | No active SecureWave VPN profile |
| `/sys/class/net/{sw-wg,tun0,ipsec0,xfrm0}/statistics/*` checks | Missing rx/tx files for all inactive tunnel interfaces |
| Public IP baseline | `92.105.134.148` |
| `.venv/bin/python scripts/linux_vpn_runtime_verifier.py --json` | Fails only at `privilege:pkexec_authorization` timeout; runner/residue checks pass |
| `.venv/bin/python scripts/linux_app_vpn_tunnel_proof.py --json --hold-seconds 8 --evidence-timeout 30` | Fails before protocol attempts because baseline verifier fails on `pkexec` authorization |
| `timeout 12s securewave_app/build/linux/arm64/debug/bundle/securewave_app` | App launched to Dart VM service, then stopped by timeout |

## Follow-up 1-4 execution

Date: 2026-06-02

| Requested item | Result |
| --- | --- |
| 1. Run app-driven proof from auth-capable desktop PolicyKit/root-like session | Blocked on this shell. `sudo -n true` returns `sudo: a password is required`; `timeout 8s pkexec /usr/bin/true` exits `124`. |
| 2. Re-run all three protocol connect/disconnect proofs | Blocked before protocol attempts. `scripts/linux_app_vpn_tunnel_proof.py --json --hold-seconds 8 --evidence-timeout 30` fails at baseline `privilege:pkexec_authorization`. |
| 3. Verify route/DNS/IP change and counter growth | Not proven because no tunnel could be started. No `sw-wg`, `tun0`, `ipsec0`, or `xfrm0` interface was present during the follow-up. |
| 4. Add IKEv2-specific counter source if NetworkManager strongSwan does not expose a netdev | Implemented a truthful fallback in the Linux runner: IKEv2 traffic stats now try `ip -s xfrm state`, classify lifetime bytes as rx/tx using local `ip -o addr show` addresses, and report unavailable if XFRM counters are not readable or not classifiable. |

Additional follow-up evidence:

- `pkexec --disable-internal-agent /usr/local/libexec/securewave-wg-quick probe wireguard` exits `0`.
- `pkexec --disable-internal-agent /usr/local/libexec/securewave-wg-quick probe openvpn` exits `0`.
- `pkexec --disable-internal-agent /usr/local/libexec/securewave-wg-quick probe ikev2` exits `0`.
- `ip -s xfrm state` and `ip -s xfrm policy` as the current user fail with `RTNETLINK answers: Operation not permitted`, so the fallback will truthfully report unavailable on this host unless the app/helper is run with sufficient network privileges.

## Blocking issues remaining

| Blocker | Impact |
| --- | --- |
| `pkexec /usr/bin/true` times out in this non-interactive shell | App-driven proof cannot start WireGuard, OpenVPN, or IKEv2 |
| No active tunnel interfaces | Cannot prove IP change, route change, DNS change, or traffic counter increase |
| IKEv2 XFRM counters require sufficient privileges | Session usage can truthfully show unavailable for IKEv2 until an `ipsec*`/`xfrm*` interface exists or XFRM state counters are readable |
| Backend/server reachability not exercised by live proof | Profile issuance and tunnel data plane were not proven in this pass |

## Recommended remediation order

1. Run the app-driven proof from an auth-capable desktop PolicyKit session or as a controlled root test where the SecureWave helper can start tunnels.
2. Re-run `scripts/linux_app_vpn_tunnel_proof.py --json` for all three protocols and capture route/DNS/IP/counter evidence during the holding window.
3. If IKEv2 connects but counters remain unavailable, verify whether `ip -s xfrm state` is readable in the app/helper context; otherwise use a real XFRM interface, NetworkManager statistics, or server-side session counters.
4. Add server-side authoritative usage counters before making billing-grade usage claims.
5. Keep UI wording as session-observed usage until server-side billing counters are proven.
