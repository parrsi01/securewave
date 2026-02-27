# OpenVPN Full Restore Report (2026-02-27)

## Scope
Restore OpenVPN server helpers + backend integration on Hetzner with strict capability gating preserved and WireGuard untouched.

## Files changed (repo)
- `scripts/ops/restore_openvpn_ikev2_hetzner.sh`
- `services/vpn_credential_service.py`
- `routes/vpn.py`
- `.env.example.backend`

## Server actions executed
1. Copied and executed restore script:
- `ssh root@138.199.204.139 'bash /root/restore_openvpn_ikev2_hetzner.sh'`

2. Installed helper scripts (verified executable):
- `/usr/local/bin/securewave-openvpn-issue-client`
- `/usr/local/bin/securewave-openvpn-upsert-user`
- `/usr/local/bin/securewave-openvpn-revoke-client`

3. Updated backend env and service:
- Set `SECUREWAVE_OPENVPN_AUTH_MODE=mtls`
- Set `SECUREWAVE_OPENVPN_SERVICE_UNITS=openvpn-server@server,openvpn-server@securewave,openvpn@server`
- Set `SECUREWAVE_ENFORCE_RUNTIME_CHECKS=true`
- Configured `SECUREWAVE_PROVISIONING_TOKEN_SECRET` and `/etc/securewave/secrets/provisioning_token_secret`
- Restarted `securewave.service`

## Validation evidence
### Service and listener
- `systemctl status openvpn-server@server --no-pager -l` => `active (running)`
- `ss -lntup | egrep ':(1194)\\b'` => UDP `1194` listening

### Helper script contract
- `securewave-openvpn-upsert-user ... --output json` => `{ "ok": true, "code": "openvpn_user_upserted", ... }`
- `securewave-openvpn-issue-client ... invalid token` => `{ "ok": false, "code": "openvpn_invalid_token", ... }`
- `securewave-openvpn-revoke-client ... --output json` => JSON response with typed code

### Backend/API
Executed on server localhost with bearer token:
- `GET /api/vpn/protocols?device_type=linux`
  - openvpn: `enabled=true`, `server_enabled=true`
- `POST /api/vpn/profile` with `{"protocol":"openvpn","device_type":"linux"...}`
  - response: `protocol=openvpn`, `profile.type=openvpn`, `profile.auth_method=mtls`, no error

## Pass/Fail matrix
- OpenVPN helper scripts installed: PASS
- OpenVPN service healthy/listening: PASS
- Backend protocols endpoint enables OpenVPN for linux: PASS
- OpenVPN profile provisioning returns MTLS profile: PASS
- Client-side live connect/disconnect from Flutter UI in this session: NOT EXECUTED (manual runtime verification pending)

## Notes
- OpenVPN is now provisioned through typed helper JSON + artifact retrieval path to avoid printing profile secrets directly from helper stdout.
- WireGuard flow was not modified.

## Known risks
- Existing server model health can still appear `degraded` (`openvpn_healthcheck_fail`) depending on per-server health metadata, even while protocol is enabled and profile issuance works.
- Final data-plane verification still needs one manual connect/disconnect run in the Linux app.
