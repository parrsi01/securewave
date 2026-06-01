# Runtime Protocol Failure Audit

Date: 2026-06-01
Mode: Diagnose only
Branch inspected: `flutter`
HEAD inspected: `44fe8ae8e81d795e361164dddd05fa95323e3b61`
Fetched `origin/master`: `b2273b86e2463926041efffb8ca0ca0c571b547f`

## 1. Executive summary

The current Flutter branch has real Linux runner code paths for WireGuard, OpenVPN, and IKEv2, and the local backend can issue non-empty profile payloads for all three protocols. The protocols are not proven connectable at runtime because the host-side privileged execution path is not working noninteractively: `pkexec` exists, but the repo runtime verifier reports `pkexec authorization timed out; start a PolicyKit authentication agent or run SecureWave with required privileges`.

No tunnel is currently active:

- No `securewave` WireGuard interface.
- No `tun0` OpenVPN interface.
- No SecureWave/tun split routes.
- No SecureWave OpenVPN process.
- No SecureWave IKEv2 SA.

The live debug app startup succeeded far enough to build and attach to Linux, but no connect attempt was made because validation was explicitly read-only. Startup logs only showed EGL/MESA/cursor warnings, not VPN runtime errors.

Important branch note: `origin/master` was fetched for comparison but not merged because this prompt required diagnose-only/read-only commands. Current `flutter` is ahead of `origin/master` by the recent protocol/runtime commits, including `44fe8ae8 Fix VPN protocol usage runtime state`.

## 2. Per-protocol failure table

| Protocol | UI availability | Backend profile/config | Linux runtime implementation | Current runtime failure reasons | Failure categories |
|---|---|---|---|---|---|
| WireGuard | Shown as enabled because `ChannelVpnService.canConnectProtocol()` returns `true` for every protocol. UI does not consume `/api/vpn/protocols`. | Local API returned HTTP 200 with non-empty `wireguard_config`; local demo response contains `DEMO CONFIG` and mock peer registration. | Implemented through method channel `securewave/vpn`, writes `~/.config/securewave/securewave.conf`, then runs `pkexec wg-quick up <config>` and requires interface `securewave` plus route evidence. | `pkexec` authorization times out on this host. The local seeded profile points to demo/private endpoint `10.77.0.10:51820`, so it is not evidence of a reachable real data-plane server. No current `securewave` interface exists. | permission/sudo/helper issue; backend/data-plane mock config in local demo; route evidence absent because no tunnel is active |
| OpenVPN | Shown as enabled for the same UI reason: `canConnectProtocol()` always returns true. | Local API returned HTTP 200 with non-empty `openvpn_config`; remote line is `remote 10.77.0.10 1194`. | Implemented through method channel, writes `~/.config/securewave/securewave.ovpn`, then runs `pkexec /bin/sh -c "openvpn --config ... --daemon ..."` and requires a `tun*` route or `tun0` link within the startup loop. | `pkexec` authorization times out. The local seeded OpenVPN endpoint and CA are demo values and do not prove a reachable OpenVPN server. No `tun0`, no OpenVPN process, and no tunnel routes currently exist. | permission/sudo/helper issue; backend/data-plane demo endpoint; route/tun evidence absent |
| IKEv2 | Shown as enabled for the same UI reason. | Local API returned HTTP 200 with non-empty `ikev2_config`; `remote_addrs = 10.77.0.10`. | Implemented through method channel, writes `~/.config/securewave/securewave-ikev2.conf`, then uses `pkexec /bin/sh -c` to install config under `/etc/swanctl`, run `swanctl --load-all`, `swanctl --initiate --child securewave`, and verify `swanctl --list-sas`. | `pkexec` authorization times out. Running `swanctl --list-sas` as the app user fails with permission denied on `unix:///var/run/charon.vici`. Local profile targets demo/private `10.77.0.10`; no real responder proof. StrongSwan service is active, but no SecureWave SA exists. | permission/sudo/helper issue; strongSwan/VICI permission issue; backend/data-plane demo endpoint; route/DNS/counter path incomplete for IKEv2 |

## 3. Exact files involved

Flutter UI and state:

- `securewave_app/lib/app.dart`
  - Connect button calls `vpnStateProvider.notifier.connect()` from the Connect screen.
  - Server selection reads `serversProvider` and stores `selectedServerId`.
  - Protocol picker enables rows from `vpnService.canConnectProtocol(...)`.
  - Data panel renders `_UsageSummary(plan: value)` and hard-codes `Bridge rates` to `Not exposed`.
