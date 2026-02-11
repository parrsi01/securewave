# Full Simulation Report (Non-Azure)

Run date: 2026-02-11

## Run Metadata

- Suite: `sandbox/realism/run_full_simulation.sh`
- Artifacts: `artifacts/sim_tests/20260211_021246/`
- Branch: `release/v1.0.0-non-apple-freeze`
- Commit: `cad5fab`

## What Was Exercised

- Python:
  - `python -m compileall` (services + ml)
  - `pytest -q` (local-only, demo/mock enabled for safety)
  - `pytest -q tests_real` (real-profile structure validation; no live traffic; peer auto-registration disabled)
- Flutter:
  - `flutter analyze`
  - `flutter test`
- Backend + flows:
  - Local uvicorn backend (sqlite)
  - Website page flows
  - API flows: signup, login, device registration, VPN profile fetch, demo connect/status/config/disconnect

## Results

- Status: **PASS**
- Website/API simulation: **25 steps, 0 failed**
  - JSON: `artifacts/sim_tests/20260211_021246/website_simulation.json`
  - Logs: `artifacts/sim_tests/20260211_021246/logs/`

## Notes

- Cloud traffic was intentionally excluded (no Azure, no Hetzner live calls).
- A fake Hetzner server record was seeded for local profile issuance validation (documentation IP `203.0.113.10`).

