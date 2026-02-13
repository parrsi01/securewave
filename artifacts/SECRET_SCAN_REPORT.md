# Secret Scan Report

Generated: `2026-02-13T21:20:34.363163+00:00`

## Scope
- Scanned tracked files (`git ls-files`) for common secret patterns (keys/tokens).
- Excluded vendored iOS code (`securewave_app/ios/ThirdParty/`), local venv (`.venv/`), and generated artifacts (`artifacts/`).

## Filename Checks
- Tracked `.env*` files (templates): **4**
  - Files: `.env.example.backend`, `.env.example.flutter`, `.env.production.example`, `.env.template`
- Tracked `.env*` files (actionable): **0**
- Tracked key/cert material files (`.pem`, `.key`, `.p12`, `.pfx`, `.jks`, `.keystore`): **0**

## Content Scan Results (Actionable)
- High severity pattern hits: **0**
- Medium severity pattern hits: **0**

### High Severity Patterns
- None detected.

### Medium Severity Patterns
- None detected.

## Content Scan Results (Allowlisted)
- Allowlisted findings: **2**
- These are expected synthetic fixtures (for redaction/testing) and do not represent real credentials.

- `stripe_test_secret_key`: 1 file(s)
  - `tests/security/test_log_redaction.py` (1 match(es))
- `stripe_webhook_secret`: 1 file(s)
  - `tests/security/test_log_redaction.py` (1 match(es))

## Git Ignore Coverage
- `.gitignore` excludes local env files (`.env`, `.env.*`), key/cert material, terraform state/vars, and generated artifacts.

## Verdict
No high/medium severity secret patterns were detected in tracked source/config files (excluding allowlisted test fixtures).
