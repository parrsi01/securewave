# Tunnel Probe Report

- Run ID: `20260227_002856`
- Output dir: `/home/sp/cyber-course/projects/securewave/tools/runtime_probe/out/20260227_002856`

## Summary Verdicts

- Tunnel up (wg/tun interface visible post-connect): **yes**
- WireGuard handshake observed (if WireGuard): **unknown**
- Default route changed: **no**
- Policy route/rule present post-connect (table 51820/fwmark): **yes**
- Routing mode inferred: **policy_tunnel_rule_table**
- Egress IP changed: **yes**
- DNS state changed: **yes**
- DNS resolver changed: **no**
- DNS query validation post-connect: **yes**
- Route decision (`ip route get 1.1.1.1`) interface changed: **yes**
- Post-disconnect tunnel interface removed: **yes**
- Leaks: **manual review required** (`egress_cloudflare_trace.txt`, route/firewall excerpts, post_disconnect bundle)

## Baseline vs Post-connect

| Signal | Baseline | Post-connect |
|---|---|---|
| Default route | `default via 192.168.64.1 dev enp0s1 proto dhcp src 192.168.64.2 metric 100 ` | `default via 192.168.64.1 dev enp0s1 proto dhcp src 192.168.64.2 metric 100 ` |
| Routing mode | `n/a` | `policy_tunnel_rule_table` |
| `ip route get 1.1.1.1` iface | `enp0s1` | `sw-wg` |
| Egress IP (ipify) | `92.105.134.148` | `138.199.204.139` |
| DNS resolver (primary) | `192.168.64.1` | `192.168.64.1` |
| DNS query validation | `yes` | `yes` |

## Post-disconnect Snapshot

- Default route: `default via 192.168.64.1 dev enp0s1 proto dhcp src 192.168.64.2 metric 100 `
- `ip route get 1.1.1.1` iface: `enp0s1`
- Egress IP (ipify): `92.105.134.148`

## Captured Files

### Baseline (`baseline/`)

- `baseline/date.txt`
- `baseline/uname.txt`
- `baseline/ip_addr.txt`
- `baseline/ip_route.txt`
- `baseline/resolvectl_status.txt`
- `baseline/wg_show.txt`
- `baseline/egress_ifconfig_me.txt`
- `baseline/egress_ipify.txt`
- `baseline/egress_cloudflare_trace.txt`
- `baseline/dns_lookup_example.txt`
- `baseline/dns_https_check.txt`
- `baseline/ip_route_get_1.1.1.1.txt`
- `baseline/ip_route_get_8.8.8.8.txt`
- `baseline/ip_rule_show.txt`
- `baseline/firewall_rules_excerpt.txt`
- `baseline/tcpdump_sample_note.txt`

### Post-connect (`post_connect/`)

- `post_connect/date.txt`
- `post_connect/uname.txt`
- `post_connect/ip_addr.txt`
- `post_connect/ip_route.txt`
- `post_connect/resolvectl_status.txt`
- `post_connect/wg_show.txt`
- `post_connect/egress_ifconfig_me.txt`
- `post_connect/egress_ipify.txt`
- `post_connect/egress_cloudflare_trace.txt`
- `post_connect/dns_lookup_example.txt`
- `post_connect/dns_https_check.txt`
- `post_connect/ip_route_get_1.1.1.1.txt`
- `post_connect/ip_route_get_8.8.8.8.txt`
- `post_connect/ip_rule_show.txt`
- `post_connect/firewall_rules_excerpt.txt`
- `post_connect/tcpdump_sample_note.txt`

### Post-disconnect (`post_disconnect/`)

- `post_disconnect/date.txt`
- `post_disconnect/uname.txt`
- `post_disconnect/ip_addr.txt`
- `post_disconnect/ip_route.txt`
- `post_disconnect/resolvectl_status.txt`
- `post_disconnect/wg_show.txt`
- `post_disconnect/egress_ifconfig_me.txt`
- `post_disconnect/egress_ipify.txt`
- `post_disconnect/egress_cloudflare_trace.txt`
- `post_disconnect/dns_lookup_example.txt`
- `post_disconnect/dns_https_check.txt`
- `post_disconnect/ip_route_get_1.1.1.1.txt`
- `post_disconnect/ip_route_get_8.8.8.8.txt`
- `post_disconnect/ip_rule_show.txt`
- `post_disconnect/firewall_rules_excerpt.txt`
- `post_disconnect/tcpdump_sample_note.txt`

### PCAPs (`pcap/`)

- Optional interface captures if sudo+tcpdump were available.
