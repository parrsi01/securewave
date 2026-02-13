# Thresholds And Gating

SecureWave runs 3 validation suites in CI:
- Chaos (`sandbox/chaos_tests/`)
- Benchmark (`sandbox/benchmark/`)
- Leak/Kill-switch (`sandbox/leak_tests/`)

This phase adds **measurement-based regression gates**. Suites always emit artifacts, and a dedicated threshold enforcer compares measured metrics against versioned JSON thresholds. In **strict mode**, any threshold violation fails the suite and the CI job.

## Files And Artifacts

Threshold configs:
- `benchmarks/thresholds.json`
- `chaos/chaos_thresholds.json`
- `leak/leak_thresholds.json`

Enforcers (compute metrics + compare + emit violations JSON):
- `sandbox/benchmark/enforce_thresholds.py`
- `sandbox/chaos_tests/enforce_thresholds.py`
- `sandbox/leak_tests/enforce_thresholds.py`

Violation outputs (always written; strict controls the exit code):
- `artifacts/benchmark/benchmark_violations.json`
- `artifacts/chaos_tests/chaos_violations.json`
- `artifacts/leak_tests/leak_violations.json`

## Strict Mode Behavior

Run strict suites locally:
```bash
bash sandbox/chaos_tests/run_chaos_suite.sh --strict
bash sandbox/benchmark/run_benchmarks.sh --strict
bash sandbox/leak_tests/run_leak_tests.sh --strict
python scripts/generate_validation_master_report.py
```

Exit codes:
- Enforcers:
  - `0`: no violations
  - `2`: violations present (deploy-blocking in strict mode)
  - `3`: thresholds/config missing or invalid (infra/config error)
- Suite runners return non-zero if any harness fails or if strict enforcement fails.

When strict enforcement fails, suite runners print the corresponding `*_violations.json` as a structured JSON block in logs (GitHub Actions log group).

## CI Gating

Workflows:
- `.github/workflows/test.yml`
- `.github/workflows/ci-cd.yml`

CI runs suites with `--strict` and uploads artifacts with `if: always()` so violations JSONs are preserved even when the job fails.

## Updating Thresholds Safely

1. Run the suite on a known-good baseline (stable network, low server load).
2. Inspect:
   - `artifacts/benchmark/*.csv`
   - `artifacts/*/*_violations.json` (observed metrics)
3. Update the corresponding threshold JSON.
4. Submit a PR and review changes as a **policy update**, not a performance fix.

Rule of thumb:
- Only loosen thresholds when you can explain the environment change (new region, new instance type, new routing).
- Tighten thresholds after multiple stable baseline runs.

## Example CI Failure Logs (Structured)

Example (benchmark regression):
```json
{
  "suite": "benchmark",
  "strict": true,
  "exit_code": 2,
  "violations_path": "artifacts/benchmark/benchmark_violations.json",
  "violation_count": 2,
  "violations": [
    {
      "metric": "p95_latency_ms",
      "observed": 315.2,
      "threshold": 200.0,
      "comparator": "lte",
      "detail": "p95 RTT over all samples exceeded maximum"
    },
    {
      "metric": "throughput_mbps",
      "observed": 8.4,
      "threshold": 25.0,
      "comparator": "gte",
      "detail": "effective throughput fell below minimum"
    }
  ]
}
```

## Common Failure Modes And Resolution Paths

Benchmark violations:
- High `p95_latency_ms`: check server CPU saturation, routing changes, UDP throttling, DNS issues, and regional egress.
- Low `handshake_rate`: check rate-limiting settings, auth failures, DB contention, and `/api/vpn/profile` latency spikes.
- Low `throughput_mbps`: check host networking, MTU regression, and tunnel routing.

Chaos violations:
- High `wireguard_recovery_time_ms`: run `network_drop.py --execute` on staging and verify interface recovery (`recovery_probe`).
- `jwt_replay_failures` > 0: refresh replay is no longer blocked; treat as security regression.
- DB recovery too slow: investigate connection pool, retry logic, and DB readiness.

Leak violations:
- DNS leak score > 0: enforce resolvers on the tunnel profile and verify client DNS settings.
- IPv6 block misses > tolerance: disable IPv6 or enforce IPv6 blackhole rules and verify routing tables.
- Kill-switch score below minimum: verify interface-down behavior (no non-tunnel default routes).

See suite-specific docs:
- `docs/benchmarks_thresholds.md`
- `docs/chaos_thresholds.md`
- `docs/leak_thresholds.md`

