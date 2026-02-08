# CODEX Simulation Report (Non-Azure)

**Run ID:** `20260208_173317`  
**Branch:** `release/v1.0.0-non-apple-freeze`  
**Base URL:** `http://127.0.0.1:18080`  
**Artifacts:** `artifacts/sim_tests/20260208_173317/`

## A) Scope & Assumptions

- Azure subscription is **down** and is **intentionally excluded** from this run.
- All Azure-dependent paths must be skipped/mocked/short-circuited safely (expected).
- Platforms validated in this run: **Android, Windows, Linux, Web** (non-Apple).
- VPN connectivity validation is **logic-level only** (no real tunnels, no server reachability).

## B) What Was Tested

**Backend (Python)**
- `python3 -m compileall services/ ml/ -q` (output: `logs/python_compileall.txt`)
- `.venv/bin/pytest -q` (output: `logs/pytest.txt`, result: **259 passed**)

**Flutter App (Dart)**
- `flutter analyze` (output: `logs/flutter_analyze.txt`, result: **clean**)
- `flutter test` (output: `logs/flutter_test.txt`, result: **all tests passed**)

**Website + API (local `uvicorn` + sqlite)**
- Smoke/simulation script: `sandbox/e2e_simulation/website_simulation.py`
- Pages validated (HTTP 200): `/`, `/home`, `/download`, `/contact`, `/settings`, `/diagnostics`, `/dashboard`
- Auth flows: register, login, `GET /api/auth/me`, logout, and auth-required guard checks
- Account/device center APIs: `GET /api/dashboard/user`, `GET /api/vpn/devices`, `GET /api/vpn/servers`
- VPN logic flows (demo/mock): `POST /api/vpn/connect`, `GET /api/vpn/status`, `GET /api/vpn/config`, `POST /api/vpn/disconnect`
- Contact form submission: `POST /api/contact/submit` (non-SMTP fallback)
- Error handling: custom web 404 + API 404 JSON shape

Evidence:
- Step-by-step results: `website_simulation.json`
- Backend logs: `logs/uvicorn.txt`

## C) What Was Skipped (Azure-Only)

- `securewave-tests` full network leak/throughput suite (DNS/IPv6 leak, throughput, stability, baseline).  
  `# AZURE_SKIPPED: Requires real deployed tunnel endpoints and reachability (production servers are Azure-hosted).`

- Any tests or runs that provision/manage peers via Azure control-plane tooling (Azure CLI / VM Run Command).  
  `# AZURE_SKIPPED: Requires Azure subscription + VM access; intentionally not executed.`

## D) Results Summary

- **PASS**: Non-Azure compile checks, pytest, Flutter analysis/tests, and local website/API simulation all succeeded.
- Output directory contains logs and structured JSON results: `artifacts/sim_tests/20260208_173317/`.

## E) Fixes Applied (Blockers Only)

- `database/session.py`: ensured dev/test auto-table creation includes `wireguard_peers` (and other models) so `/api/vpn/devices` works under sqlite simulation.
- `routers/contact.py`: implemented non-SMTP fallback (accept contact submissions when email is disabled).
- `tests/integration/test_contact.py`: updated expectations to match the non-SMTP fallback behavior.
- `sandbox/e2e_simulation/*`: added non-Azure simulation harness + website/API simulation script.
- `RELEASE_FREEZE.md`: documented Azure exclusion, validated platforms, and rerun instructions.

## F) Risks Remaining

- Real VPN tunnel validation (true DNS/IPv6 leak prevention, throughput, real reconnect behavior) is **not verified** in this run because Azure-backed tunnel infrastructure is unavailable.
- Windows runtime behavior (rapid connect/disconnect on an actual Windows desktop build) is not executed here; only code-level checks and Flutter tests were run.
- Contact form acceptance works without SMTP, but email delivery remains disabled until a provider is configured (expected for Azure-excluded mode).

## G) Human Next Steps

1. When Azure is available again, run `securewave-tests/run_tests.sh` against a real deployment to validate leak protection, throughput, and stability with an actual tunnel.
2. On Windows, perform a manual stress test: repeated connect/disconnect toggles + rapid reconnect sequences to validate no UI stalls and clean state transitions.
3. Configure an email provider (SMTP/SendGrid/SES) and re-run the contact flow to validate delivery (or keep fallback-only in demo environments).

---

## CHANGE LOG

1) What changed
- Added non-Azure simulation harness under `sandbox/e2e_simulation/`.
- Fixed sqlite dev table auto-create coverage for device listing.
- Enabled non-SMTP contact submission fallback.
- Added `RELEASE_FREEZE.md`.

2) What was reused
- Existing pytest suite and Flutter tests.
- Existing demo/mock backend paths (`DEMO_MODE=true`, `WG_MOCK_MODE=true`).

3) What was intentionally untouched
- Azure deployment and infrastructure scripts/config.
- Branding, colors, logos, and UX structure.
- Apple-specific code paths and signing/entitlements.

4) Risks introduced
- NONE identified beyond the explicitly scoped behavior change: contact submissions are accepted when email is disabled (no delivery).

