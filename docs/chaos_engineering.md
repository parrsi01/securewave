# Chaos Engineering Guide

This guide covers SecureWave chaos harnesses under `dev_tools/sandbox/chaos_tests/`.

## Included Harnesses
- `network_drop.py`: Simulates WireGuard process crash, iptables flush, interface down/up, and firewall rule removal.
- `db_disconnect.py`: Verifies service behavior through DB outage and recovery probes.
- `jwt_replay_attack.py`: Validates refresh token replay rejection and access-token revocation enforcement.

## Run Full Chaos Suite
```bash
bash dev_tools/sandbox/chaos_tests/run_chaos_suite.sh
```

Outputs:
- `artifacts/chaos_tests/chaos_summary.json`
- `artifacts/chaos_tests/chaos_summary.md`
- Per-harness JSON/MD/HTML summaries.

## Live/Destructive Mode
`network_drop.py` supports `--execute`, but only applies real destructive actions when run as root.

Example:
```bash
sudo python dev_tools/sandbox/chaos_tests/network_drop.py --execute --interface wg0
```

## CI Behavior
CI runs chaos harnesses in safe mode (non-destructive) and validates result schema + summary artifacts.

## Threshold Gating
Chaos thresholds are defined in `dev_tools/chaos/chaos_thresholds.json` and enforced by the chaos suite runner in strict mode.

See:
- `docs/chaos_thresholds.md`
- `docs/thresholds_and_gating.md`
