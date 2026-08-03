# Linux VPN Connectivity Scrub

Date: 2026-05-25

## Screenshot-Observed Symptom

- Flutter Linux app launches and authenticates.
- WireGuard/OpenVPN selection reaches the connect flow.
- Connect fails before any tunnel starts with: `Profile fetch failed. The server endpoint was not found. Please update the app or contact support.`
- Session remains disconnected and traffic stays at zero.

## Exact Root Cause

The screenshot error was caused by profile lookup state, not by Flutter startup.
The app could send stale locally persisted VPN references to `POST /api/vpn/profile`:

- stale `vpn_device_id` from a previous user/session; or
- stale selected server IDs left over from earlier provider/server inventory.

The backend correctly rejected those references with HTTP 404. The app then mapped
that 404 to the vague "server endpoint was not found" text.

Live reproduction confirmed the failure mode:

```text
POST /vpn/profile as user A, protocol=wireguard -> 200 device_id=68 server_id=de-nue-1
POST /vpn/profile as user B, protocol=wireguard, device_id=68 -> 404
POST /vpn/profile as user B, protocol=wireguard, no device_id -> 200 device_id=69 server_id=de-nue-1
POST /vpn/profile protocol=wireguard, server_id=old-provider-server -> 404
POST /vpn/profile protocol=wireguard, auto-select -> 200 server_id=de-nue-1
```

A second live check also exposed a separate precise failure class: a new device
name on a Free account with one active device returns `403 device_limit_reached`.
That must be shown as a device-limit error, not as auth failure or endpoint loss.

## Files Changed

- `routes/vpn.py`
- `tests/integration/test_vpn_profile.py`
- `securewave_app/lib/core/models/server_region.dart`
- `securewave_app/lib/core/state/vpn_state.dart`
- `securewave_app/lib/services/api_client.dart`
- `securewave_app/test/live_payload_parsing_test.dart`
- `securewave_app/test/vpn_state_test.dart`
- `artifacts/linux_vpn_connectivity_scrub.md`

## Dependency Status

Local Linux VM:

- `wg`: present at `/usr/bin/wg`
- `wg-quick`: present at `/usr/bin/wg-quick`
- `openvpn`: present at `/usr/sbin/openvpn`
- `resolvectl` / `systemd-resolved`: present
- `ip` / `iproute2`: present
- `iptables` / `ip6tables`: present
- `pkexec` / polkit: present, but no active desktop auth agent was usable from this validation session
- strongSwan: `ipsec` present; `swanctl` not on PATH
- Flutter Linux desktop: present, Linux arm64 desktop device detected

Privilege status:

```text
sudo -n true -> sudo: a password is required
pkexec /usr/bin/id -> timed out after 8 seconds
```

That blocks automated local tunnel start/stop proof in this VM. It does not block
profile/API validation.

Production Hetzner host:

- `securewave-api`, `nginx`, `postgresql`, `redis-server`, `openvpn-server@server`, and `strongswan-starter` are active.
- WireGuard interface `wg0` is present and listening on UDP `51820`.
- OpenVPN is listening on UDP `1194`.
- strongSwan/charon is listening on UDP `500` and `4500`, but IKEv2 remains non-public for Linux v1.

## Backend/API Diagnosis

Live API base used by the app and validation:

```text
https://api.securewaveapp.com/api
```

Live protocol truth:

```text
GET /vpn/protocols?device_type=linux -> 200
wireguard enabled=true
openvpn enabled=true
ikev2 enabled=false reason=not_supported_on_platform
```

Live server catalog:

```text
GET /vpn/servers?device_type=linux -> 200
total=1
recommended_server_id=de-nue-1
server_id=de-nue-1 status=active health=healthy region_health=up
```

Live profile validation with the current QA Linux device:

```text
POST /vpn/profile protocol=wireguard device_type=linux -> 200
server_id=de-nue-1 device_id=67 peer_registered=true
registration_status="Peer added successfully"
endpoint=138.199.204.139:51820
address=10.8.0.67/32
allowed_ips=0.0.0.0/0, ::/0
DNS=94.140.14.14,94.140.15.15
kill-switch hooks present=true

POST /vpn/profile protocol=openvpn device_type=linux -> 200
server_id=de-nue-1 device_id=67
remote=138.199.204.139 1194 udp
CA/cert/key blocks present=true
cipher=AES-256-GCM auth=SHA256
```

Local backend hardening added in this scrub:

- `GET /api/vpn/protocols?device_type=linux` exists in repo and reports protocol availability with reasons.
- `GET /api/vpn/servers?device_type=linux` returns `supported_protocols` derived from usable endpoint/certificate metadata.
- Linux IKEv2 is not advertised as release-ready.
- Stale `device_id` is recoverable server-side by falling back to device-name lookup/creation.
- Auto-select candidates are filtered by usable protocol metadata, not only broad boolean flags.

## Frontend Diagnosis

