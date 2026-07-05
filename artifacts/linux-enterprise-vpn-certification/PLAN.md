# SecureWave Linux Enterprise VPN Certification Plan

## Scope

This certification suite validates the Linux SecureWave VPN runtime for a 100 to
1000 user enterprise readiness review. It covers backend account/session flows,
VPN profile issuance, protocol metadata, usage metering, helper/runtime safety,
release packaging truth, and live tunnel evidence for WireGuard, OpenVPN, and
IKEv2.

## Safety Model

- Default load simulation runs only in `TESTING=true` with a temporary SQLite
  database and synthetic `example.com` certification users.
- Default simulation uses demo/WireGuard mock backend mode with an isolated
  `WG_CLIENT_IPV4_CIDR`, so no production VPN nodes, users, payment records, or
  peer registries are modified.
- Live runtime tunnel proofs are separate and require explicit opt-in with
  `--include-live-proofs`.
- External load testing against deployed infrastructure is intentionally not
  automated. Run it only after explicit authorization for SecureWave-owned
  infrastructure.
- Artifacts are redacted. Tokens, passwords, private keys, profile configs, CA
  material, QR codes, and email addresses must not be written in clear text.

## Automated Harness

Primary command:

```bash
.venv/bin/python scripts/linux_enterprise_vpn_certification.py \
  --cohorts 100 250 500 1000 \
  --workers 16
```

Optional live runtime proof command:

```bash
.venv/bin/python scripts/linux_app_vpn_tunnel_proof.py \
  --protocol wireguard --hold-seconds 120 --evidence-timeout 180 --json

.venv/bin/python scripts/linux_app_vpn_tunnel_proof.py \
  --protocol openvpn --hold-seconds 120 --evidence-timeout 180 --json

.venv/bin/python scripts/linux_app_vpn_tunnel_proof.py \
  --protocol ikev2 --hold-seconds 120 --evidence-timeout 180 --json
```

The harness writes redacted artifacts under:

```text
artifacts/linux-enterprise-vpn-certification/latest/
```

## Certification Dimensions

The harness exercises:

- user registration, login, logout, relogin, and authenticated account probes
- invalid token rejection
- server list and protocol availability under synthetic load
- WireGuard, OpenVPN, and IKEv2 profile issuance
- selected-server protocol support and incomplete metadata fail-closed behavior
- stale device id recovery
- free-tier device limit enforcement
- cross-user device access rejection
- connect notification, usage reporting, disconnect notification
- usage persistence across logout/login
- peer uniqueness and IP uniqueness
- key rotation sample
- latency percentiles and error rates per API group

Existing validation commands complete the broader release/runtime gate:

```bash
.venv/bin/pytest tests/unit/test_linux_runtime_guards.py \
  tests/unit/test_linux_vpn_runner_contract.py \
  tests/unit/test_linux_app_vpn_tunnel_proof.py \
  tests/unit/test_linux_vpn_runtime_verifier.py \
  tests/integration/test_auth.py \
  tests/integration/test_vpn_profile.py \
  tests/integration/test_vpn_flow.py -q

flutter test test/mock_vpn_service_test.dart test/vpn_state_test.dart \
  test/live_payload_parsing_test.dart

.venv/bin/python scripts/linux_vpn_runtime_verifier.py

.venv/bin/python scripts/linux_app_vpn_tunnel_proof.py \
  --protocol wireguard --hold-seconds 120 --evidence-timeout 180 --json

.venv/bin/python scripts/linux_app_vpn_tunnel_proof.py \
  --protocol openvpn --hold-seconds 120 --evidence-timeout 180 --json

.venv/bin/python scripts/linux_app_vpn_tunnel_proof.py \
  --protocol ikev2 --hold-seconds 120 --evidence-timeout 180 --json
```

## Readiness Rule

SecureWave can be called enterprise-ready for a cohort only when:

- the safe local cohort simulation passes with no endpoint failures
- all protocol profile issuance counts equal the cohort size
- usage aggregates match expected session totals within documented tolerance
- cross-user access and malformed/unsupported protocol paths fail closed
- Linux runtime verifier reports all checks OK
- live tunnel proof passes for WireGuard, OpenVPN, and IKEv2
- no post-run WireGuard, OpenVPN, IKEv2, route, policy, pref-220, or adblock
  residue remains
