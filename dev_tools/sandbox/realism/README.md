# Realism Sandbox

This folder contains end-to-end "realistic" simulations that exercise SecureWave flows
without requiring external cloud traffic.

Primary entrypoint:

- `dev_tools/sandbox/realism/run_full_simulation.sh`

What it does (outputs under `artifacts/sim_tests/<ts>/`):
- Fake user signup + login
- Device registration
- VPN profile fetch (WireGuard config structure validation)
- Website page flows (non-VPN control plane)
- Python compile checks + pytest
- Flutter analyze + flutter test

Notes:
- Other cloud providers are intentionally not used or referenced.
- "Real mode" validation is structure-only (no live tunnel, no remote peer registration).