- `securewave_app/lib/core/state/app_state.dart`
  - `vpnServiceProvider` creates `ChannelVpnService(fallback: MockVpnService(), allowFallback: config.useMockApi)`.
  - `serversProvider` calls `api.fetchServers()`.
- `securewave_app/lib/core/state/vpn_state.dart`
  - Fetches profile on native connect.
  - Sends selected protocol to `service.connect(protocol: state.protocol, config: config)`.
  - Polls `service.getTrafficStats(protocol)` every 5 seconds after connected.
  - Reports deltas to `/api/vpn/usage/report`.
- `securewave_app/lib/core/services/vpn_service.dart`
  - `ChannelVpnService.canConnectProtocol()` currently returns `true` for all protocols.
  - `_refreshNativeAvailability()` calls native `isAvailable`, which is generic, not per-protocol.
  - `getTrafficStats()` calls native `getTrafficStats`.
- `securewave_app/lib/services/api_client.dart`
  - `fetchServers()` calls `GET /vpn/servers?device_type=linux`.
  - `fetchVpnProfile()` calls `POST /vpn/profile`.
  - `notifyVpnConnected()` calls `POST /vpn/connect`.
  - `notifyVpnDisconnected()` calls `POST /vpn/disconnect`.
  - `reportVpnUsage()` calls `POST /vpn/usage/report`.

Linux runtime:

- `securewave_app/linux/runner/my_application.cc`
  - Tools checks: `wg-quick`, `openvpn`, `swanctl`, `ipsec`, `pkexec`.
  - WireGuard path: `wg-quick up/down`, interface and route checks.
  - OpenVPN path: `openvpn --daemon`, PID/log files, tun route/interface checks.
  - IKEv2 path: writes `/etc/swanctl` config, `swanctl --load-all`, `swanctl --initiate`, `swanctl --list-sas`.
  - Traffic counters read `/sys/class/net/<interface>/statistics/{rx_bytes,tx_bytes}`.
- `scripts/linux_vpn_runtime_verifier.py`
  - Read-only verifier confirms tools, runner contract, privilege path, and residue state.

Backend:

- `routes/vpn.py`
  - `_platform_supported_protocols()` returns all three protocols for Linux.
  - `_server_supported_protocols()` gates protocols on server metadata.
  - `GET /api/vpn/servers` returns `supported_protocols`.
  - `GET /api/vpn/protocols` returns availability rows.
  - `POST /api/vpn/profile` issues per-protocol profile config.
  - `POST /api/vpn/connect` is a backend session/event endpoint, not the actual local tunnel starter.
  - `POST /api/vpn/usage/report` records client-observed byte deltas.

## 4. Runtime dependencies required

Installed on this host:

- `wg`: `/usr/bin/wg`
- `wg-quick`: `/usr/bin/wg-quick`
- `openvpn`: `/usr/sbin/openvpn`
- `swanctl`: `/usr/sbin/swanctl`
- `ipsec`: `/usr/sbin/ipsec`
- `ip`: `/usr/sbin/ip`
- `resolvectl`: `/usr/bin/resolvectl`
- `pkexec`: `/usr/bin/pkexec`
- `sudo`: `/usr/bin/sudo`
- `nmcli`: `/usr/bin/nmcli`
- `strongswan-starter`: active
- `NetworkManager`: active

Not working for the app user:

- `sudo -n true` fails: `sudo: a password is required`.
- `pkexec /usr/bin/true` times out in the repo runtime verifier.
- `swanctl --list-sas` as user `sp` fails with VICI permission denied.

Dependency implications:

- WireGuard requires working privilege elevation for `wg-quick up/down`.
- OpenVPN requires working privilege elevation, tun device support, and a reachable OpenVPN server/profile.
- IKEv2 requires working privilege elevation, strongSwan VICI access via elevated command path, valid `/etc/swanctl` writes, and a reachable IKEv2 responder.

## 5. Whether each protocol has a real implementation

