# SecureWave Linux Enterprise VPN Certification

Generated: `2026-07-05T14:52:09+00:00`
Mode: `safe_local_test_database`

## Executive Summary

- Local enterprise simulation: `PASS`
- Live runtime proofs: `True`
- Overall: `ready_for_modeled_local_scale`

## Enterprise Scale Readiness

| Cohort | Status | Users Completed | Duration s | Login p95 ms | WG profile p99 ms | Errors |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| 100 | pass | 100 | 21.962 | 420.15 | 447.67 | 0 |
| 250 | pass | 250 | 55.75 | 382.0 | 440.49 | 0 |
| 500 | pass | 500 | 135.117 | 497.93 | 532.12 | 0 |
| 1000 | pass | 1000 | 314.246 | 602.96 | 562.92 | 0 |

## Protocol Readiness

| Protocol | Backend Profile Scale | Live Runtime Proof |
| --- | --- | --- |
| wireguard | True | pass |
| openvpn | True | pass |
| ikev2 | True | pass |

## Safety Notes

- Default execution uses a temporary SQLite database with `TESTING=true`.
- No production users, payment data, VPN private keys, tokens, profile configs, or CA material are written to artifacts.
- Live tunnel proofs require explicit `--include-live-proofs`.
- External load testing is intentionally not automatic; use only against authorized SecureWave-owned infrastructure.

## Blockers

- None for the safe local certification mode.
