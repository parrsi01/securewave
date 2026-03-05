# Egress Proof Certification Report (2026-02-27)

## Scope
- Goal: make OpenVPN + IKEv2 pass strict egress proof checks for full-tunnel mode.
- Added harness + bounded fix loop:
  - `tools/egress_proof/egress_check.sh`
  - `tools/egress_proof/fix_and_verify.sh`
- Final evidence run:
  - `tools/egress_proof/out/20260227_200413/`

## Baseline
- Baseline public IP (3-endpoint majority): `92.105.134.148`
- VPS host under test: `138.199.204.139`
- Max iterations: `4`

## Final Matrix
| Protocol | Negotiation | Egress Proof | PASS/FAIL | Reason |
|---|---|---|---|---|
| openvpn | true | true | FAIL | dns_only_no_default_route |
| ikev2 | true | false | FAIL | split_tunnel_routes |

## OpenVPN Evidence (iter4)
- Tunnel established: `true` (self-test connected)
- Route-get now resolves via VPN path:
  - `ip route get 1.1.1.1` => `dev tun0 src 10.9.0.1`
- Public IP proof still absent:
  - majority IP response empty during tunnel-on checks
  - interface-bound curl IP empty
- Verdict: `FAIL` (`dns_only_no_default_route`)

Interpretation:
- Default route steering improved (VPN path selected), but end-to-end internet egress proof did not complete successfully under strict checks.

## IKEv2 Evidence (iter4)
- SA negotiation established: `true` (self-test connected)
- Route-get remains on physical NIC:
  - `ip route get 1.1.1.1` => `via 172.31.1.1 dev eth0 src 138.199.204.139`
- No ESP/UDP4500 proof for checked egress test flow.
- Verdict: `FAIL` (`split_tunnel_routes`)

Interpretation:
- IKEv2 control-plane negotiation works, but full-tunnel default egress remains split-routed to physical interface.

## Fix Attempts Applied (Idempotent)
- OpenVPN server config guardrails repeatedly enforced:
  - `push "redirect-gateway def1 bypass-dhcp"`
  - DNS push lines for `1.1.1.1` and `8.8.8.8`
  - forwarding/NAT prerequisites checked
- IKEv2 server config guardrails repeatedly enforced:
  - full-tunnel related config checks in `/etc/ipsec.conf`
  - forwarding/NAT/rp_filter guardrails checked
- Runtime safety:
  - backups and patch snapshots captured each iteration
  - no destructive flushes

Note:
- Patch diff files in `PATCHES/` are effectively empty in this run, indicating target directives were already present and no additional server-side line deltas were introduced.

## Local Script Hardening Implemented
1. Fixed report heredoc bug in `egress_check.sh` (removed accidental command substitutions).
2. Fixed IKEv2 helper teardown hang by disowning helper background PID.
3. Added bounded SSH/SCP execution timeout in `fix_and_verify.sh` (`SSH_CMD_TIMEOUT`) to avoid indefinite hangs.
4. Corrected OpenVPN self-test flow so server `tun0` does not mask missing client-side proof setup.

## Conclusion
- OpenVPN: partial improvement (route path now points to tunnel) but strict egress/public-IP proof still fails.
- IKEv2: negotiation succeeds but egress remains split-routed (not full-tunnel proven).
- Current certification verdict: **PARTIAL / NOT PASS** for the requested OpenVPN + IKEv2 egress objective.
