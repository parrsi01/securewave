# OpenVPN Pass/Fail

- Result: FAIL
- Reason: route_metric_prefers_physical
- Evidence source: EVIDENCE/openvpn_targeted_check/result.env

Key points:
- Handshake succeeds (`openvpn_selftest_connected`).
- Public IP majority resolves to VPS IP (`138.199.204.139`) and differs from baseline.
- Route decision remains physical for probe destinations (`ip route get 1.1.1.1` => `dev eth0`).
- Full deterministic full-tunnel proof criteria not met.
