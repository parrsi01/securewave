# Contract-10 staging VPN flow certification

## Result

**Branch:** `codex/certify-contract10-staging-vpn-flow`

**Base revision:** `b2c69ade` (`origin/master` at branch creation)

**Date:** 2026-07-12 (UTC)

**Status:** **blocked before staging user-flow actions.** The installed
contract-10 local runtime is healthy, but no verified staging target,
authorized staging account/device, or usable WireGuard/OpenVPN server evidence
was available. No application was launched, no account was registered or used,
and no API, VPN endpoint, cloud resource, production system, or profile was
contacted.

The duplicate request to establish staging runtime is covered by the same
preflight: the existing branch `codex/establish-staging-vpn-runtime` records
that no staging endpoint, target-scoped credentials, target-specific rollback
plan, or deletion inventory was available. This branch does not create a
second resource-establishment branch or bypass those gates.

## Contract-10 local prerequisite evidence

| Item | Status | Redacted evidence |
| --- | --- | --- |
| Installed application package | verified | Installed SecureWave package version is `4.0.0+1`. |
| Helper service | verified | `securewave-helper.service` is active and enabled. |
| Helper socket | verified | Socket mode is `0660`, owned by `root:securewave`. |
| Installed contract | verified | Installed helper contract is `10`. |
| Matching app/verifier source | verified | A matching Linux-branch bundle and contract-10 verifier are present. The dirty contract-9/pkexec checkout was not launched, built, or changed. |
| Contract-10 runtime verifier | passed | Disconnected, read-only verifier completed with `ok=true` and zero failures. |
| Disconnected cleanup | passed | Verifier found no SecureWave WireGuard interface, OpenVPN process/tun interface, tunnel routes, VPN DNS residue, IKEv2 SA, or unqualified pref-220 routing-loop rule. |

The verifier's successful helper probes only prove local helper capability. They
do not prove a staging server, valid profile, peer allocation, handshake, or
VPN data plane.

## Staging prerequisites

| Required item | Status | Reason |
| --- | --- | --- |
| Staging target demonstrably separate from production | **blocked** | No staging API URL, host, or approved target scope is configured. |
| Authorized staging account and test device | **blocked** | A local certification-account file exists, but no staging-specific credential alias/file or scope confirmation exists; its contents were not read. |
| WireGuard runtime evidence | **blocked** | No authorized staging server or redacted server audit/runtime evidence was supplied. |
| OpenVPN runtime evidence | **blocked** | No authorized staging server or redacted server audit/runtime evidence was supplied. |
| Rollback and temporary-resource deletion | **blocked** | No target inventory, approved deletion path, previous revision/snapshot, or rollback owner is available. |
| IKEv2 authorization and proof | unavailable by design | Linux keeps IKEv2 not release-ready; no IKEv2 action was attempted. |

## End-to-end flow results

| Required flow or proof | Result |
| --- | --- |
| Register/use staging account and sign in | not run: no authorized staging account or target |
| Register device and fetch a real API profile | not run: no authorized staging API/profile path |
| Compare UI/API protocol state to server evidence | not run: no authorized staging API/server evidence |
| WireGuard connect, handshake, interface, policy route, DNS, HTTPS, endpoint bypass, exit IP, counters, disconnect, cleanup | not run: no usable staging WireGuard runtime/profile |
| OpenVPN equivalent proof | not run: no usable staging OpenVPN runtime/profile |
| IKEv2 visible unavailable/not connected | automated coverage only; no live API/UI target to inspect |
| Failure cases (profile/server/helper/malformed profile/timeout/disconnect/stale route) | live cases not run; helper and stale-residue conditions covered by verifier and automated tests only |
| Usage accounting start/increment/finalize/logout-login persistence | not run against staging; automated app/backend coverage only |
| Final pref-220 state | verified locally clean by the disconnected contract-10 verifier |

No connection claim is made from process/interface state. No live-protocol
claim is made from local helper availability or automated tests.

## Tests and safe commands

No command below contacted an external API or started a VPN tunnel. Secret
values, profiles, private keys, accounts, endpoints, and host details were not
printed or stored.

```text
dpkg-query -W -f='${Version}\n' securewave-vpn
systemctl is-active securewave-helper.service
systemctl is-enabled securewave-helper.service
stat -c 'helper_socket=%a %U:%G' /run/securewave/helper.sock
cat /usr/local/libexec/securewave-wg-quick.contract

python /tmp/securewave-final-linux-release-readiness/scripts/linux_vpn_runtime_verifier.py --json

/home/sp/cyber-course/projects/securewave/.venv/bin/python -m pytest \
  tests/integration/test_vpn_profile.py \
  tests/integration/test_vpn_flow.py \
  tests/integration/test_device_acl.py \
  tests/unit/test_vpn_server_inventory_filter.py \
  tests/unit/test_vpn_service.py \
  tests/unit/test_linux_vpn_runtime_verifier.py \
  tests/unit/test_linux_vpn_runner_contract.py -q

cd /tmp/securewave-final-linux-release-readiness/securewave_app
flutter analyze
flutter test
```

| Validation | Result |
| --- | --- |
| Contract-10 verifier | passed; zero failures |
| Python integration/unit/helper/verifier tests | **75 passed** in 7.31 seconds |
| Flutter analysis, matching Linux branch | passed; no issues |
| Flutter tests, matching Linux branch | **26 passed** |

The Python test run emitted the existing `pytest-asyncio` deprecation warning
about an unset default event-loop scope. It did not fail the suite.

## Unblock criteria

Do not retry the live flow until all of the following are supplied through an
approved staging-only handoff:

1. A named staging API and VPN-server target, with evidence that it is not
   production.
2. A scoped staging test account/device and safe credential delivery method.
3. WireGuard and/or OpenVPN server runtime evidence collected through the
   approved redacted auditor, including listener, firewall, forwarding/NAT,
   routing, DNS, and backend management/profile readiness.
4. A temporary-resource inventory, bounded test limits, deletion procedure,
   rollback revision/snapshot, and named rollback owner.
5. Explicit approval for any external HTTPS/exit-IP checks and tunnel traffic.

Until then, WireGuard and OpenVPN must remain unavailable, IKEv2 must remain
unavailable, and this work must not be presented as staging or release
readiness.
