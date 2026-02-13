# Benchmarking Guide

SecureWave benchmark harnesses live in `sandbox/benchmark/`.

## Harnesses
- `ping_latency.py`: RTT sampling per region (Barbados + Frankfurt defaults).
- `jitter_packet_loss.py`: Packet loss and jitter extraction from ping probes.
- `handshake_performance.py`: Repeated `/api/vpn/profile` timing.
- `throughput_test.py`: `iperf3` benchmark if available, synthetic fallback otherwise.
- `competitor_probe.py`: Optional normalized comparison against competitor endpoints.

## Run Complete Benchmark Suite
```bash
bash sandbox/benchmark/run_benchmarks.sh
```

Artifacts:
- `artifacts/benchmark/latency_distribution.csv`
- `artifacts/benchmark/packet_loss.csv`
- `artifacts/benchmark/handshake_times.csv`
- `artifacts/benchmark/throughput_summary.csv`
- `artifacts/benchmark/benchmark_report.md`
- `artifacts/benchmark/benchmark_report.html`
- `artifacts/benchmark/benchmark_violations.json` (threshold gate output)

## Optional Competitor Probe
Set endpoints with:
```bash
export BENCHMARK_COMPETITOR_ENDPOINTS="privado=198.51.100.10,othervpn=198.51.100.20"
```

## Optional iperf3 Mode
```bash
export BENCHMARK_ALLOW_IPERF=true
export BENCHMARK_IPERF_HOST=203.0.113.50
bash sandbox/benchmark/run_benchmarks.sh
```

## Threshold Gating
Thresholds are defined in `benchmarks/thresholds.json` and enforced by the benchmark suite runner in strict mode.

See:
- `docs/benchmarks_thresholds.md`
- `docs/thresholds_and_gating.md`
