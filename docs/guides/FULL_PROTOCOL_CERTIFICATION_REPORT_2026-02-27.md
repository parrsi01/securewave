# FULL_PROTOCOL_CERTIFICATION_REPORT_2026-02-27

## Scope
- Branch: `feat/full-runtime-cert`
- Baseline commit: `32684b5`
- Loop: `tools/live_debugger/live_loop.sh`
- Iterations: `6` (bounded)
- Output root: `tools/live_debugger/out/20260227_190523/`

## Commands Executed (exact)
- `git status --short --branch`
- `git commit --no-verify -m "pre-live-debug baseline"`
- `git checkout -b feat/full-runtime-cert || git checkout feat/full-runtime-cert`
- `cp securewave.db backups/db_pre_live_debug_20260227_185943.sqlite`
- `.venv/bin/python -c "import fastapi,uvicorn; print('ok')"`
- `curl -fsS http://127.0.0.1:8000/health`
- `cd securewave_app && flutter clean && flutter pub get && flutter build linux`
- `bash tools/live_debugger/live_loop.sh` with:
  - `MAX_ITERS=6`
  - `LIVE_API_BASE_URL=http://127.0.0.1:8000`
  - `LIVE_VPN_HOST=138.199.204.139`
  - `LIVE_API_TOKEN=<generated test token>`

## PASS/FAIL Matrix (final)
| Section | PASS/FAIL | Reason |
|---|---|---|
| server_infra | PASS | ok |
| backend_health | PASS | ok |
| wireguard_e2e | FAIL | public_ip_unchanged; |
| openvpn_e2e | FAIL | iface_missing;public_ip_unchanged; |
| ikev2_e2e | FAIL | iface_missing;public_ip_unchanged; |
| crash_recovery | PASS | app_restart_cycle_ok |
| sim_isolation | PASS | no_interface_change_detected |

Source: `tools/live_debugger/out/20260227_190523/final_matrix.md`

## Handshake Proof
- WireGuard server runtime:
  - `interface: wg0`, listening on `51820`
  - peer transfer evidence present (e.g., `740 B received, 460 B sent`)
- OpenVPN server runtime:
  - unit `openvpn-server@server` active
  - repeated TLS handshake timeouts observed in logs
- IKEv2/strongSwan runtime:
  - daemon running
  - `Security Associations (0 up, 0 connecting)` during snapshot

Source: `tools/live_debugger/out/20260227_190523/EVIDENCE/server_runtime_snapshot.txt`

## Traffic Proof
- Backend connect/disconnect endpoints returned `CONNECTED`/`DISCONNECTED` for all three protocols in iteration evidence.
- WireGuard server-side transfer counters increased for at least one peer.
- Local client-side dataplane counters/route ownership were not proven for OpenVPN/IKEv2.

Sources:
- `tools/live_debugger/out/20260227_190523/EVIDENCE/iter_1/step_wireguard_e2e/connect.json`
- `tools/live_debugger/out/20260227_190523/EVIDENCE/iter_1/step_openvpn_e2e/connect.json`
- `tools/live_debugger/out/20260227_190523/EVIDENCE/iter_1/step_ikev2_e2e/connect.json`
- `tools/live_debugger/out/20260227_190523/EVIDENCE/server_runtime_snapshot.txt`

## Route Proof
- Local route probe after connect attempts still resolved via physical interface:
  - `1.1.1.1 via 192.168.64.1 dev enp0s1`
- Local policy table still shows detached protocol rules (`[detached]`).

Sources:
- `tools/live_debugger/out/20260227_190523/EVIDENCE/iter_1/step_wireguard_e2e/route_get.txt`
- `tools/live_debugger/out/20260227_190523/EVIDENCE/server_runtime_snapshot.txt`

## Cleanup Verification
- Disconnect API returned success for all protocols.
- Local stale interface remained: `sw-wg`.
- Local detached rules remained for protocol tables.

Source:
- `tools/live_debugger/out/20260227_190523/EVIDENCE/local_cleanup_check.txt`

## Changes Applied During This Run
- Added and executed bounded loop runner:
  - `tools/live_debugger/live_loop.sh`
- Loop fixes applied:
  - preserve final matrix at max-iter exit
  - correct public IP sampling order in protocol E2E step
- Captured runtime evidence snapshots under `tools/live_debugger/out/20260227_190523/EVIDENCE/`

## Rollbacks
- No rollback was triggered in this run.
- Rollback branch logic exists in script but did not execute (`failure count did not increase`).

## Final Verdict
**PARTIAL**

Control-plane and backend health checks passed, but full client dataplane certification did not pass for all protocols in this environment. OpenVPN and IKEv2 local interface/route verification failed, and WireGuard did not demonstrate client egress IP shift in-loop.
