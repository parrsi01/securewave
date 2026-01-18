# SecureWave VPN Test Suite

Real, objective performance and security testing for VPN connections.

## Overview

This test suite measures actual VPN performance metrics by testing the currently active OS-level VPN tunnel. It does **not** control or configure the VPN—it only measures what's already connected.

## Requirements

### System Tools
- `ping` - Latency measurements
- `curl` - Throughput tests
- `dig` (dnsutils) - DNS leak detection
- `ip` (iproute2) - Interface detection

### Python
- Python 3.6+
- PyYAML (`pip install pyyaml`)

### Optional
- `iperf3` - More accurate throughput testing (if server available)

## Quick Start

```bash
# Run all tests
./run_tests.sh

# Quick test (shorter stability check)
./run_tests.sh --quick

# Output JSON only
./run_tests.sh --json

# Skip baseline (VPN always on)
./run_tests.sh --skip-baseline
```

## What It Tests

### 1. Baseline Measurements
Measures network performance without VPN for comparison:
- Latency to multiple targets
- Jitter (latency variation)
- Packet loss
- Download throughput

### 2. VPN Latency & Jitter
Measures with VPN active:
- Average/min/max latency
- Jitter (connection quality)
- Packet loss rate

### 3. Throughput
Download speed tests:
- Multiple test servers
- Compares to baseline
- Reports % retained through VPN

### 4. DNS Leak Detection
Checks if DNS queries leak outside the VPN:
- Identifies active DNS resolvers
- Detects unexpected resolvers
- Rates severity (none/minor/major/critical)

### 5. IPv6 Leak Detection
Checks if IPv6 traffic bypasses the VPN:
- Tests IPv6 connectivity
- Checks IPv6 routing
- Identifies leak severity

### 6. Ad/Tracker Blocking
Tests VPN's DNS-level blocking:
- Tests known ad domains
- Tests known tracker domains
- Reports blocking effectiveness

### 7. Tunnel Stability
Monitors tunnel over time:
- Tracks drops and reconnections
- Measures uptime percentage
- Reports reconnection times

## Output

### Terminal Output
```
[+] SecureWave VPN Test Suite
==================================================

Baseline latency:        15.23 ms
SecureWave latency:      18.45 ms (+3.2)

Baseline download:       95.4 Mbps
SecureWave download:     82.1 Mbps (86%)

DNS leaks detected:      NO
IPv6 leaks detected:     NO

Ads blocked:             85%
Trackers blocked:        90%

Tunnel drops:            0
Avg reconnect time:      N/A

OVERALL SCORE:           87/100
STATUS:                  PASSED
--------------------------------------------------
Results saved to results/latest.json
```

### JSON Output
Results are saved to `results/latest.json`:

```json
{
  "test_suite": "SecureWave VPN Test Suite",
  "version": "1.0.0",
  "timestamp": "2024-01-18T12:00:00",
  "vpn_detected": true,
  "vpn_interface": "wg0",
  "baseline": { ... },
  "latency": { ... },
  "throughput": { ... },
  "dns_leak": { ... },
  "ipv6_leak": { ... },
  "ad_blocking": { ... },
  "stability": { ... },
  "scoring": {
    "overall_score": 87,
    "status": "PASSED"
  }
}
```

## Configuration

Edit `config.yaml` to customize:
- Test targets (ping hosts, download URLs)
- Scoring weights
- Pass/fail thresholds
- Expected VPN DNS servers

## Scoring

| Test | Weight | Description |
|------|--------|-------------|
| Latency | 25% | Lower increase = better |
| Throughput | 25% | Higher retention = better |
| DNS Leak | 20% | No leak = 100 |
| IPv6 Leak | 10% | No leak = 100 |
| Ad Blocking | 10% | Higher block rate = better |
| Stability | 10% | Higher uptime = better |

**Pass threshold:** 70/100 (configurable)

## Integration

### Python API
```python
from runner import run_all_tests, save_results

# Run tests
results = run_all_tests(
    skip_baseline=False,
    stability_duration=30,
    verbose=True
)

# Save results
save_results(results, output_dir='./results')

# Access results
print(f"Score: {results['scoring']['overall_score']}")
print(f"Status: {results['scoring']['status']}")
```

### FastAPI Integration
See the main SecureWave backend for API endpoints:
- `POST /api/vpn/tests/run` - Run tests
- `GET /api/vpn/tests/latest` - Get latest results

## Important Notes

1. **VPN must be connected at OS level** before running tests
2. **Baseline tests** should ideally run without VPN connected
3. **Results are real** - no mocking or simulation
4. **Some tests require root** for full functionality (IPv6 leak detection)
5. **Network conditions vary** - run multiple times for accurate results

## Troubleshooting

### "No VPN interface detected"
- Ensure VPN is connected at the OS level
- Check that the VPN creates a `wg*`, `tun*`, or similar interface
- Run `ip link show` to see available interfaces

### DNS tests failing
- Install `dnsutils` package: `apt install dnsutils`
- Ensure `dig` command is available

### Low throughput scores
- Test servers may be slow or distant
- Configure closer test servers in `config.yaml`
- Consider using iperf3 for local testing

## License

Part of SecureWave VPN - All rights reserved.
