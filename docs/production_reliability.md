# Production Reliability Engineering

This document covers the production reliability layer added to SecureWave:
- Tunnel self-healing watchdog
- Barbados/EU server recommendation
- IP pool pressure simulator
- System leak audits (memory/FD/threads)
- Hetzner hard cost guardrails

All configuration uses environment variables (no secrets are committed).

## 1) Tunnel Self-Healing Watchdog

**Purpose:** Detect and remediate “stuck” or unhealthy tunnel states without creating retry storms.

**Signals monitored:**
- Handshake staleness from the DB (`WireGuardPeer.last_handshake_at`)
- Interface health (best-effort remote `wg show` health check)
- “Stuck” state: aggregate RX/TX transfer not progressing for multiple cycles while handshakes are stale

**Remediation:**
- Best-effort restart of the WireGuard interface on the node (SSH only)
- Exponential backoff + jitter
- Bounded actions per server per time window (prevents retry storms)

**Events (structured artifacts):**
- JSONL file: `artifacts/watchdog/watchdog_events.jsonl`
- Event types include: `watchdog_start`, `watchdog_action_attempt`, `watchdog_action_result`, `watchdog_action_suppressed`, `watchdog_stop`

**Environment variables:**
- `SECUREWAVE_WATCHDOG_ENABLED` (default: true)
- `SECUREWAVE_WATCHDOG_INTERVAL_SECONDS` (min: 5, default: 20)
- `SECUREWAVE_WATCHDOG_INTERFACE` (default: `wg0`)
- `WG_HANDSHAKE_DEGRADED_SECONDS` (default: 120)
- `WG_HANDSHAKE_UNSTABLE_SECONDS` (default: 300)
- `SECUREWAVE_WATCHDOG_ACTION_WINDOW_SECONDS` (default: 600)
- `SECUREWAVE_WATCHDOG_MAX_ACTIONS_PER_WINDOW` (default: 3)
- `SECUREWAVE_WATCHDOG_BACKOFF_BASE_SECONDS` (default: 10)
- `SECUREWAVE_WATCHDOG_BACKOFF_MAX_SECONDS` (default: 300)
- `SECUREWAVE_WATCHDOG_JITTER_FRACTION` (default: 0.25)
- `SECUREWAVE_WATCHDOG_STUCK_CYCLES` (default: 3)
- `SECUREWAVE_WATCHDOG_EVENTS_PATH` (default: `artifacts/watchdog/watchdog_events.jsonl`)

**How to run (local smoke):**
```bash
.venv/bin/python dev_tools/sandbox/watchdog/run_watchdog_smoke.py
```

## 2) Barbados/EU Routing Optimization (Recommended Server)

**Endpoint:**
- `GET /api/vpn/recommended-server`

**Inputs used in scoring:**
- Geo latency baselines from `geo_latency_probe` output (if present)
- Rolling RTT history (p95) from the DB
- Server load (`current_connections / max_connections`)
- Health status and recent failures

**Geo baselines source:**
- `SECUREWAVE_GEO_LATENCY_REPORT_PATH` (default: `artifacts/live_validation/geo_latency_report.json`)
- Fallback env baselines if report is missing:
  - `BARBADOS_BASELINE_MS` (default: 95.0)
  - `EUROPE_BASELINE_MS` or `FRANKFURT_BASELINE_MS` (default: 130.0)

**Rolling RTT history:**
- Table: `vpn_server_rtt_samples`
- Scoring uses p95 when sample count meets `SECUREWAVE_GEO_RECO_RTT_MIN_SAMPLES`
- Config:
  - `SECUREWAVE_GEO_RECO_RTT_WINDOW_SECONDS` (default: 900)
  - `SECUREWAVE_GEO_RECO_RTT_MIN_SAMPLES` (default: 5)

**Artifacts (optional):**
- Set `SECUREWAVE_GEO_RECO_WRITE_ARTIFACTS=true` to emit:
  - `recommended_server.json`
  - `candidates.csv`
  under `artifacts/geo_reco/<hint>/`

**How to generate artifacts (offline harness):**
```bash
.venv/bin/python dev_tools/sandbox/geo_reco/run_geo_reco.py --output-dir artifacts/geo_reco
```

## 3) IP Pool Pressure Simulator

**Purpose:** Simulate 500 peers with churn, reclaim, and partial exhaustion to validate pool behavior.

**How to run:**
```bash
.venv/bin/python dev_tools/sandbox/ip_pool_pressure/run_ip_pool_pressure.py --output-dir artifacts/ip_pool_pressure
```

**Outputs:**
- `artifacts/ip_pool_pressure/report.json`
- `artifacts/ip_pool_pressure/summary.csv`

## 4) Memory + FD Leak Audits

**Endpoints:**
- `GET /api/metrics/system` (JSON, requires auth)
- `GET /metrics` (Prometheus text format, public)

**Leak-oriented fields tracked:**
- RSS (process memory)
- open file descriptors
- threads
- WireGuard processes
- zombie processes
- “zombie peers” (DB peers that are inactive but not revoked)

**Local snapshot (no sockets required):**
```bash
.venv/bin/python dev_tools/sandbox/system_audit/run_local_system_audit.py
```

Writes:
- `artifacts/system_audit/local_prometheus_metrics.txt`
- `artifacts/system_audit/local_metrics_system.json`
- `artifacts/system_audit/local_system_audit_report.json`

**Live snapshot (HTTP probe):**
```bash
.venv/bin/python dev_tools/sandbox/system_audit/system_audit_probe.py \
  --api-base-url "$LIVE_API_BASE_URL" \
  --output-dir artifacts/system_audit \
  --label "snapshot"
```

## 5) Hetzner Hard Cost Guardrails

**Strict policy:**
- Single server only (`node_count=1`, `allow_scale=false`)
- Server type restricted to `cx23` or `cx33`
- Backups forbidden and must be explicitly disabled (`backups=false`)
- No paid add-ons: Hetzner Terraform resources are allowlisted

**Guard script (terraform optional):**
```bash
bash scripts/check_cost_guardrails.sh infra/hetzner/terraform.tfvars
```

**Release wrapper:**
- `scripts/release_hetzner.sh` enforces the single-server + type policy and calls the guard script.
- “Monthly cap” is enforced via `HETZNER_MONTHLY_INSTANCE_CAP` plus the hard single-server restriction.
- Teardown is always available via `destroy` (gated by explicit env confirmations).

## Live Validation (Env-Gated)

Both scripts require a reachable backend:
- `LIVE_API_BASE_URL` (required)

Commands:
```bash
bash dev_tools/sandbox/live_validation/run_live_validation.sh --strict --linux --users 3
bash dev_tools/sandbox/live_validation/run_live_stress_tests.sh --strict --linux --workers 4 --cycles 5
```
