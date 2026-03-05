# Integration Stall Report

## Summary
The integration suite does not deadlock in current runs; it appears stalled because `pytest -q` emits no progress while several tests take 60–140 seconds. Adding deterministic timestamps and a timeout wrapper makes long-running phases visible and ensures the suite cannot hang indefinitely without a stack trace.

## Environment
- OS: Ubuntu 24.04.4 LTS (kernel 6.8.0-101-generic, aarch64)
- Python: 3.12.3
- pytest: 8.2.2
- Plugins: anyio 4.12.0, asyncio 0.24.0, cov 6.0.0
- pytest-timeout: not installed

## Reproduction Commands
Baseline (previously “silent”):
- `.venv/bin/pytest tests/integration -q`

Deterministic runner:
- `tools/run_integration_with_timeouts.sh`

Stack dump on demand:
- `tools/py_stackdump.py --pid <pytest_pid> --asyncio`

## Evidence of “Stall” Symptoms
With progress timestamps enabled, the suite shows long gaps with no output, which previously appeared as a stall:
- `test_peer_lifecycle_create_reassign_rotate` start at `20:08:03Z`, next output at `20:10:22Z` (~2m19s).
- `test_openvpn_profile_returns_ovpn_and_certificate_metadata` start at `20:18:18Z`, next output at `20:19:30Z` (~72s).

These are long-running tests, not deadlocks.

## Root Cause Analysis
1. **Silent progress**: `pytest -q` provides no per-test output. Long tests create multi-minute periods of silence that look like hangs.
2. **No global timeout**: Without `pytest-timeout` or an external watchdog, an actual hang would be indistinguishable from a long test run.

No reproducible deadlock was found in the current environment; the “hang” was a lack of progress visibility.

## Minimal Fix Implemented
1. **Timestamped progress in tests**:
   - Added collection and per-test start timestamps for integration tests only.
   - Registered `faulthandler` SIGUSR1 dumps and a best-effort asyncio task dump on SIGUSR2.
2. **Deterministic timeout wrapper**:
   - Added `tools/run_integration_with_timeouts.sh` to run pytest with `-vv -s --maxfail=1`.
   - Uses GNU `timeout` to send SIGUSR1 and terminate after a fixed window.
   - Includes a Python fallback watchdog when `timeout` is unavailable.
3. **Stack dump helper**:
   - Added `tools/py_stackdump.py` to trigger SIGUSR1/SIGUSR2 on demand.

All changes are test-only tooling and diagnostics. No product behavior changed.

## Verification
Suite completed deterministically with visible progress:
- `tools/run_integration_with_timeouts.sh` → **130 passed** in ~6m23s
- `.venv/bin/pytest tests/integration -q` → **130 passed** in ~6m22s
- `.venv/bin/pytest tests/integration -q` (second run) → **130 passed** in ~6m23s
- `.venv/bin/pytest tests/integration/test_vpn_profile.py -q` → **12 passed** in ~1m32s
- `.venv/bin/pytest tests/integration/test_vpn_credentials.py -q` → **2 passed** in ~32s

## Change Log
1. what changed
   - Added integration progress timestamps and SIGUSR1/SIGUSR2 dump hooks for test runs.
   - Added deterministic integration runner and stack dump helper scripts.
2. what was reused
   - Existing pytest fixtures and `InProcessTestClient`.
   - Existing integration test suite and environment flags.
3. what was intentionally left untouched
   - Application runtime behavior, API contracts, database schema, and production code paths.
4. risks introduced
   - Slightly noisier pytest output for integration tests.
   - Signal handlers are test-only; no production impact.
