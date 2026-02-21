# SecureWave Multiprotocol Phase 2 Server Report

Date: 2026-02-21  
Branch: `release/multiprotocol-live-only`

## Mission Outcome
Implemented real server-provisioning and backend credential lifecycle integration for OpenVPN and IKEv2/IPsec (Hetzner-targeted, live-only).

## Deliverables Created
- `scripts/provision_openvpn.sh` (idempotent)
- `scripts/provision_ikev2.sh` (idempotent)
- `scripts/rotate_openvpn_ca.sh`
- `scripts/rotate_ikev2_certs.sh`
- `docs/openvpn_setup.md`
- `docs/ikev2_setup.md`
- `artifacts/multiprotocol_phase2_server_report.md`
- `scripts/ci_multiprotocol_safety_check.sh`

Redacted profile artifacts:
- `artifacts/sample_openvpn_profile_redacted.ovpn`
- `artifacts/sample_ikev2_profile_redacted.txt`

## Backend Integration Implemented
### Credential lifecycle metadata
`VPNCredential` now tracks lifecycle metadata (serial/fingerprint/expiry/revision/revocation metadata/token hash) and includes migration:
- `alembic/versions/0011_add_vpn_credential_lifecycle_metadata.py`

### Provisioning/revocation/rotation service
`services/vpn_credential_service.py` now supports:
- OpenVPN mTLS credential issuance (server script driven)
- IKEv2 EAP-TLS credential issuance (server script driven)
- Provisioning-token minting (HMAC, short TTL)
- Credential revoke + rotate APIs
- Test-safe deterministic payload mode (only when `TESTING=true`)

### API endpoints added
In `routes/vpn.py`:
- `POST /api/vpn/credentials/provision`
- `GET /api/vpn/credentials`
- `POST /api/vpn/credentials/{credential_id}/revoke`
- `POST /api/vpn/credentials/{credential_id}/rotate`

`/api/vpn/profile` now issues cert-based payloads by default for:
- OpenVPN (`auth_method=mtls`)
- IKEv2 (`auth_method=eap-tls`)

Legacy username/password fallback remains available via env:
- `SECUREWAVE_OPENVPN_AUTH_MODE=userpass`
- `SECUREWAVE_IKEV2_AUTH_MODE=eap-mschapv2`

## Security / Operational Controls
- Secrets constrained to `/etc/securewave/secrets` (root-only).
- No committed cert/key material.
- Provisioning token validation helper installed on server (`securewave-validate-provisioning-token`).
- UFW/NAT setup included in provisioning scripts.
- Hetzner firewall minimum-open-port guidance documented.
- Rotation scripts include backup + break-glass recovery guidance.

## Test and Validation Results
- Backend tests: `337 passed, 3 skipped` (`./.venv/bin/pytest`)
- OpenAPI generated: `docs/openapi/securewave-openapi.json`
- CI safety check: `ci_multiprotocol_safety_check:ok`
- Nginx config check (local environment): `nginx` not installed (`nginx: command not found`)
- UFW check (local environment): requires root (`ERROR: You need to be root`)

## Required Environment Variables
Backend:
- `SECUREWAVE_PROVISIONING_TOKEN_SECRET`
- `SECUREWAVE_OPENVPN_AUTH_MODE` (default `mtls`)
- `SECUREWAVE_IKEV2_AUTH_MODE` (default `eap-tls`)
- `SECUREWAVE_OPENVPN_CERT_VALID_DAYS` (default `30`)
- `SECUREWAVE_IKEV2_CERT_VALID_DAYS` (default `30`)
- `SECUREWAVE_PROVISIONING_TOKEN_TTL_SECONDS` (default `300`)

Server-side helper compatibility:
- OpenVPN helpers: `/usr/local/bin/securewave-openvpn-issue-client`, `/usr/local/bin/securewave-openvpn-revoke-client`
- IKEv2 helpers: `/usr/local/bin/securewave-ikev2-issue-client`, `/usr/local/bin/securewave-ikev2-revoke-client`

## Known Constraints / Risks
1. TCP 443 for OpenVPN is intentionally disabled by default to avoid HTTPS conflict; script only enables if port 443 is free.
2. IKEv2 revocation depends on on-host CA DB/CRL state continuity; manual tampering with CA index files can break revoke workflow.
3. Full live validation of `nginx -t` and `ufw status` could not run inside this sandbox due missing binary / root requirement.
