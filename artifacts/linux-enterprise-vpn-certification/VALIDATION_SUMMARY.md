# SecureWave Linux Enterprise VPN Validation Summary

## Branch

- `codex/linux-enterprise-vpn-certification`

## Commands And Results

| Command | Result |
| --- | --- |
| `.venv/bin/python scripts/linux_enterprise_vpn_certification.py --cohorts 100 250 500 1000 --workers 16 --output-dir artifacts/linux-enterprise-vpn-certification/latest` | PASS; 100, 250, 500, and 1000 modeled users completed with zero endpoint failures |
| `.venv/bin/pytest tests/unit/test_linux_enterprise_vpn_certification.py tests/unit/test_vpn_service.py::TestIPAllocation tests/integration/test_vpn_profile.py -q` | PASS; 23 passed |
| `.venv/bin/pytest tests/integration/test_auth.py tests/integration/test_vpn_flow.py tests/unit/test_downloads_manifest.py tests/unit/test_linux_app_vpn_tunnel_proof.py -q` | PASS; 60 passed |
| `(cd securewave_app && flutter test test/mock_vpn_service_test.dart test/vpn_state_test.dart)` | PASS; all tests passed |
| `.venv/bin/python scripts/linux_vpn_runtime_verifier.py` | PASS before and after live proofs; all checks OK |
| `.venv/bin/python scripts/linux_app_vpn_tunnel_proof.py --protocol wireguard --hold-seconds 120 --evidence-timeout 180 --json` | PASS; route used `sw-wg`, exit IP moved `92.105.134.148 -> 138.199.204.139`, DNS/data plane/backend health/counters passed |
| `.venv/bin/python scripts/linux_app_vpn_tunnel_proof.py --protocol openvpn --hold-seconds 120 --evidence-timeout 180 --json` | PASS; route used `tun0`, exit IP moved `92.105.134.148 -> 138.199.204.139`, DNS/data plane/backend health/process/log checks passed |
| `.venv/bin/python scripts/linux_app_vpn_tunnel_proof.py --protocol ikev2 --hold-seconds 120 --evidence-timeout 180 --json` | PASS; NM active, DNS/route/XFRM helper evidence passed, exit IP moved `92.105.134.148 -> 138.199.204.139`, pref-220 tripwire clean |
| `git diff --check` | PASS |
| `python3 -m compileall -q scripts/linux_enterprise_vpn_certification.py services/vpn_peer_manager.py routes/devices.py routes/vpn.py` | PASS |
| `python3 -m json.tool` over latest JSON artifacts | PASS |
| `docker compose -f deploy/hetzner/compose.yaml config` | BLOCKED locally; required `POSTGRES_PASSWORD` was not set |

## Scale Summary

| Cohort | Status | Duration s | Users Completed | Endpoint Failures | Usage Integrity | Duplicate Public Keys | Duplicate IPs |
| ---: | --- | ---: | ---: | ---: | --- | ---: | ---: |
| 100 | pass | 21.962 | 100 | 0 | pass | 0 | 0 |
| 250 | pass | 55.750 | 250 | 0 | pass | 0 | 0 |
| 500 | pass | 135.117 | 500 | 0 | pass | 0 | 0 |
| 1000 | pass | 314.246 | 1000 | 0 | pass | 0 | 0 |

## Root Cause Of Gaps Found

- The backend WireGuard peer allocator had a hardcoded `10.8.0.10-254` client range. That exhausted before the 1000-user cohort and made enterprise-scale profile issuance fail even in the safe local certification database.
- Key rotation in mock/test mode still attempted external WireGuard server-manager synchronization. That made the bounded certification harness slow and could touch non-local sync paths even though the route was intended to remain database-local.

## Fixes Validated

- Added configurable `WG_CLIENT_IPV4_CIDR` and `WG_CLIENT_IPV4_START_OFFSET` while preserving the existing default first address, `10.8.0.10/32`.
- Serialized in-process peer allocation to prevent duplicate local allocations during concurrent profile issuance.
- Set the certification harness to use an isolated `/20` client CIDR for 1000-user simulation.
- Skipped external WireGuard server sync during mock/test key rotation while preserving local key rotation and production sync behavior.
