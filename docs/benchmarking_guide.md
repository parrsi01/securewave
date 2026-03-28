# Benchmarking Guide

SecureWave benchmark harnesses live in `dev_tools/sandbox/benchmark/`.

## Harnesses
- `ping_latency.py`: RTT sampling per region (Barbados + Frankfurt defaults).
- `jitter_packet_loss.py`: Packet loss and jitter extraction from ping probes.
- `handshake_performance.py`: Repeated `/api/vpn/profile` timing.
- `throughput_test.py`: `iperf3` benchmark if available, synthetic fallback otherwise.
- `live_protocol_benchmark.py`: Honest per-protocol benchmark for the current host, with website JSON publishing.
- `competitor_probe.py`: Optional normalized comparison against competitor endpoints.

## Run Complete Benchmark Suite
```bash
bash dev_tools/sandbox/benchmark/run_benchmarks.sh
```

## Run Live Protocol Benchmarks For The Current Host
```bash
python3 dev_tools/sandbox/benchmark/live_protocol_benchmark.py \
  --publish-path static/data/performance_benchmarks.json
```

Optional upload benchmarking requires an iperf3 target:

```bash
export BENCHMARK_IPERF_HOST=203.0.113.50
python3 dev_tools/sandbox/benchmark/live_protocol_benchmark.py
```

If a protocol path is missing or broken, the output marks it `fail` or `unavailable` rather than inventing a score.

Artifacts:
- `artifacts/benchmark/latency_distribution.csv`
- `artifacts/benchmark/packet_loss.csv`
- `artifacts/benchmark/handshake_times.csv`
- `artifacts/benchmark/throughput_summary.csv`
- `artifacts/benchmark/benchmark_report.md`
- `artifacts/benchmark/benchmark_report.html`
- `artifacts/benchmark/benchmark_violations.json` (threshold gate output)
- `artifacts/protocol_benchmarks/<timestamp>/protocol_speed_results.json`
- `static/data/performance_benchmarks.json`

## Optional Competitor Probe
Set endpoints with:
```bash
export BENCHMARK_COMPETITOR_ENDPOINTS="privado=198.51.100.10,othervpn=198.51.100.20"
```

## Optional iperf3 Mode
```bash
export BENCHMARK_ALLOW_IPERF=true
export BENCHMARK_IPERF_HOST=203.0.113.50
bash dev_tools/sandbox/benchmark/run_benchmarks.sh
```

## Threshold Gating
Thresholds are defined in `dev_tools/benchmarks/thresholds.json` and enforced by the benchmark suite runner in strict mode.

See:
- `docs/benchmarks_thresholds.md`
- `docs/thresholds_and_gating.md`
