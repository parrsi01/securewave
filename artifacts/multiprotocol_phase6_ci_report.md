# Multiprotocol Phase 6 CI Guardrails Report

Date (UTC): 2026-02-22
Branch: `release/multiprotocol-live-only`

## Scope Completed

1. Added a dedicated CI guardrail script:
   - `scripts/ci_multiprotocol_release_guardrails.sh`
   - Enforces:
     - HTTPS/TLS nginx baseline checks
     - no VPN mock/demo flag patterns in tracked runtime/workflow/test code
     - release manifest versioning/provider consistency
     - release artifact checksum/size validation
     - Hetzner cost guardrail invariants

2. Added a dedicated CI workflow with required jobs:
   - `lint`
   - `tests`
   - `artifact-checksum-validation`
   - `multiprotocol-live-validation` (live mode optional via workflow inputs / repo vars)
   - File: `.github/workflows/multiprotocol-release-guardrails.yml`

3. Hardened live validation suite mock-scan allowlist to avoid false positives from guardrail scripts:
   - `sandbox/live_validation_multi_protocol/run_validation.py`

4. Removed a remaining demo-labeled integration test comment so the new policy is enforceable:
   - `tests/integration/test_vpn_flow.py`

## Guardrails Added

### HTTPS + TLS
- Validates `infra/nginx/securewave_prod.conf`:
  - HTTP -> HTTPS redirect present
  - TLS listener on `443`
  - `ssl_protocols TLSv1.2 TLSv1.3;`
  - HSTS header present
  - no legacy TLS (`TLSv1` / `TLSv1.1`)
- Validates `nginx/securewave_preview.conf` TLS listener + protocol baseline

### No Mock/Demo (VPN runtime path)
- Blocks legacy fake/demo VPN patterns:
  - `DEMO_MODE`
  - `WG_MOCK_MODE`
  - `WG_SIMULATE`
  - `MockVpnService`
  - `mock tunnel`
  - `simulate connect`
  - `fake success`
- Scans tracked code/workflow/test/script paths with explicit allowlist exclusions for validation scanners/guard scripts.

### Release Manifest Versioning
- `VERSION` must match:
  - `artifacts/releases/<VERSION>/version.json`
  - `static/downloads/version.json`
- Provider must be `hetzner`
- Timestamps must be ISO UTC (`YYYY-MM-DDTHH:MM:SSZ`)
- Available artifact filenames must include the normalized version tag (`+` -> `-`)

### Artifact Checksum Validation
- Verifies `artifacts/releases/<VERSION>/checksums.txt` matches manifest SHA256
- Recomputes SHA256 + size for each available artifact in:
  - `artifacts/releases/<VERSION>/`
  - `static/downloads/`
- Ensures published manifest equals release manifest

### Hetzner Cost Guardrails
- Reuses `scripts/check_cost_guardrails.sh`
- Verifies `scripts/release_hetzner.sh` retains:
  - `HETZNER_MONTHLY_INSTANCE_CAP`
  - single-node policy (`node_count == 1`)
  - `allow_scale=false` enforcement
  - invocation of `scripts/check_cost_guardrails.sh`

## CI Workflow Inputs / Flags

Workflow: `.github/workflows/multiprotocol-release-guardrails.yml`

`workflow_dispatch` inputs:
- `enable_live` (`true`/`false`)
- `strict_live` (`true`/`false`)

Repo variable support (live validation job):
- `LIVE_MULTI_PROTOCOL_ENABLE_LIVE`
- `LIVE_MULTI_PROTOCOL_STRICT`
- `LIVE_MULTI_PROTOCOL_API_BASE_URL`

## Local Validation Results (Equivalent Commands)

### Guardrail Lint + Artifact Checks
- Command: `bash scripts/ci_multiprotocol_release_guardrails.sh all`
- Result: **PASS**

### Backend Tests (CI tests job subset)
- Command:
  - `SKIP_INSTALL=true PYTEST_ARGS='tests/unit/test_download_manifest.py tests/unit/test_live_validation_multi_protocol.py tests/security/test_multiprotocol_ci_safety.py -q' bash scripts/run_backend_tests.sh`
- Result: **PASS** (`6 passed`)

### Flutter Tests (CI tests job subset)
- Command:
  - `cd securewave_app && flutter test test/protocol_capability_matrix_test.dart test/protocol_selector_test.dart test/state_machine/protocol_transition_test.dart`
- Result: **PASS**

### Multiprotocol Live Validation (non-invasive / env-gated)
- Command:
  - `LIVE_MULTI_PROTOCOL_ENABLE_LIVE=false LIVE_MULTI_PROTOCOL_STRICT=false bash sandbox/live_validation_multi_protocol/run_suite.sh`
- Result: **PASS (partial evidence mode)**
- Latest run:
  - `artifacts/live_validation_multi_protocol/20260222_011418/`
- Summary:
  - `live_api_enabled=false`
  - `runtime_mock_hits=0`
  - `workflow_mock_hits=0`
  - `dns_failures=0`
  - `kill_switch_failures=0`
  - `error_ux_failures=0`

## Known Constraints
- GitHub Actions itself was not executed from this local environment; results above are local command-equivalent validations.
- Live validation remains evidence-based partial when live API/data-plane env vars are not supplied.
