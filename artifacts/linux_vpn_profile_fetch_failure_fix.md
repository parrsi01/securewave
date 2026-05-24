# Linux VPN Profile Fetch Failure Fix

Date: 2026-05-24

## Screenshot-Observed Symptom

The Linux Flutter app launched, restored a logged-in session, rendered the
Connect screen, and showed account/usage data. WireGuard and OpenVPN both failed
before tunnel startup with:

> Profile fetch failed. The server endpoint was not found. Please update the app or contact support.

The UI/runtime was responsive; the failure was in the VPN profile request path.

## Root Cause

The app persisted VPN runtime identifiers across account/session changes:

- `vpn_device_id`
- cached per-protocol profile config
- selected server ID

After logout/re-login or account changes, the app could send a stale
`device_id` or stale `server_id` to `POST /api/vpn/profile`. The live backend
correctly rejected those references with HTTP 404. The Flutter error classifier
then mapped the generic 404 into the visible "server endpoint was not found"
message.

This was not a basic Flutter startup issue and not a general live backend outage.
Clean live profile requests still succeeded for the canonical Hetzner server
`de-nue-1`.

## Exact Live Evidence

API base used for validation:

```text
https://api.securewaveapp.com/api
```

Live health:

```text
GET /health -> 200 {"status":"ok","service":"securewave-vpn"}
```

Live Linux protocols:

```text
GET /vpn/protocols?device_type=linux -> 200
wireguard enabled=true
openvpn enabled=true
ikev2 enabled=false reason=not_supported_on_platform
```

Live Linux server catalog:

```text
GET /vpn/servers?device_type=linux -> 200
total=1
recommended_server_id=de-nue-1
server_ids=["de-nue-1"]
```

Reproduction of stale-device failure:

```text
POST /vpn/profile as user A, protocol=wireguard -> 200 device_id=68 server_id=de-nue-1
POST /vpn/profile as user B, protocol=wireguard, device_id=68 -> 404
POST /vpn/profile as user B, protocol=wireguard, no device_id -> 200 device_id=69 server_id=de-nue-1
```

Reproduction of stale-server failure:

```text
POST /vpn/profile protocol=wireguard, server_id=old-provider-server -> 404
POST /vpn/profile protocol=wireguard, auto-select -> 200 server_id=de-nue-1
```

Normal profile path after the fix:

```text
python3 scripts/live_flutter_runtime_smoke.py --profile-repeats 3

wireguard: [200, 200, 200]
openvpn: [200, 200, 200]
ikev2: [400, 400, 400]
server_count: 1
server_ids: ["de-nue-1"]
usage: 0.0 / 5.0 GB
```

IKEv2 returning 400 is expected current release truth for Linux.

## Files Changed

- `securewave_app/lib/core/state/vpn_state.dart`
- `securewave_app/lib/core/services/secure_storage.dart`
- `securewave_app/lib/services/auth_service.dart`
- `securewave_app/lib/app.dart`
- `securewave_app/test/vpn_state_test.dart`
- `scripts/live_flutter_runtime_smoke.py`
- `artifacts/linux_vpn_profile_fetch_failure_fix.md`

## Fix Implemented

The app now treats VPN runtime IDs as session-scoped state:

- Login/register clears cached VPN runtime state before storing the new session.
- Sign out clears VPN runtime state and resets server selection to auto-select.
- Profile fetch retries once through the normal backend path when the backend
  returns 404 for a stale `device_id` or stale selected server.
- Stale 404 profile failures do not fall back to cached VPN configs.
- Successful retry stores the fresh backend-issued device ID and profile config.

The fix does not hardcode profiles, server locations, keys, credentials, or fake
connected states.

## Validation

Commands run:

```bash
flutter test test/vpn_state_test.dart
flutter test
flutter analyze
pytest -q tests/integration/test_vpn_profile.py tests/unit/test_vpn_server_inventory_filter.py
python3 -m py_compile scripts/live_flutter_runtime_smoke.py
python3 scripts/live_flutter_runtime_smoke.py --profile-repeats 3
git diff --check
```

Results:

- Targeted Flutter VPN state tests passed.
- Full Flutter test suite passed.
- Flutter analyzer passed with no issues.
- Targeted backend profile/server tests passed.
- Live control-plane smoke confirmed WireGuard and OpenVPN profile fetches return
  HTTP 200 through the normal `/api/vpn/profile` path.
- No local `securewave` WireGuard interface or SecureWave OpenVPN client process
  was left running.

## Protocol Verdict

- WireGuard: profile fetch is usable through the normal app/API path. Native
  tunnel startup still requires local privileges and `wg-quick`.
- OpenVPN: profile fetch is usable through the normal app/API path. Native
  tunnel startup remains limited to the covered Linux helper/runtime path and
  local privileges.
- IKEv2: non-public for Linux release. The live protocol endpoint reports it as
  unsupported for Linux and the app keeps it gated.

## Remaining Risks

- Native WireGuard/OpenVPN connect/disconnect was not re-run end to end in this
  prompt because this VM does not have passwordless sudo. `pkexec` is installed,
  but interactive privilege prompts are not suitable for automated validation.
- The public catalog still has one real canonical server: `de-nue-1`.
- The Flutter classifier still maps unrelated generic 404s to a profile-not-found
  category, but stale device/server references now recover before that message
  reaches the user for valid release-visible protocols.
