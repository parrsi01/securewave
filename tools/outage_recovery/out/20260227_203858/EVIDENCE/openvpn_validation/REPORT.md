# Egress Check Report

- Protocol:       **openvpn**
- Baseline public IP: **92.105.134.148**
- VPN-on public IP (majority): **** (votes=)
- Interface-bound IP: ****
- Tunnel up: **true**
- Route decision dev/src: **tun-egress-proo / 10.9.0.2**
- Route indicates VPN path: **true**
- Tcpdump indicates VPN path: **false**
- Default-if ESP/UDP4500 hits: **0**
- Default-if plain IP hits: **0**
- Tunnel-if hits: **0**
- VERDICT: **FAIL**
- REASON_CODE: **dns_only_no_default_route**

## Raw Artifacts
- Public IP raw: public_ip_raw.txt
- Route get: route_get.txt
- Default iface tcpdump: tcpdump_default.txt
- Tunnel iface tcpdump: tcpdump_tunnel.txt
- Result env: result.env
- Status log: status.log
