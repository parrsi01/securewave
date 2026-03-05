# Provisioning Fix Report (2026-02-28)

## Root Cause Of The 409
The `409 openvpn_server_misconfigured` and `409 ikev2_server_misconfigured` responses were being raised before the backend ever consulted the selected VPN server.

The blocking source was local backend gating in `routes/vpn.py`:
- `_server_supported_protocols()` required `_protocol_material_ready(protocol)`.
- `_select_server_for_protocol()` also required `_protocol_material_ready(protocol)`.
- `_protocol_material_ready()` checked for provisioning scripts on the API host filesystem (`/usr/local/bin/securewave-*`).

That is incorrect for the real architecture because provisioning scripts live on the selected VPS and are executed over SSH. As a result, healthy remote OpenVPN and IKEv2 daemons were incorrectly rejected when the API host did not have those scripts locally.

## What Changed
- Added explicit provisioning mode handling:
  - `SECUREWAVE_PROVISIONING_MODE=local_stub|ssh_real`
  - default is `local_stub` in tests, `ssh_real` otherwise
- Added remote, typed prerequisite validation in `services/vpn_credential_service.py`:
  - `validate_openvpn_provisioning_prereqs()`
  - `validate_ikev2_provisioning_prereqs()`
- Changed credential provisioning to:
  - skip local runtime prereq gating during server selection
  - validate prerequisites against the selected server instead
  - return actionable `missing` and `hint` details on 409
- Hardened remote script execution:
  - bounded with `SECUREWAVE_PROVISIONING_COMMAND_TIMEOUT`
  - stderr/stdout preserved in error text instead of collapsing to one side
- Made provisioning more idempotent:
  - OpenVPN certificate issuance reuses the existing revision/common-name when `rotate_if_exists=false`
  - IKEv2 certificate issuance does the same
  - repeated provisioning calls now return stable credential metadata instead of forcing a new revision by default
- Added IKEv2 payload fields for explicit full-tunnel signaling:
  - `proposals`
  - `traffic_selectors` (defaults to `0.0.0.0/0`)
- Added targeted integration tests for OpenVPN and IKEv2 provisioning.

## Files Changed
- `routes/vpn.py`
- `services/vpn_credential_service.py`
- `tests/integration/test_vpn_provision_openvpn.py`
- `tests/integration/test_vpn_provision_ikev2.py`

## Tests Run
- `.venv/bin/python -m py_compile routes/vpn.py services/vpn_credential_service.py tests/integration/test_vpn_provision_openvpn.py tests/integration/test_vpn_provision_ikev2.py`
- `.venv/bin/pytest -q tests/integration/test_vpn_provision_openvpn.py tests/integration/test_vpn_provision_ikev2.py`
- `.venv/bin/pytest -q tests/integration/test_vpn_credentials.py tests/integration/test_vpn_profile.py tests/integration/test_vpn_protocols_endpoint.py`

## Results
- New provisioning tests: `2 passed`
- Regression suite: `29 passed`

## Exact Rerun Commands
### Targeted provisioning tests
```bash
.venv/bin/pytest -q tests/integration/test_vpn_provision_openvpn.py tests/integration/test_vpn_provision_ikev2.py
```

### Adjacent regression coverage
```bash
.venv/bin/pytest -q tests/integration/test_vpn_credentials.py tests/integration/test_vpn_profile.py tests/integration/test_vpn_protocols_endpoint.py
```

### Syntax check
```bash
.venv/bin/python -m py_compile \
  routes/vpn.py \
  services/vpn_credential_service.py \
  tests/integration/test_vpn_provision_openvpn.py \
  tests/integration/test_vpn_provision_ikev2.py
```

## Manual Curl Verification
### OpenVPN (real SSH path)
```bash
TOKEN=$(curl -sS -X POST http://127.0.0.1:8000/api/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"premium_test@securewave.dev","password":"SecureWave!Test123"}' | python3 -c 'import json,sys; print(json.load(sys.stdin)["access_token"])')

SECUREWAVE_PROVISIONING_MODE=ssh_real \
curl -sS -X POST http://127.0.0.1:8000/api/vpn/credentials/provision \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"protocol":"openvpn","device_name":"Manual Verify","device_type":"linux","rotate_if_exists":false}'
```

### IKEv2 (Linux EAP-MSCHAPv2 payload)
```bash
TOKEN=$(curl -sS -X POST http://127.0.0.1:8000/api/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"premium_test@securewave.dev","password":"SecureWave!Test123"}' | python3 -c 'import json,sys; print(json.load(sys.stdin)["access_token"])')

SECUREWAVE_PROVISIONING_MODE=ssh_real \
curl -sS -X POST http://127.0.0.1:8000/api/vpn/credentials/provision \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"protocol":"ikev2","device_name":"Manual Verify","device_type":"linux","rotate_if_exists":false}'
```

### Expected shape checks
- OpenVPN: `profile.type=openvpn`, `profile.ovpn_config` contains a `remote` line, `credential.credential_type=client_certificate`
- IKEv2: `profile.type=ikev2`, `profile.username`, `profile.password`, `profile.traffic_selectors=["0.0.0.0/0"]`
