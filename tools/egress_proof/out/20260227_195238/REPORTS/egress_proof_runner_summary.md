# Egress Proof Runner Summary

- VPS host: 138.199.204.139
- Baseline public IP: 92.105.134.148
- Max iterations: 4
- Matrix: tools/egress_proof/out/20260227_195238/final_matrix.md

| Protocol | Negotiation | Egress Proof | PASS/FAIL | Reason |
|---|---|---|---|---|
| openvpn | true | false | FAIL | route_metric_prefers_physical |
| ikev2 | true | false | FAIL | split_tunnel_routes |