| Protocol | Real implementation present? | Current quality |
|---|---:|---|
| WireGuard | Yes | Most complete. It writes a config, runs `wg-quick`, and verifies interface plus route evidence. Runtime blocked by privilege path and by demo/local endpoint when using the local seeded API. |
| OpenVPN | Yes, but narrower than WireGuard | It starts `openvpn --daemon` and verifies `tun*` route/interface evidence. It does not use the installed `/usr/local/libexec/securewave-wg-quick` helper path directly, and it depends on `pkexec /bin/sh -c`. Runtime blocked by privilege path and demo/local endpoint. |
| IKEv2 | Partial real implementation | It uses strongSwan `swanctl` directly and checks for an SA, but DNS/routing/counter handling is less complete. Runtime blocked by privilege path, VICI permission when not elevated, and demo/local endpoint. |

## 6. Data usage implementation diagnosis

Backend metering path is real:

- `routes/vpn.py::report_usage()` records app-observed `rx_bytes` and `tx_bytes` deltas against a `WireGuardPeer` and active `VPNConnection`.
- The Flutter app posts usage deltas through `ApiClient.reportVpnUsage()`.

Client counter source is mixed:

- In native mode, `ChannelVpnService.getTrafficStats()` calls native `getTrafficStats`.
- Linux native code reads `/sys/class/net/<interface>/statistics/rx_bytes` and `tx_bytes`.
- WireGuard maps to interface `securewave`.
- OpenVPN maps to `tun0` or the first `tun*` interface.
- IKEv2 maps to the first `ipsec*` or `xfrm*` interface, falling back to `ipsec0`.

Data usage weaknesses:

- The visible UI does not show real bridge rates; `securewave_app/lib/app.dart` displays `Bridge rates: Not exposed`.
- The visible Data panel uses `UserPlan` from the backend, not direct live tunnel counters.
- IKEv2 counter mapping may return zero on normal policy-based strongSwan setups that do not create an `ipsec*` or `xfrm*` netdev.
- In mock API mode, usage is not real: `MockVpnService` increments synthetic counters and `ApiClient.reportVpnUsage()` returns `null`.
- If native availability is false, `getTrafficStats()` returns zero and no usage is reported.

Current host state:

- No active tunnel interface exists, so current live counters cannot prove usage metering.
- Existing state files under `~/.config/securewave` include configs from previous runs, but no active interface/route/process/SA is present.

## 7. Recommended fix order

1. Fix the privileged runtime path first.
   - Make app-started WireGuard/OpenVPN/IKEv2 commands work without a hanging `pkexec` prompt.
   - Prefer a dedicated installed helper/polkit policy over `pkexec /bin/sh -c`.
   - Verify `pkexec` succeeds from a desktop session with an authentication agent, or run through a controlled helper with explicit allowed operations.

2. Add per-protocol runtime availability to the Flutter service/UI.
   - `canConnectProtocol()` must not return `true` unconditionally.
   - Native `isAvailable` should report per-protocol dependency and privilege readiness.
   - UI should consume backend `/api/vpn/protocols` plus native runtime readiness before enabling rows.

3. Replace local/demo endpoints with reachable real data-plane endpoints for runtime validation.
   - Current local seeded profiles target `10.77.0.10`, which is useful for shape tests only.
   - WireGuard needs real peer registration on the selected server.
   - OpenVPN needs a real listener, CA, auth mode if required, and tun route.
   - IKEv2 needs a real strongSwan responder matching `remote_id`, CA, EAP identity/secret, proposals, and traffic selectors.

4. Harden OpenVPN and IKEv2 helper execution.
   - Avoid broad `pkexec /bin/sh -c`.
   - Use an audited helper command set for start/stop/status/stats.
   - Capture protocol-specific logs back into diagnostics.

5. Fix IKEv2 routing, DNS, and usage counters.
   - Decide whether to use policy-based IPsec counters, XFRM interfaces, or NetworkManager IKEv2.
   - Do not rely on `ipsec0` unless the runner creates it.
   - Apply DNS intentionally; the current IKEv2 config only comments `# dns = ...`.

6. Expose real live rates in the UI.
   - Use `VpnState.dataRateDown` and `dataRateUp` in the Connect screen instead of `Bridge rates: Not exposed`.
   - Keep backend account usage as cumulative metering, but show tunnel counters/rates separately.

7. Run real protocol E2E validation after fixes.
   - WireGuard: interface `securewave`, route `dev securewave`, external IP change, rx/tx counters increase, clean down.
   - OpenVPN: `tun*` interface, route through tun, process exists during connection, counters increase, clean stop/routes removed.
   - IKEv2: `swanctl --list-sas` shows `securewave`, route/DNS behavior proven, counters source proven, clean termination.
