# Live Validation Multi-Protocol Suite

This suite generates evidence-based multi-protocol validation artifacts.

## Outputs

Timestamped artifacts are written to:

- `artifacts/live_validation_multi_protocol/YYYYMMDD_HHMMSS/`

Required files:

- `FINAL_MULTI_PROTOCOL_VALIDATION_REPORT.md`
- `protocol_matrix.csv`
- `dns_leak_results.csv`
- `kill_switch_results.csv`
- `handshake_latency.csv`
- `throughput_summary.csv`
- `raw_logs/`

## Run Modes

### Non-invasive (default; CI-safe)

```bash
bash sandbox/live_validation_multi_protocol/run_suite.sh
```

### Live API checks (env-gated)

```bash
export LIVE_MULTI_PROTOCOL_ENABLE_LIVE=true
export LIVE_API_BASE_URL="https://your-securewave-host"
bash sandbox/live_validation_multi_protocol/run_suite.sh
```

### Optional data-plane checks

Provide connect/disconnect command templates:

- `LIVE_MULTI_WG_CONNECT_CMD`
- `LIVE_MULTI_WG_DISCONNECT_CMD`
- `LIVE_MULTI_OVPN_CONNECT_CMD`
- `LIVE_MULTI_OVPN_DISCONNECT_CMD`
- `LIVE_MULTI_IKEV2_CONNECT_CMD`
- `LIVE_MULTI_IKEV2_DISCONNECT_CMD`

Then run:

```bash
export LIVE_MULTI_PROTOCOL_ENABLE_DATA_PLANE=true
bash sandbox/live_validation_multi_protocol/run_suite.sh
```

## Barbados/Europe Focus

Regional baseline targets are configured in:

- `sandbox/live_validation_multi_protocol/region_targets.json`

