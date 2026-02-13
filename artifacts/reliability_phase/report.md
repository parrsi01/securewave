# Reliability Phase Report

Generated: 2026-02-13

## A) What Changed

1) Tunnel self-healing watchdog (backend)
- Added a watchdog loop that monitors handshake staleness, interface disappearance, and “stuck” tunnel states and triggers best-effort remediation with exponential backoff + jitter.
- Structured JSONL watchdog events are emitted to `artifacts/watchdog/watchdog_events.jsonl`.
- Retry storms are prevented via bounded actions per server per time window + backoff suppression.

2) Barbados/EU routing optimization
- Added `GET /api/vpn/recommended-server` to recommend a server using:
  - geo latency probe baselines (if present)
  - rolling RTT history (p95)
  - server load, health, and recent failures
- Persisted rolling RTT samples in `vpn_server_rtt_samples` (DB table) and added a service to compute rollups with retention/cleanup.
- Added an offline harness that produces `artifacts/geo_reco/*`.

3) IP pool pressure simulator
- Added `dev_tools/sandbox/ip_pool_pressure/` to simulate 500 peers with churn + reclaim + forced exhaustion.
- Added artifacts output: `artifacts/ip_pool_pressure/report.json` and `artifacts/ip_pool_pressure/summary.csv`.
- Hardened IP reclaim correctness with a partial unique index so revoked peers can reclaim their IPv4 address safely.

4) Memory + FD leak audits
- Extended runtime metrics to include RSS, open FDs, thread count, WireGuard process count, and zombie process count.
- Added `GET /api/metrics/system` (JSON) and ensured `/metrics` Prometheus output includes the new gauges.
- Added local and live probes to write `artifacts/system_audit/*` during validation/stress runs.

5) Hard cost guardrails (Hetzner)
- Added strict guardrails that fail fast when configuration attempts:
  - more than 1 server (`node_count != 1`)
  - scale enablement (`allow_scale=true`)
  - backups enabled (`backups=true`)
  - server types outside `cx23/cx33`
  - unexpected Hetzner Terraform resource types (allowlist only)
- Guardrails work even without a `terraform` binary (static config checks).
- `scripts/release_hetzner.sh` invokes guardrails and enforces the strict single-server policy.

## B) What Was Reused

- Existing health classification thresholds (`WG_HANDSHAKE_DEGRADED_SECONDS`, `WG_HANDSHAKE_UNSTABLE_SECONDS`) were reused by the watchdog to align behavior with the existing health monitor.
- Existing server load and health signals (`VPNServer` fields) were reused by the geo recommendation scoring.
- Existing Prometheus `/metrics` endpoint was extended (not replaced).

## C) What Was Left Untouched

- Branding/colors/logos (no changes made to branding assets).
- Secrets handling: no secrets were added to the repo; env vars only.
- No traffic-mimicry/impersonation features were introduced.

## D) Risks Introduced + Mitigations

- Risk: watchdog restarts a node unnecessarily.
  - Mitigations: bounded actions per window, exponential backoff + jitter, and suppression events for observability.
- Risk: recommendation scoring chooses a suboptimal server when probe data is sparse.
  - Mitigations: falls back to existing `latency_ms` when rolling RTT p95 is unavailable; health/load/failure penalties reduce bad picks.
- Risk: DB migration for IPv4 uniqueness behavior changes.
  - Mitigations: uses a partial unique index so only non-revoked peers must be unique; tests validate reclaim and exhaustion behavior.
- Risk: new metrics add overhead.
  - Mitigations: sampling is lightweight and cached; Prometheus remains compatible.

## E) How To Run Watchdog + Simulators

Watchdog (local smoke, emits JSONL events):
```bash
.venv/bin/python dev_tools/sandbox/watchdog/run_watchdog_smoke.py
```

Geo recommendation artifacts (offline harness):
```bash
.venv/bin/python dev_tools/sandbox/geo_reco/run_geo_reco.py --output-dir artifacts/geo_reco
```

IP pool pressure simulator:
```bash
.venv/bin/python dev_tools/sandbox/ip_pool_pressure/run_ip_pool_pressure.py --output-dir artifacts/ip_pool_pressure
```

System audit snapshot (local/in-process):
```bash
.venv/bin/python dev_tools/sandbox/system_audit/run_local_system_audit.py
```

Live validation (requires `LIVE_API_BASE_URL`):
```bash
bash dev_tools/sandbox/live_validation/run_live_validation.sh --strict --linux --users 3
bash dev_tools/sandbox/live_validation/run_live_stress_tests.sh --strict --linux --workers 4 --cycles 5
```

## F) Test Results

Mandatory commands executed from repo root:

- `python3 -m compileall . -q`: PASS
- `.venv/bin/pytest -q`: PASS (`319 passed, 3 skipped`)
  - Skips were limited to `tests/preview/*` in this sandbox because TCP sockets are not permitted for preview-stack tests.

Env-gated commands (require `LIVE_API_BASE_URL`):

- `bash dev_tools/sandbox/live_validation/run_live_validation.sh --strict --linux --users 3`: NOT RUN (missing `LIVE_API_BASE_URL`)
- `bash dev_tools/sandbox/live_validation/run_live_stress_tests.sh --strict --linux --workers 4 --cycles 5`: NOT RUN (missing `LIVE_API_BASE_URL`)
