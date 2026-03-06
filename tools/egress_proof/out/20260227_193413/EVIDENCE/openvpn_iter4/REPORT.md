# Egress Check Report

- Protocol:       **openvpn**
- Baseline public IP: **185.100.234.112**
- VPN-on public IP (majority): **138.199.204.139** (votes=2)
- Interface-bound IP: ****
- Tunnel up: **true**
- Route decision dev/src: **eth0 / 138.199.204.139**
- Route indicates VPN path: **false**
- Tcpdump indicates VPN path: **false**
- Default-if ESP/UDP4500 hits: **0**
- Default-if plain IP hits: **0**
- Tunnel-if hits: **0**
- VERDICT: **FAIL**
- REASON_CODE: **route_metric_prefers_physical**

## Raw Artifacts
- Public IP raw: 
- Route get: 
- Default iface tcpdump: 
- Tunnel iface tcpdump: 
- Result env: 
- Status log: 
