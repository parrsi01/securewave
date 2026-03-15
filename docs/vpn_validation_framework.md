# SecureWave VPN Validation Framework

## Overview

The validation framework lives in `dev_tools/sandbox/live_validation/` and provides automated tests for VPN tunnel integrity, leak detection, failover behavior, and server selection.

All modules can run standalone or be invoked from the main harness (`live_e2e_validate.py`) via opt-in flags.

## Test Modules

| Module | File | What it tests | Requires root | Requires tunnel |
|--------|------|---------------|:-------------:|:---------------:|
| E2E Tunnel | `live_e2e_validate.py` | Auth, profile, handshake, routing, DNS, throughput | Yes | Creates its own |
| DNS Leak | `dns_leak_test.py` | Resolver config, DNS route path, dig query verification | No | Yes |
| Packet Leak | `packet_leak_test.py` | tcpdump-based egress leak detection on non-VPN interfaces | Yes | Yes |
| IPv6 Leak | `ipv6_leak_test.py` | IPv6 address exposure, route validation, sysctl kill-switch | No | Yes |
| WebRTC Leak | `webrtc_leak_test.py` | ICE candidate IP exposure via STUN/Playwright | No | Yes |
| Failover | `failover_test.py` | Server failover after endpoint block (iptables) | Yes (execute mode) | Yes |
| Server Selection | `server_selection_test.py` | Latency-based auto server selection validation | No | No |
| DPI Resistance | `dpi_resistance_test.py` | WireGuard fingerprint, port block, UDP throttle, traffic entropy | Yes (execute mode) | Yes |
| Network Chaos | `network_failure_cases.py` | Backend unreachable, gateway reset, DNS unresponsive | Yes (execute mode) | Yes |

## Standalone Usage

### DNS Leak Test

```bash
python dev_tools/sandbox/live_validation/dns_leak_test.py \
  --interface wg0 \
  --expected-dns "94.140.14.14,94.140.15.15"
```

### IPv6 Leak Test

```bash
python dev_tools/sandbox/live_validation/ipv6_leak_test.py \
  --interface wg0
```

### Packet Leak Test

```bash
sudo python dev_tools/sandbox/live_validation/packet_leak_test.py \
  --interface wg0
```

### WebRTC Leak Test

```bash
python dev_tools/sandbox/live_validation/webrtc_leak_test.py \
  --interface wg0 \
  --vpn-exit-ip 138.199.204.139
```

### Failover Test

```bash
# Simulation mode (no iptables changes)
python dev_tools/sandbox/live_validation/failover_test.py \
  --interface wg0

# Execute mode (requires root, blocks endpoint)
sudo python dev_tools/sandbox/live_validation/failover_test.py \
  --interface wg0 --execute
```

### Server Selection Test

```bash
python dev_tools/sandbox/live_validation/server_selection_test.py \
  --api-base-url https://138.199.204.139 \
  --access-token "$TOKEN" \
  --tolerance-ms 20
```

### DPI Resistance Test

```bash
# Simulation mode (no tcpdump/tc/iptables)
python dev_tools/sandbox/live_validation/dpi_resistance_test.py \
  --interface wg0

# Execute mode (requires root)
sudo python dev_tools/sandbox/live_validation/dpi_resistance_test.py \
  --interface wg0 --execute
```

## Integrated Harness Usage

Run all tests via the main harness with opt-in flags:

```bash
sudo python dev_tools/sandbox/live_validation/live_e2e_validate.py \
  --api-base-url https://138.199.204.139 \
  --users 1 \
  --strict \
  --dns-leak-test \
  --packet-leak-test \
  --ipv6-leak-test \
  --webrtc-leak-test \
  --failover-test \
  --server-selection-test \
  --dpi-resistance-test
```

### Environment Variables

Each flag has a corresponding env var for CI:

| Flag | Env Var |
|------|---------|
| `--dns-leak-test` | `LIVE_DNS_LEAK_TEST=true` |
| `--packet-leak-test` | `LIVE_PACKET_LEAK_TEST=true` |
| `--ipv6-leak-test` | `LIVE_IPV6_LEAK_TEST=true` |
| `--webrtc-leak-test` | `LIVE_WEBRTC_LEAK_TEST=true` |
| `--failover-test` | `LIVE_FAILOVER_TEST=true` |
| `--server-selection-test` | `LIVE_SERVER_SELECTION_TEST=true` |
| `--dpi-resistance-test` | `LIVE_DPI_TEST=true` |

## CI-Safe Unit Tests

All detection logic has offline unit tests in `tests/live_network/`:

| Test File | Module | Tests |
|-----------|--------|------:|
| `test_dns_leak_validation.py` | DNS Leak | 22 |
| `test_packet_leak_parser.py` | Packet Leak | 4 |
| `test_ipv6_leak_logic.py` | IPv6 Leak | 11 |
| `test_webrtc_parser.py` | WebRTC Leak | 17 |
| `test_failover_state_machine.py` | Failover | 13 |
| `test_server_selection_logic.py` | Server Selection | 12 |
| `test_dpi_resistance_logic.py` | DPI Resistance | 27 |
| `test_live_validation_common.py` | Common utils | 4 |
| `test_network_failure_cases.py` | Network Chaos | 3 |
| `test_live_reporting.py` | Reporting | 2 |

Run all:

```bash
python -m pytest tests/live_network/ -v
```

## Output Format

Each module produces a structured JSON report:

```json
{
  "test_name": "dns_leak_detection",
  "started_at": "2026-03-13T12:00:00+00:00",
  "finished_at": "2026-03-13T12:00:05+00:00",
  "verdict": "PASS",
  "leak_detected": false,
  "failures": []
}
```

Reports are written to `artifacts/` subdirectories when `--output-dir` is specified.

## Staging Run Instructions

1. Deploy SecureWave backend to staging VPS.
2. Ensure WireGuard is running on the VPS (`wg show`).
3. Set environment:
   ```bash
   export LIVE_API_BASE_URL=https://<staging-ip>
   export LIVE_VALIDATION_PASSWORD=<test-password>
   ```
4. Run validation with root:
   ```bash
   sudo -E python dev_tools/sandbox/live_validation/live_e2e_validate.py \
     --users 1 --strict \
     --dns-leak-test --ipv6-leak-test --webrtc-leak-test
   ```
5. Check `artifacts/live_validation/live_e2e_result.json` for results.

## Architecture

```
dev_tools/sandbox/live_validation/
  common.py                  -- Shared utilities (run_command, HTTP, WG config parsing)
  live_e2e_validate.py       -- Main orchestrator (auth → profile → tunnel → probes)
  dns_leak_test.py           -- DNS resolver + route + query leak detection
  packet_leak_test.py        -- tcpdump-based non-VPN egress leak detection
  ipv6_leak_test.py          -- IPv6 address + route leak detection
  webrtc_leak_test.py        -- WebRTC ICE candidate leak detection (STUN/Playwright)
  failover_test.py           -- Multi-server failover via iptables endpoint block
  server_selection_test.py   -- Latency-based server selection validation
  dpi_resistance_test.py     -- DPI fingerprint, port block, throttle, traffic entropy
  network_failure_cases.py   -- Network chaos injection scenarios
  reporting.py               -- Readiness report generation
  geo_latency_probe.py       -- Geographic latency measurement
  live_stress_runner.py      -- Stress/load testing
```
