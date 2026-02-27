# SecureWave Untouched Follow-up (2026-02-27)

## Completed in this pass

1. Strict backend behavior for OpenVPN/IKEv2 provisioning
- Added typed error classification for protocol provisioning failures:
  - `openvpn_server_misconfigured` / `ikev2_server_misconfigured`
  - `openvpn_healthcheck_fail` / `ikev2_healthcheck_fail`
  - `openvpn_unavailable_region` / `ikev2_unavailable_region`
  - fallback `credential_provision_failed`
- Added blocking policy for provisioning failures so API no longer pretends success when server-side credential provisioning fails.
- Applied this in:
  - `/api/vpn/profile`
  - `/api/vpn/credentials/provision`
  - `/api/vpn/credentials/{credential_id}/rotate`

2. Protocol catalog gating tightened
- `/api/vpn/protocols` now marks OpenVPN/IKEv2 as misconfigured when capability flags exist but required server material is missing.
- Added protocol runtime health fields:
  - `health_status` (`healthy|degraded|unavailable`)
  - `health_reason` (typed code)
- Degraded protocol pools remain connectable to prioritize continuity over hard-fail behavior.
- Linux IKEv2 auth-mode mismatch (`eap-tls` backend mode vs Linux client expectation) now disables IKEv2 in catalog (`enabled=false`) with reason `ikev2_auth_mode_mismatch_linux`.

3. Client error/reason mapping updates
- Added new backend protocol error codes to VPN state classification so they surface as protocol-unavailable instead of generic backend errors.
- Added user-facing reason text mapping in settings protocol selector for the new reason codes.

4. DevOps health matrix endpoint + strict server filtering
- Added `/api/vpn/protocol-health` to expose protocol readiness by global and per-region matrix.
- Server selection now excludes protocol paths that are misconfigured/unusable before profile issuance:
  - `_select_server_for_protocol(...)`
  - explicit protocol candidate filtering in `/api/vpn/profile`

## Validation executed

### Backend tests
```bash
cd /home/sp/cyber-course/projects/securewave
.venv/bin/pytest -q tests/integration/test_vpn_protocols_endpoint.py tests/unit/test_vpn_error_classification.py
```
Result: `10 passed`

### Flutter tests
```bash
cd /home/sp/cyber-course/projects/securewave/securewave_app
flutter test test/protocol_selector_test.dart test/protocol_capability_matrix_test.dart test/state_machine/auto_connect_listener_test.dart
```
Result: `All tests passed`

## Remaining next steps

1. Real dataplane validation on host (outside sandbox)
- Run runtime probe against a live tunnel and confirm:
  - route decision (`ip route get 1.1.1.1`)
  - egress IP change
  - DNS resolution under tunnel

2. Hetzner server routing/NAT fix verification
- Confirm `net.ipv4.ip_forward=1`.
- Confirm NAT MASQUERADE exists for tunnel subnet to egress interface.
- Confirm WireGuard server config and client `AllowedIPs` align with full-tunnel expectations.

3. OpenVPN/IKEv2 production readiness
- Ensure server provisioning scripts and required materials exist on active servers:
  - OpenVPN CA and issue/revoke scripts
  - IKEv2 CA/remote_id and issue/revoke scripts
- Re-run protocol catalog checks; protocols should only appear enabled when actually provisionable.

## Notes
- This pass intentionally did not modify infrastructure deployment scripts or server firewall rules.
- Scope stayed minimal and auditable in app/backend control plane.
