# IKEv2 Runtime Fix Report

Date: 2026-06-02

## Executive summary

IKEv2 had partial Linux runtime code before this pass, but it was not a safe or reliable app runtime path. The runner tried to generate a `swanctl` config and launch it through a broad privileged shell, then verified state with `swanctl --list-sas`. On this host the app user cannot query `swanctl` state, and that path was not aligned with the installed SecureWave helper.

The installed helper already exposes a narrower NetworkManager strongSwan path:

- `ikev2-add-eap <server> <username> <password> [remote-id]`
- `ikev2-up`
- `ikev2-down`
- `ikev2-delete`

The runner now uses that helper path and only reports success after real NetworkManager runtime evidence exists.

## Whether IKEv2 existed before

| Area | Before | Result |
| --- | --- | --- |
| Runtime implementation | Partial `swanctl`/`ipsec` implementation in the Linux runner | Real code existed, but it was not aligned with the installed helper/runtime path |
| Privileged execution | `pkexec /bin/sh -c` shell script wrote system files and ran `swanctl` | Too broad and difficult to verify safely from app state |
| State detection | `swanctl --list-sas` grep for `securewave` | Fails for normal app user on this host because VICI/stroke state needs elevated access |
| Route/DNS proof | No NetworkManager route or DNS profile evidence | App could not prove the active desktop VPN profile affected runtime routing/DNS |
| Profile parsing | Config was written but not converted into the helper's EAP profile inputs | IKEv2 could not use the helper's real `ikev2-add-eap` command |

## Runtime path after fix

Expected IKEv2 runtime path:

1. Flutter app fetches `/api/vpn/profile` for protocol `ikev2`.
2. Native runner writes the backend profile to `~/.config/securewave/securewave-ikev2.conf`.
3. Native runner parses:
   - `remote_addrs` as the server
   - `eap_id` as the EAP username
   - `secret` as the EAP password
   - remote `id` as the optional remote identity
4. Non-root runner configures the NetworkManager profile through:
   - `pkexec --disable-internal-agent /usr/local/libexec/securewave-wg-quick ikev2-add-eap <server> <username> <password> <remote-id>`
5. Native runner starts:
   - `pkexec --disable-internal-agent /usr/local/libexec/securewave-wg-quick ikev2-up`
6. Runner reports connected only after both checks pass:
   - `nmcli -t -f NAME,TYPE connection show --active` includes `SecureWave-IKEv2:vpn`
   - `nmcli -t -f IP4.DNS,IP4.ROUTE,IP6.DNS,IP6.ROUTE connection show SecureWave-IKEv2` contains route or DNS evidence
7. Native runner stops and removes the profile through:
   - `ikev2-down`
   - `ikev2-delete`
8. Runner reports disconnected only after `SecureWave-IKEv2:vpn` is no longer active.

## What changed

| Area | Change |
| --- | --- |
| Runtime backend | Replaced the app-side direct `swanctl` shell path with the existing SecureWave NetworkManager helper actions |
| Dependency gate | IKEv2 availability now requires `nmcli`, `ipsec`, and the installed SecureWave helper |
| Profile/config acquisition | Runner parses the backend IKEv2 profile into server, EAP username, EAP secret, and remote identity |
| Secret handling | No hardcoded secrets were added; backend-issued EAP secret is passed to the existing helper contract and stored by NetworkManager as a VPN secret |
| Connect state | Connected state requires active NetworkManager VPN plus route or DNS evidence |
| Disconnect state | Disconnect removes the NetworkManager profile and waits for the active VPN evidence to disappear |
| Protocol isolation | Added tests proving IKEv2 selection sends IKEv2 config, not WireGuard or OpenVPN fallback config |
| Runtime proof scripts | Updated verifier/proof scripts to check NetworkManager IKEv2 evidence and stale active `SecureWave-IKEv2` residue |

## Files changed

- `securewave_app/linux/runner/my_application.cc`
- `scripts/linux_vpn_runtime_verifier.py`
- `scripts/linux_app_vpn_tunnel_proof.py`
- `securewave_app/test/vpn_state_test.dart`
- `tests/integration/test_vpn_profile.py`
- `tests/unit/test_linux_app_vpn_tunnel_proof.py`
- `tests/unit/test_linux_vpn_runner_contract.py`
- `tests/unit/test_linux_vpn_runtime_verifier.py`
- `artifacts/ikev2_runtime_fix_report.md`

## Validation results

| Check | Result |
| --- | --- |
| `.venv/bin/python -m py_compile scripts/linux_vpn_runtime_verifier.py scripts/linux_app_vpn_tunnel_proof.py` | Pass |
| `.venv/bin/python -m pytest -q tests/unit/test_linux_vpn_runner_contract.py tests/unit/test_linux_vpn_runtime_verifier.py tests/unit/test_linux_app_vpn_tunnel_proof.py tests/integration/test_vpn_profile.py -k "ikev2_profile_returns_protocol_config_when_server_supports_it or runner_contract_covers_all_protocol_runtime_evidence or residue_checks_fail_on_securewave_leftovers or ikev2_start or ikev2_evidence"` | Pass, 5 passed, 27 deselected |
| `flutter analyze` | Pass, no issues found |
| `flutter test test/vpn_state_test.dart test/mock_vpn_service_test.dart test/live_payload_parsing_test.dart` | Pass, all tests passed |
| `flutter build linux --debug` | Pass, built `build/linux/arm64/debug/bundle/securewave_app` |
| `git diff --check` | Pass |
| `which nmcli` / `nmcli --version` | `/usr/bin/nmcli`, NetworkManager 1.46.0 |
| `which ipsec` / `ipsec --version` | `/usr/sbin/ipsec`, strongSwan U5.9.13 |
| `pkexec --disable-internal-agent /usr/local/libexec/securewave-wg-quick probe ikev2` | Pass |
| `nmcli -t -f NAME,TYPE,DEVICE connection show --active` | No active `SecureWave-IKEv2` profile before test |
| `nmcli -t -f IP4.DNS,IP4.ROUTE,IP6.DNS,IP6.ROUTE connection show SecureWave-IKEv2` | Expected baseline: no such connection profile |
| `ip addr` / `ip route` / `resolvectl status` | No IKEv2 VPN interface/profile evidence; default route and DNS remain on `enp0s1` |
| `.venv/bin/python scripts/linux_vpn_runtime_verifier.py --json` | Expected host-gate fail: `privilege:pkexec_authorization` timed out; IKEv2 helper contract and residue checks passed |

Full `flutter test` was also run. It still fails in pre-existing `test/fresh_ui_state_test.dart` finder taps with `Bad state: No element`; this is unrelated to the IKEv2 runtime path changed here.

## Remaining IKEv2 risks

- Full live IKEv2 tunnel proof was not completed in this pass. The helper probe works, but this non-interactive shell still cannot complete the generic `pkexec /usr/bin/true` authorization check.
- The current helper contract receives the EAP password as an argv value. No secret is hardcoded, and NetworkManager stores it as a hidden VPN secret, but argv exposure during helper invocation remains a security limitation to improve in the helper.
- The NetworkManager helper path does not currently import or pin the backend CA PEM. If a server requires a private CA not already trusted by the OS/NetworkManager strongSwan stack, live connect will fail truthfully instead of marking connected.
- IKEv2 data usage counters may remain zero on policy-based NetworkManager/strongSwan connections because there may be no dedicated `ipsec*` or `xfrm*` netdev. This pass fixed runtime connection truth, not a per-protocol IKEv2 usage counter implementation.
