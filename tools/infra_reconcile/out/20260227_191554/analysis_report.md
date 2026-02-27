# Infra Root Cause Analysis (2026-02-27T19:15:54Z)

Source snapshot:
- `tools/infra_reconcile/out/20260227_191554/base_snapshot.txt`

## Pattern Detection

| Pattern | Result | Evidence |
|---|---|---|
| A) `ip_forward` disabled | NO | `net.ipv4.ip_forward = 1`, `net.ipv6.conf.all.forwarding = 1` |
| B) Missing MASQUERADE | NO | NAT had subnet masquerade for `10.8.0.0/24`, `10.9.0.0/24`, `10.10.0.0/24` on `eth0` |
| C) MASQUERADE on wrong outbound iface | NO | default route uses `eth0`; MASQ rules also on `eth0` |
| D) Missing FORWARD ACCEPT | PARTIAL | wg/tun/10.10 rules present; added explicit IPsec policy-forward accept rules |
| E) nftables overriding iptables | NO DIRECT CONFLICT | UFW nft chains mirrored existing allow/forward behavior; no conflicting drop specific to VPN ports observed |
| F) Cloud firewall blocking UDP 51820/1194/500/4500 | UNKNOWN (console not accessible) | VPS listeners present for all required UDP ports; UFW now explicitly allows all four |
| G) WireGuard AllowedIPs mismatch | YES (fixed) | Found orphan peer with `AllowedIPs=(none)` in `wg show`; removed runtime peer + cleaned `wg0.conf` |
| H) FwMark/policy routing misalignment | NO | Server uses main-table routing for VPN gateway role; no broken fwmark rules required/observed |
| I) OpenVPN cert mismatch | NO | Server cert/CA valid; local OpenVPN mTLS self-test completed (`Initialization Sequence Completed`) |
| J) StrongSwan auth mismatch | NO (config path valid) | Automated IKEv2 EAP test reached successful EAP/MSCHAPv2 and IKE_SA/CHILD_SA establishment |

## High-Value Findings
1. UFW persisted only `51820/udp` initially; `1194/500/4500` were present in iptables but not persisted in UFW rules. This was corrected.
2. `rp_filter` was effectively strict (`1`) because `/etc/sysctl.d/99-wireguard.conf` overrode previous settings. Added higher-priority override to enforce loose mode (`2`) for VPN asymmetric paths.
3. WireGuard had one stale peer with missing `AllowedIPs`; removed to avoid undefined routing behavior.
4. OpenVPN repeated TLS timeouts from source `172.30.12.2` existed in logs, but controlled self-test with valid client cert succeeded; issue likely from a separate probe/client path, not core daemon/NAT/firewall breakage.

## Recommended Follow-up (outside this patch)
- Validate the source/process at `172.30.12.2` that repeatedly triggers failed OpenVPN handshakes.
- Run one external IKEv2/Linux client test (not loopback) to capture public IP change proof.
