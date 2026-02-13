# Chaos Thresholds

Chaos thresholds are configured in `dev_tools/chaos/chaos_thresholds.json` and enforced by `dev_tools/sandbox/chaos_tests/enforce_thresholds.py`.

The chaos suite runner `dev_tools/sandbox/chaos_tests/run_chaos_suite.sh` executes the harnesses, writes summaries, then runs the enforcer. In `--strict` mode, the suite fails if any threshold is violated.

## Threshold Keys

File: `dev_tools/chaos/chaos_thresholds.json`

- `max_wireguard_recovery_time_ms`
  - Observed metric: `wireguard_recovery_time_ms`
  - Source: `artifacts/chaos_tests/network_drop_result.json` (`metrics.recovery_time_ms`)
  - Comparator: `<=`
  - Notes:
    - In CI, `network_drop.py` runs in safe mode, so recovery timing may be unmeasured and the enforcer emits a warning.
    - For real measurements, run destructive mode on staging (root + `wg0` present).

- `allowed_jwt_replay_failures`
  - Observed metric: `jwt_replay_failures`
  - Source: `artifacts/chaos_tests/jwt_replay_attack_result.json` (`metrics.replay_blocked`)
  - Comparator: `<=`
  - Definition:
    - `0` if replay is blocked, otherwise `1`.

- `max_db_outage_recovery_seconds`
  - Observed metric: `db_outage_recovery_seconds`
  - Source: `artifacts/chaos_tests/db_disconnect_result.json` (`steps[].name == recovery_probe` duration)
  - Comparator: `<=`

## Strict Mode Enforcement

Run:
```bash
bash dev_tools/sandbox/chaos_tests/run_chaos_suite.sh --strict
```

Outputs:
- `artifacts/chaos_tests/chaos_violations.json`

Example violation payload:
- `docs/examples/chaos_violations.example.json`

## Measuring WireGuard Recovery On Staging (Destructive)

`network_drop.py` supports `--execute` and captures recovery timing once the interface returns to an operational state.

Example (run on a staging host only):
```bash
sudo python dev_tools/sandbox/chaos_tests/network_drop.py --execute --interface wg0 --output-dir artifacts/chaos_tests
python dev_tools/sandbox/chaos_tests/enforce_thresholds.py --strict \
  --chaos-dir artifacts/chaos_tests \
  --thresholds dev_tools/chaos/chaos_thresholds.json \
  --output artifacts/chaos_tests/chaos_violations.json
```

Safety:
- `network_drop.py --execute` snapshots iptables rules (when possible) and restores them after fault injection.
- Still expect transient network disruption; do not run on a production control plane.
