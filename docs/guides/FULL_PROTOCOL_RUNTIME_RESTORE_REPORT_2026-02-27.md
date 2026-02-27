# SecureWave Full Protocol Runtime Restore Report (2026-02-27)

## Scope
- Objective: restore and verify real dataplane functionality for WireGuard, OpenVPN, and IKEv2.
- Constraints honored:
  - No simulation mode changes.
  - No UI changes.
  - Runtime/infrastructure and provisioning only.

## Phase 1: Remote Server Audit (Hetzner `138.199.204.139`)

### Reachability
Commands:
```bash
ping -c 3 138.199.204.139
ssh root@138.199.204.139 'echo SSH_OK && hostname && uname -a'
```
Results:
- `ping`: 100% packet loss (ICMP filtered).
- `ssh`: reachable; host operational (`securewave-prod`).

### System and routing state
Commands:
```bash
ssh root@138.199.204.139 'sysctl net.ipv4.ip_forward'
ssh root@138.199.204.139 'iptables -t nat -S'
ssh root@138.199.204.139 'nft list ruleset'
ssh root@138.199.204.139 'ip route'
ssh root@138.199.204.139 'ufw status verbose'
ssh root@138.199.204.139 'ip route get 1.1.1.1'
```
Results:
- `net.ipv4.ip_forward = 1`
- NAT MASQUERADE present for `10.8.0.0/24` (WG), `10.9.0.0/24` (OpenVPN), `10.10.0.0/24` (IKEv2)
- Default route via `172.31.1.1 dev eth0`
- UFW active with required inbound allow rules (`51820/udp`, `22/tcp`, `80/tcp`, `443/tcp`), plus nft accept rules for UDP `1194`, `500`, `4500`.

### WireGuard audit
Commands:
```bash
ssh root@138.199.204.139 'systemctl status wg-quick@wg0 --no-pager'
ssh root@138.199.204.139 'wg show'
ssh root@138.199.204.139 'ss -lunp | grep 51820'
```
Results:
- `wg-quick@wg0`: active.
- Handshakes observed on active peers.
- UDP `51820` listening.

### OpenVPN audit
Commands:
```bash
ssh root@138.199.204.139 'systemctl status openvpn-server@server --no-pager'
ssh root@138.199.204.139 'ss -lunp | grep 1194'
ssh root@138.199.204.139 'ls -l /usr/local/bin/securewave-openvpn-*'
```
Results:
- `openvpn-server@server`: active.
- UDP `1194` listening.
- Provisioning scripts present and executable:
  - `/usr/local/bin/securewave-openvpn-issue-client`
  - `/usr/local/bin/securewave-openvpn-upsert-user`
  - `/usr/local/bin/securewave-openvpn-revoke-client`

### IKEv2 audit
Commands:
```bash
ssh root@138.199.204.139 'systemctl status strongswan-starter --no-pager'
ssh root@138.199.204.139 'ipsec statusall'
ssh root@138.199.204.139 'ss -lunp | grep -E ":500|:4500"'
ssh root@138.199.204.139 'ls -l /usr/local/bin/securewave-ikev2-*'
```
Results:
- `strongswan-starter`: active.
- IKEv2 profile loaded; pools configured.
- UDP `500` and `4500` listening.
- Provisioning scripts present and executable:
  - `/usr/local/bin/securewave-ikev2-issue-client`
  - `/usr/local/bin/securewave-ikev2-upsert-user`
  - `/usr/local/bin/securewave-ikev2-revoke-client`

## Phase 2: Repair Actions Applied

### 1) OpenVPN provisioning endpoint fix (critical)
Observed failure before fix:
```text
TCP/UDP: Preserving recently used remote address: [AF_INET]127.0.1.1:1194
UDP link remote: [AF_INET]127.0.1.1:1194
```
Root cause:
- `/usr/local/bin/securewave-openvpn-issue-client` fallback used `hostname -f`, resolving to loopback (`127.0.1.1`) on this node.

Fix applied:
- Endpoint fallback now resolves in this order:
  1. `OPENVPN_SERVER_PUBLIC_HOST`
  2. `ip -4 route get 1.1.1.1` source IP
  3. `curl https://api.ipify.org`
  4. `hostname -I`
  5. `hostname -f`

