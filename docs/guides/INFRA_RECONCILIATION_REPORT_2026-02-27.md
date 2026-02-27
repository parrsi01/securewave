# INFRA_RECONCILIATION_REPORT_2026-02-27

## Scope
- Target VPS: `138.199.204.139` (`securewave-prod`)
- Repo: `/home/sp/cyber-course/projects/securewave`
- Evidence root: `tools/infra_reconcile/out/20260227_191554/`
- Constraint honored: no Flutter code changes, no backend logic changes.

## Before Snapshot
- Full baseline captured at:
  - `tools/infra_reconcile/out/20260227_191554/base_snapshot.txt`
- Key pre-fix state:
  - Forwarding already enabled (`ip_forward=1`, IPv6 forwarding enabled)
  - NAT present for VPN subnets
  - UFW persistent allow existed for `51820/udp`, but not explicitly for `1194/500/4500`
  - WireGuard contained one orphan peer with no `AllowedIPs`
  - OpenVPN and strongSwan daemons running (service unit names differed: `openvpn-server@server`, `strongswan-starter`)

## Detected Root Causes
Detailed A-J classification is in:
- `tools/infra_reconcile/out/20260227_191554/analysis_report.md`

Primary actionable issues:
1. UFW persistence gap for `1194/udp`, `500/udp`, `4500/udp`.
2. Reverse-path filter effective value was strict (`rp_filter=1`) due `99-wireguard.conf` override.
3. WireGuard stale peer with missing `AllowedIPs`.

## Patch Applied (Minimal/Additive)
Command transcript:
- `tools/infra_reconcile/out/20260227_191554/patch_actions.txt`

Changes applied on VPS:
1. Runtime + persistent sysctl hardening
- Set:
  - `net.ipv4.ip_forward=1`
  - `net.ipv6.conf.all.forwarding=1`
  - `net.ipv4.conf.all.rp_filter=2`
  - `net.ipv4.conf.default.rp_filter=2`
- Wrote:
  - `/etc/sysctl.d/99-securewave-vpn.conf`
- Added override to beat late wireguard sysctl file:
  - `/etc/sysctl.d/100-securewave-vpn-override.conf`

2. Firewall persistence for protocol ports
- Added UFW rules:
  - `ufw allow 1194/udp`
  - `ufw allow 500/udp`
  - `ufw allow 4500/udp`

3. Routing/firewall guard rules (idempotent)
- Ensured existing wg/tun forward rules and NAT subnet rules
- Added IPsec policy forward accepts:
  - `-m policy --pol ipsec --dir in -j ACCEPT`
  - `-m policy --pol ipsec --dir out -j ACCEPT`

4. WireGuard stale peer cleanup
- Removed runtime peer that had `AllowedIPs=(none)`
- Removed matching orphan peer block from `/etc/wireguard/wg0.conf`

5. Service restarts
- `wg-quick@wg0`
- `openvpn-server@server` (fallback to `openvpn@server` if needed)
- `strongswan` or `strongswan-starter` (starter active)

## Post-Fix Verification
Post snapshot:
- `tools/infra_reconcile/out/20260227_191554/post_snapshot.txt`
- Final effective-state check after `rp_filter` override:
  - `tools/infra_reconcile/out/20260227_191554/final_postcheck.txt`

Additional protocol checks:
- WireGuard isolated self-test:
  - `tools/infra_reconcile/out/20260227_191554/wireguard_selftest.txt`
  - Result: default route via wg test interface + successful ping to `1.1.1.1`
- OpenVPN local mTLS self-test:
  - `tools/infra_reconcile/out/20260227_191554/openvpn_selftest.txt`
  - Result: `Initialization Sequence Completed`
- OpenVPN route/ping sanity:
  - `tools/infra_reconcile/out/20260227_191554/openvpn_selftest_with_ping.txt`
- IKEv2 automated EAP test (pexpect + charon-cmd):
  - `tools/infra_reconcile/out/20260227_191554/ikev2_selftest_pexpect.txt`
  - Result: reached `EAP_MSCHAPV2` success, `IKE_SA` established, CHILD SA/TS negotiated (`10.10.0.x/32 === 0.0.0.0/0`)

## PASS/FAIL Matrix
| Section | Result | Notes |
|---|---|---|
| WireGuard infra (listen/NAT/forward) | PASS | Listener, NAT, and forward path validated; wg self-test route+ping successful |
| WireGuard full-tunnel route behavior | PASS | Namespace self-test shows `route get 1.1.1.1` via wg test iface |
| OpenVPN TLS handshake + tunnel bring-up | PASS | Controlled cert-based client completed initialization |
| OpenVPN external public-IP-change proof | PARTIAL | Same-host self-tests are not authoritative for external egress-IP change |
| IKEv2 SA establishment | PASS | Automated EAP/MSCHAPv2 succeeded; IKE_SA/CHILD SA negotiated |
| IKEv2 external public-IP-change proof | PARTIAL | External client egress-IP change not captured in this run |
| Firewall persistence for all 3 protocols | PASS | UFW now explicitly allows 51820/1194/500/4500 UDP |
| Routing/NAT safety constraints | PASS | No flushes, no default DROP policy rewrites, additive-only changes |

## Final Verdict
**PARTIAL (infra reconciled, external egress-IP certification pending)**

The VPS control/data-plane prerequisites are now aligned and protocol daemons negotiate correctly under controlled tests. Remaining gap is external-client proof of public-IP change for OpenVPN/IKEv2 in this run.
