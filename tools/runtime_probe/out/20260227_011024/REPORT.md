# Tunnel Probe Report

- Run ID: `20260227_011024`
- Output dir: `/home/sp/cyber-course/projects/securewave/tools/runtime_probe/out/20260227_011024`

## Summary Verdicts

- Connect command exit status: **127**
- Disconnect command exit status: **127**
- Tunnel up (wg/tun interface visible post-connect): **no**
- WireGuard handshake observed (if WireGuard): **unknown**
- Default route changed: **no**
- Policy route/rule present post-connect (table 51820/fwmark): **no**
- Routing mode inferred: **no_tunnel_routing_detected**
- Egress IP changed: **unknown**
- DNS state changed: **no**
- DNS resolver changed: **unknown**
- DNS query validation post-connect: **unknown**
- Route decision (`ip route get 1.1.1.1`) interface changed: **no**
- Post-disconnect tunnel interface removed: **yes**
- Leaks: **manual review required** (`egress_cloudflare_trace.txt`, route/firewall excerpts, post_disconnect bundle)

## Baseline vs Post-connect

| Signal | Baseline | Post-connect |
|---|---|---|
| Default route | `n/a` | `n/a` |
| Routing mode | `n/a` | `no_tunnel_routing_detected` |
| `ip route get 1.1.1.1` iface | `n/a` | `n/a` |
| Egress IP (ipify) | `n/a` | `n/a` |
| DNS resolver (primary) | `n/a` | `n/a` |
| DNS query validation | `unknown` | `unknown` |

## Post-disconnect Snapshot

- Default route: ``
- `ip route get 1.1.1.1` iface: ``
- Egress IP (ipify): ``

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
- `connect_cmd_exit_status.txt`
- `disconnect_cmd_exit_status.txt`