Before/after diff (live node):
```diff
@@
 REMOTE_HOST="${OPENVPN_SERVER_PUBLIC_HOST:-}"
 if [[ -z "${REMOTE_HOST}" ]]; then
+  REMOTE_HOST="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '/src/ {for (i=1; i<=NF; i++) if ($i=="src") {print $(i+1); exit}}')"
+fi
+if [[ -z "${REMOTE_HOST}" ]]; then
+  REMOTE_HOST="$(curl -4fsS --max-time 3 https://api.ipify.org 2>/dev/null || true)"
+fi
+if [[ -z "${REMOTE_HOST}" ]]; then
+  REMOTE_HOST="$(hostname -I 2>/dev/null | awk '{print $1}')"
+fi
+if [[ -z "${REMOTE_HOST}" ]]; then
   REMOTE_HOST="$(hostname -f 2>/dev/null || hostname)"
 fi
```

Post-fix profile proof:
```text
remote 138.199.204.139 1194
```

### 2) IKEv2 client validation dependency
Action:
```bash
ssh root@138.199.204.139 'apt-get install -y charon-cmd'
```
- Added client-side test tool only; server tunnel runtime unchanged.

## Phase 3: Routing + NAT Validation

Validated:
- `ip_forward=1`.
- NAT MASQUERADE rules exist for all VPN subnets.
- No conflicting rule prevented tunnel egress during tests.
- Route decision checks:
  - Node route: default via `eth0` gateway.
  - Test namespace connected state route flips to tunnel path and disconnect reverts.

## Phase 4: Deterministic Per-Protocol Runtime Validation (Linux namespace clients)

Artifacts on node:
- WireGuard: `/root/swrt_wg_test_20260227_143339`
- OpenVPN: `/root/swrt_ovpn_test_20260227_143632`
- IKEv2: `/root/swrt_ike_test_20260227_144233`

### WireGuard
Proof points:
- Handshake:
  - client `latest handshake: 2 seconds ago`
  - server peer transfer: `820 B received, 732 B sent`
- Interface and traffic:
  - ping `10.8.0.1` success, ping `1.1.1.1` success
- Routing cleanup:
  - connected: `default dev swg0`
  - after disconnect: `default dev swg0` removed

### OpenVPN
Proof points:
- Profile issued and connected:
  - `Initialization Sequence Completed`
- Interface and traffic:
  - ping `10.9.0.1` success, ping `1.1.1.1` success
  - tun counters: `rx=1967 tx=4910`
- Egress proof:
  - before: `unreachable`
  - after: `138.199.204.139`
- Routing cleanup:
  - connected: `0.0.0.0/1 via 10.9.0.1`, `128.0.0.0/1 via 10.9.0.1`
  - after disconnect: split default routes removed

### IKEv2
Proof points:
- SA establishment:
  - `ESTABLISHED ... 10.215.0.2[sw_probe_user]`
  - CHILD SA `INSTALLED`
- Interface and traffic:
  - `ipsec0` present with `10.10.0.10/32`
  - ping `1.1.1.1` success
- Egress proof:
  - before: `unreachable`
  - after: `138.199.204.139`
- Disconnect cleanup:
  - post-disconnect status has no `sw_probe_user` SA
  - `ipsec0` removed
  - default route reverted to namespace veth gateway

## Validation Matrix

| Scenario | Expected Behavior | Result |
|---|---|---|
| WireGuard connect | Handshake + data transfer + internet reachability | PASS |
| WireGuard disconnect | Tunnel route removed | PASS |
| OpenVPN profile issuance | Client profile points to public endpoint | PASS (fixed from 127.0.1.1) |
| OpenVPN connect | Tun up + initialization completed + traffic | PASS |
| OpenVPN disconnect | Redirect routes removed | PASS |
| IKEv2 connect | IKE SA + CHILD SA established + traffic | PASS |
| IKEv2 disconnect | SA removed + ipsec interface gone | PASS |

## Repository Files Changed (for persistence)
- `scripts/provision_openvpn.sh`
- `scripts/ops/restore_openvpn_ikev2_hetzner.sh`
- `docs/guides/FULL_PROTOCOL_RUNTIME_RESTORE_REPORT_2026-02-27.md`

## End Section
### what changed
- Repaired OpenVPN issued profile endpoint fallback to avoid loopback endpoint leakage.
- Verified and documented full real dataplane bring-up/teardown for WG/OpenVPN/IKEv2.
- Applied corresponding persistence fix in repo provisioning scripts.

### what reused
- Existing VPN service units and existing provisioning scripts.
- Existing NAT/UFW/nft routing posture on node.

### untouched
- Simulation mode paths.
- Flutter/UI code.
- WireGuard/OpenVPN/IKEv2 core runtime internals beyond provisioning endpoint selection logic.

### risks
- Egress-IP checks were performed from server-hosted Linux namespaces; external client-network path variation is not covered by this run.
- OpenVPN endpoint fallback now depends on route/public-IP discovery tools (`ip`, optional `curl`). If both fail, it still falls back to hostname.
