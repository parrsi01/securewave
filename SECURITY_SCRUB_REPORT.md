# Security Scrub Report

Date: 2026-02-11

## Scope

- Hard security scrub and cleanup
- Hetzner-only enforcement (other cloud providers unsupported)
- Secret safety (.gitignore, CI scanning, history scan)

## Actions Taken

### Dead Code / Disallowed Provider Removal

- Removed disallowed-provider deployment/config remnants (docs/scripts/docker/infrastructure).
- Removed legacy production server initializer that hardcoded IP/key material:
  - deleted `infrastructure/init_production_server.py`
- Removed legacy disallowed-provider environment template.

### Secret Safety

- Hardened `.gitignore` coverage for:
  - env files (`*.env`, `.env.*`)
  - key/cert material (`*.pem`, `*.key`, `*.p12`, `*.pfx`, `*.jks`)
  - terraform state + vars (`*.tfstate*`, `.terraform/`, `*.tfvars*`, `terraform.tfvars`)
- generated artifacts (`artifacts/**`, with an explicit allowlist for `artifacts/hetzner/DEPLOY_READINESS_REPORT.md`)
- Scrubbed templates to remove disallowed provider references and secret-looking placeholders:
  - `.env.template`
  - `.env.production.example`
- Removed a hard-coded test string that triggered secret scanners:
  - `tests/unit/test_env_validation.py`

### CI Secret Scanning

- Added a Gitleaks scan to CI to detect secrets in the current working tree:
  - `.github/workflows/ci-cd.yml`
- Added repository config for scanner allowlisting of vendored iOS code:
  - `.gitleaks.toml`

### Log Redaction

- The FastAPI logging filter redacts emails, Bearer tokens, and WireGuard key material from logs:
  - `main.py` (`RedactFilter`)

## Git History Secret Scan (Findings)

- Tool: Gitleaks v8.30.0
- Result: **Leaks found in git history (28 findings)**.
- Remediation guidance written (no history rewrite performed):
  - `docs/SECRET_REMEDIATION.md`

## Current State Verification

- Current working tree secret scan (dir scan) passes:
  - `gitleaks dir --redact --no-banner -c .gitleaks.toml .`
- Python tests pass locally (offline):
  - `pytest -q`
