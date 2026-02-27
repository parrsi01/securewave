# IKEv2 Full Restore Report (2026-02-27)

## Scope
Restore IKEv2 server helpers + backend integration on Hetzner with strict capability gating preserved and Linux automation compatibility.

## Files changed (repo)
- `scripts/ops/restore_openvpn_ikev2_hetzner.sh`
- `services/vpn_credential_service.py`
- `routes/vpn.py`
- `.env.example.backend`

## Server actions executed
1. Copied and executed restore script:
- `ssh root@138.199.204.139 'bash /root/restore_openvpn_ikev2_hetzner.sh'`

2. Installed helper scripts (verified executable):
- `/usr/local/bin/securewave-ikev2-issue-client`
- `/usr/local/bin/securewave-ikev2-upsert-user`
- `/usr/local/bin/securewave-ikev2-revoke-client`

3. Updated backend env and service:
- Set `SECUREWAVE_IKEV2_AUTH_MODE=eap-mschapv2`
- Set `SECUREWAVE_IKEV2_SERVICE_UNITS=strongswan-starter,strongswan,charon-systemd`
- Restarted `securewave.service`

## Validation evidence
### Service and listeners
- `systemctl status strongswan-starter --no-pager -l` => `active (running)`
- `ss -lntup | egrep ':(500|4500)\\b'` => UDP `500` and `4500` listening

### Helper script contract
- `securewave-ikev2-upsert-user ... --output json` => `{ "ok": true, "code": "ikev2_user_upserted", ... }`
- `securewave-ikev2-issue-client ... invalid token` => `{ "ok": false, "code": "ikev2_invalid_token", ... }`
- `securewave-ikev2-revoke-client ... --output json` => JSON response with typed code

### Backend/API
Executed on server localhost with bearer token:
- `GET /api/vpn/protocols?device_type=linux`
  - ikev2: `enabled=true`, `server_enabled=true`
- `POST /api/vpn/profile` with `{"protocol":"ikev2","device_type":"linux"...}`
  - response: `protocol=ikev2`, `profile.type=ikev2`, `profile.auth_method=eap-mschapv2`, no error

## Pass/Fail matrix
- IKEv2 helper scripts installed: PASS
- strongSwan service healthy/listening: PASS
- Backend protocols endpoint enables IKEv2 for linux: PASS
- IKEv2 profile provisioning returns Linux-compatible EAP-MSCHAPv2 profile: PASS
- Client-side live connect/disconnect from Flutter UI in this session: NOT EXECUTED (manual runtime verification pending)

## Notes
- Linux runner automation path is aligned to EAP-MSCHAPv2.
- Backend typed gating remains active; capability now depends on script material + service health.

## Known risks
- As with OpenVPN, server row health metadata can report `degraded` while the service is operational.
- If server-side IPsec conf is manually changed, `securewave-ikev2-upsert-user` must remain source-of-truth for EAP credentials.
