# Leak/Kill-Switch Thresholds

Leak thresholds are configured in `leak/leak_thresholds.json` and enforced by `sandbox/leak_tests/enforce_thresholds.py`.

The leak suite runner `sandbox/leak_tests/run_leak_tests.sh` executes the harnesses, writes summaries, then runs the enforcer. In `--strict` mode, the suite fails if any threshold is violated.

## Threshold Keys

File: `leak/leak_thresholds.json`

- `max_dns_leak_score`
  - Observed metric: `dns_leak_score`
  - Source: `artifacts/leak_tests/dns_leak_result.json`
  - Definition:
    - `dns_leak_score` is the count of observed resolvers that are not in `expected_dns`.
    - Private/loopback/link-local resolvers are ignored by default (CI often uses `127.0.0.53`).
  - Comparator: `<=`

- `ipv6_block_miss_tolerance`
  - Observed metric: `ipv6_block_misses`
  - Source: `artifacts/leak_tests/ipv6_leak_result.json`
  - Comparator: `<=`

- `min_kill_switch_enforcement_score`
  - Observed metric: `kill_switch_enforcement_score`
  - Source: `artifacts/leak_tests/interface_flap_result.json`
  - Comparator: `>=`
  - Definition:
    - `100` when down/up behavior is fully enforced
    - `50` when tunnel-down is blocked but tunnel-up is not validated
    - `0` when enforcement fails

## Strict Mode Enforcement

Run:
```bash
bash sandbox/leak_tests/run_leak_tests.sh --strict
```

Outputs:
- `artifacts/leak_tests/leak_violations.json`

Example violation payload:
- `docs/examples/leak_violations.example.json`

## CI Notes (Safe Mode vs Strict-Live)

CI runs leak harnesses in safe mode for determinism. When `wg0` is not present, the enforcer emits warnings like:
- `ipv6_unmeasured_interface_missing`
- `kill_switch_unmeasured_interface_missing`

These warnings appear in the master report, but do not fail thresholds by themselves.

For real leak enforcement on staging:
- Use `--strict-live` flags in the harnesses to require a live tunnel.
- Use `--execute` (root) only where interface flapping is required.

Example:
```bash
sudo python sandbox/leak_tests/interface_flap_test.py --execute --strict-live --interface wg0 --output-dir artifacts/leak_tests
python sandbox/leak_tests/enforce_thresholds.py --strict \
  --leak-dir artifacts/leak_tests \
  --thresholds leak/leak_thresholds.json \
  --output artifacts/leak_tests/leak_violations.json
```

