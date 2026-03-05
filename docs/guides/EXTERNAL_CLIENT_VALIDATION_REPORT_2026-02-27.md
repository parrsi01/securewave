# External Client Validation Report (2026-02-27)

## Scope
Validated OpenVPN and IKEv2 end-to-end dataplane behavior from a separate Hetzner Ubuntu 22.04 client (`securewave-test-client`, `5.223.54.59`) against the SecureWave VPS (`securewave-prod`, `138.199.204.139`).

## Constraint Compliance
- Main VPS routing was not modified for this task.
- Client environment changes were limited to package install and temporary protocol configs.
- Flutter UI and backend business logic were untouched.

## Baseline
- External client public IP before VPN: `5.223.54.59`
- Baseline evidence: `tools/external_client_validation/out/20260227_232749/EVIDENCE/client_baseline.txt`

## Provisioning Finding
The backend provisioning endpoint rejected both protocols with deterministic `409` responses:
- OpenVPN: `openvpn_server_misconfigured`
- IKEv2: `ikev2_server_misconfigured`

Because the live daemons were reachable, validation proceeded by issuing temporary client material directly from the VPS without changing routing.

## OpenVPN Result: PASS
Evidence:
- Client validation: `tools/external_client_validation/out/20260227_232749/EVIDENCE/openvpn_client_validation.txt`
- Server before: `tools/external_client_validation/out/20260227_232749/EVIDENCE/openvpn_server_before.txt`
- Server after: `tools/external_client_validation/out/20260227_232749/EVIDENCE/openvpn_server_after.txt`

Observed:
- `tun0` came up on the external client with `10.9.0.3/24`.
- `ip route get 1.1.1.1` resolved to `via 10.9.0.1 dev tun0 src 10.9.0.3`.
- Public IP changed from `5.223.54.59` to `138.199.204.139`.
- `tcpdump` on client `eth0` showed UDP control traffic to `138.199.204.139:1194`.
- VPS `tun0` counters increased:
  - Before: RX `1560`, TX `304`
  - After: RX `3191`, TX `4856`

Conclusion: OpenVPN is operating as a real full-tunnel external dataplane.

## IKEv2 Result: PASS
Evidence:
- Client validation: `tools/external_client_validation/out/20260227_232749/EVIDENCE/ikev2_client_validation.txt`
- Server before: `tools/external_client_validation/out/20260227_232749/EVIDENCE/ikev2_server_before.txt`
- Server during active session: `tools/external_client_validation/out/20260227_232749/EVIDENCE/ikev2_server_during_active.txt`

Observed:
- IKE_SA and CHILD_SA established successfully.
- Client CHILD_SA: `10.10.0.11/32 === 0.0.0.0/0`.
- `ip route get 1.1.1.1` resolved to `via 172.31.1.1 dev eth0 table 220 src 10.10.0.11`; for policy-based IPsec this is the expected full-tunnel policy route path.
- Public IP changed from `5.223.54.59` to `138.199.204.139`.
- Client `tcpdump` showed IKE on UDP `500/4500` followed by UDP-encapsulated ESP on `4500`.
- VPS active-session counters increased:
  - `securewave-ikev2-eap{3}` bytes_in `112`, bytes_out `60`
  - Server `xfrm state` lifetime counters matched active traffic.

Conclusion: IKEv2 is operating as a real full-tunnel external dataplane.

## Route Summary
- Baseline client default route: `default via 172.31.1.1 dev eth0`
- OpenVPN after connect:
  - `0.0.0.0/1 via 10.9.0.1 dev tun0`
  - `128.0.0.0/1 via 10.9.0.1 dev tun0`
  - explicit host routes kept SSH control path outside the tunnel
- IKEv2 after connect:
  - main default route remained on `eth0`
  - effective default egress enforced by XFRM policies plus route lookup in table `220`

## Final Verdict
- OpenVPN: PASS
- IKEv2: PASS
- Backend provisioning contract for these protocols: still FAIL (`409` misconfiguration), independent of dataplane validity