The Flutter client already sends `device_type` and the selected protocol to
`/vpn/profile`. The issue was stale persisted state and overly broad error
mapping.

Frontend hardening in place:

- Login/register clears session-scoped VPN runtime state.
- Sign out clears selected server, cached profile configs, expiry, and stored VPN device ID.
- Profile fetch retries once through the normal `/vpn/profile` path when stale device/server references return 404.
- Stale 404s do not fall back to cached tunnel configs.
- Device limit errors are surfaced precisely as `Device limit reached...`.
- Profile request logging now records protocol, device type, server/auto-select, device-id presence, and API base URL without logging tokens or secrets.
- Server parsing accepts either `supported_protocols` or legacy protocol booleans.

## Runtime Diagnosis

WireGuard:

- Live profile fetch is healthy and returns a complete `wg-quick` style Linux config.
- Hetzner WireGuard listener is active.
- Local app helper writes config to the SecureWave config path and uses `wg-quick up` through `pkexec` when not root.
- Automated `wg-quick up/down` validation was blocked by local privilege elevation, so no local interface/route/public-IP movement is claimed from this session.

OpenVPN:

- Live profile fetch is healthy and returns a complete nested OpenVPN profile.
- Hetzner OpenVPN listener is active on UDP `1194`.
- Local app helper writes config, starts `openvpn --daemon securewave-openvpn`, records a pid file, and cleans that pid file on disconnect.
- Automated OpenVPN tunnel validation was blocked by the same local privilege path.

IKEv2:

- Live protocol endpoint reports Linux IKEv2 unsupported.
- App/runtime keeps IKEv2 blocked for Linux release use.
- No IKEv2 success is claimed.

## Fixes Implemented

- Backend stale-device recovery in `POST /api/vpn/profile`.
- Backend protocol metadata checks for WireGuard/OpenVPN auto-select.
- Backend protocol availability endpoint in repo.
- Backend server list `supported_protocols` for Linux release truth.
- Flutter server protocol parsing fallback.
- Flutter profile-request diagnostic logging.
- Flutter device-limit error precision.
- Tests for stale profile references, protocol availability, supported protocols, and precise device-limit errors.

## Validation Evidence

Commands run and passed:

```bash
pytest -q tests/integration/test_vpn_profile.py tests/unit/test_vpn_server_inventory_filter.py
flutter test test/live_payload_parsing_test.dart test/vpn_state_test.dart
flutter analyze
python3 scripts/live_flutter_runtime_smoke.py --email securewave.qa.20260524233626.d8105a@gmail.com --password 'REDACTED' --profile-repeats 3
git diff --check
```

Results:

- Backend targeted tests: `11 passed`.
- Full Flutter test suite: `24 passed`.
- Flutter analyzer: `No issues found`.
- Live smoke with existing QA account:
  - WireGuard profile statuses: `[200, 200, 200]`
  - OpenVPN profile statuses: `[200, 200, 200]`
  - IKEv2 profile statuses: `[400, 400, 400]` as expected for Linux release truth
  - Server catalog: `de-nue-1`
- No local SecureWave WireGuard/OpenVPN process or `securewave` interface residue was present after validation.

## Final Protocol Verdicts

- WireGuard: Profile fetch and backend peer registration work through the normal app/API path. Native tunnel start is blocked from automated proof in this VM by missing non-interactive privilege elevation, not by profile/server metadata.
- OpenVPN: Profile fetch works through the normal app/API path and production listener is active. Native tunnel start is still unproven in this VM due to the same privilege blocker.
- IKEv2: Blocked/non-public for Linux v1. No success claimed.

## Remaining Risks

- To prove end-to-end local tunnel startup, run the app in a Linux desktop session with a working PolicyKit authentication agent or a properly installed SecureWave privilege helper.
- Free accounts have a one-device limit. Reusing the same device name works; a new device name returns `device_limit_reached`, which is now surfaced precisely.
- The public catalog still has one real canonical server: `de-nue-1`.
- If backend code is deployed independently of the current Flutter client, ensure production `/vpn/protocols` response shape remains compatible with any existing consumers.

## Manual Native Validation Command Plan

Use this only in a Linux VM where admin elevation can complete:

```bash
cd securewave_app
flutter build linux --debug
./build/linux/arm64/debug/bundle/securewave_app
```

Then in the app:

1. Sign in with the QA account.
2. Select WireGuard and Auto-select server.
3. Press Connect and approve the PolicyKit prompt.
4. Verify:

```bash
ip link show securewave
wg show securewave
ip route
curl -4 https://ifconfig.me
```

5. Disconnect and verify cleanup:

```bash
ip link show securewave || true
pgrep -af 'securewave-openvpn|securewave.ovpn|wg-quick.*securewave|openvpn.*securewave' || true
```

For OpenVPN, repeat with the OpenVPN protocol and verify a `tun` interface,
OpenVPN pid, route movement, browser traffic, then disconnect cleanup.
