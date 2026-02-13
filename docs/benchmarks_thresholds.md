# Benchmark Thresholds

Benchmark thresholds are configured in `dev_tools/benchmarks/thresholds.json` and enforced by `dev_tools/sandbox/benchmark/enforce_thresholds.py`.

The full benchmark suite runner `dev_tools/sandbox/benchmark/run_benchmarks.sh` always generates benchmark artifacts, then runs the enforcer. In `--strict` mode, the suite fails if any threshold is violated.

## Threshold Keys

File: `dev_tools/benchmarks/thresholds.json`

- `max_p95_latency_ms`
  - Observed metric: `p95_latency_ms`
  - Source: `artifacts/benchmark/latency_distribution.csv` (all `latency_ms` samples)
  - Comparator: `<=`

- `max_jitter_ms`
  - Observed metric: `max_jitter_ms`
  - Source: `artifacts/benchmark/packet_loss.csv` (max over `jitter_ms`)
  - Comparator: `<=`

- `max_packet_loss_pct`
  - Observed metric: `max_packet_loss_pct`
  - Source: `artifacts/benchmark/packet_loss.csv` (max over `loss_pct`)
  - Comparator: `<=`

- `min_handshake_rate`
  - Observed metric: `handshake_rate` (`success_count / iterations`)
  - Source: `artifacts/benchmark/handshake_performance_result.json`
  - Comparator: `>=`

- `min_throughput_mbps`
  - Observed metric: `throughput_mbps` (effective throughput)
  - Source: `artifacts/benchmark/throughput_summary.csv`
  - Comparator: `>=`

Note: The effective throughput is computed as:
- `min(max(download_mbps), max(upload_mbps))`

## Strict Mode Enforcement

Run:
```bash
bash dev_tools/sandbox/benchmark/run_benchmarks.sh --strict
```

Outputs:
- `artifacts/benchmark/benchmark_violations.json`

If any threshold is violated, the runner exits non-zero and prints `benchmark_violations.json` to logs (structured JSON).

Example violation payload:
- `docs/examples/benchmark_violations.example.json`

## Updating Thresholds

1. Run:
   - `bash dev_tools/sandbox/benchmark/run_benchmarks.sh`
2. Inspect:
   - `artifacts/benchmark/benchmark_violations.json` (computed metrics)
   - `artifacts/benchmark/*.csv` (raw distributions)
3. Update `dev_tools/benchmarks/thresholds.json` based on a stable baseline.

## CI Notes (ICMP/Simulated Probes)

In some CI environments, ICMP may be blocked. The harnesses degrade gracefully and may emit simulated rows for ping-based measurements. Threshold gates still enforce computed metrics, but you should treat simulated-heavy runs as weaker signals and run the benchmark suite on staging for corridor-grade baselines.
