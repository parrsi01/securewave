# SecureWave Linux Enterprise VPN Readiness Matrix

This matrix is the durable review checklist. The generated
`latest/readiness-matrix.json` and `latest/final-report.md` provide the current
run result.

## Protocol Readiness

| Protocol | Backend profile scale | Runtime proof | Residue cleanup | Ready condition |
| --- | --- | --- | --- | --- |
| WireGuard | 100/250/500/1000 users receive app-consumable profiles without duplicate peers or IPs | Hardened live proof shows route, data plane, DNS, backend health, exit-IP movement, counters | No `sw-wg`, table 51820, or policy-rule residue | All columns pass |
| OpenVPN | 100/250/500/1000 users receive app-consumable profiles only when metadata is complete | Hardened live proof shows `tun0`, route, data plane, DNS, backend health, exit-IP movement | No OpenVPN process, pid/log route residue | All columns pass |
| IKEv2 | 100/250/500/1000 users receive app-consumable profiles only when EAP secret and CA metadata exist | Hardened live proof shows NM active, route/DNS, XFRM ESP, data plane, backend health, exit-IP movement | No active SecureWave-IKEv2 VPN, stale SA, table-220 loop route, or unqualified pref-220 rule | All columns pass |

## Enterprise Scale Readiness

| Cohort | Required evidence | Ready condition |
| ---: | --- | --- |
| 100 | local simulation plus API latency/error summary | pass |
| 250 | local simulation plus API latency/error summary | pass |
| 500 | local simulation plus API latency/error summary | pass |
| 1000 | local simulation plus API latency/error summary or authorized external load test | pass |

## User Flow Readiness

| Area | Required evidence |
| --- | --- |
| Account/session | registration, login, account probe, logout, relogin, invalid token rejection |
| Device lifecycle | unique device identity, stale device-id recovery, device-limit enforcement, key rotation |
| Cross-user isolation | another user cannot read device usage/profile state |
| Protocol metadata | selected server support enforced; incomplete metadata fails closed |
| Usage metering | per-session deltas aggregate into current-period plan usage within tolerance |
| Runtime truth | app/proof does not accept false connected states |
| Privacy | generated artifacts are redacted; no tokens/configs/private material |

## Operational Readiness

| Area | Required evidence |
| --- | --- |
| Helper safety | runtime verifier and source guard tests pass; helper allowlist/path validation remains intact |
| Release truth | .deb full-routing requirement and portable UI-only boundaries remain documented/tested |
| Hetzner deploy | `docker compose -f deploy/hetzner/compose.yaml config` passes when Docker is available |
| Fleet audit | read-only Hetzner audit passes when credentials are available |
| Abuse protection | rate-limit tests pass and production mode does not silently enable mock VPN fallback |
