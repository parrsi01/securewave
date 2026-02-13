# Leak Validation Guide

SecureWave leak and kill-switch checks are located in `sandbox/leak_tests/`.

## Harnesses
- `dns_leak_test.py`: Validates resolver usage against expected DNS list.
- `ipv6_leak_test.py`: Detects IPv6 default-route leakage or disabled-state.
- `route_table_test.py`: Ensures default route integrity via WireGuard interface.
- `interface_flap_test.py`: Simulates interface down/up and validates kill-switch behavior.

## Run Full Leak Suite
```bash
bash sandbox/leak_tests/run_leak_tests.sh
```

Artifacts:
- `artifacts/leak_tests/leak_summary.json`
- `artifacts/leak_tests/leak_summary.md`
- Per-harness JSON/MD/HTML summaries.

## Strict Live Validation
Use `--strict-live` to fail when a live tunnel is absent:
```bash
python sandbox/leak_tests/dns_leak_test.py --strict-live --interface wg0
```

For real interface flapping (root required):
```bash
sudo python sandbox/leak_tests/interface_flap_test.py --execute --strict-live --interface wg0
```

## CI Behavior
CI uses safe mode for deterministic checks and executes pytest leak logic tests to validate leak classification behavior.

## Threshold Gating
Leak thresholds are defined in `leak/leak_thresholds.json` and enforced by the leak suite runner in strict mode.

See:
- `docs/leak_thresholds.md`
- `docs/thresholds_and_gating.md`
