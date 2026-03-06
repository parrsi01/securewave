| Protocol | Negotiation | Egress Proof | PASS/FAIL | Reason |
|---|---|---|---|---|
| openvpn | true | false | FAIL | route_metric_prefers_physical |
| ikev2 | blocked | blocked | FAIL | infra_unreachable_after_openvpn_changes (last known: split_tunnel_routes) |
