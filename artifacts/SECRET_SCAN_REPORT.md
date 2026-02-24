# Secret Scan Report

Generated (UTC): 2026-02-19T14:27:00Z

## Working Tree Findings

Pattern: `sk_test_[0-9A-Za-z]{16,}`

- /home/sp/cyber-course/projects/securewave/tests/security/test_log_redaction.py:23

## Git History Findings

Pattern: `sk_test_[0-9A-Za-z]{16,}`

- 848ce32 (origin/release/stripe-harden-web, release/stripe-harden-web) feat: stripe hardening + web account/billing center

Pattern: `-----BEGIN PGP PRIVATE KEY BLOCK-----`

- dd4d397 feat: complete VPN platform implementation + security hardening

Pattern: `JWT_SECRET(_KEY)?\s*=\s*["\047]?[A-Za-z0-9_\-]{16,}`

- 8599b42 hetzner: add terraform module, sync tool, and runbook
- 5a2cd35 chore: remove Azure remnants and purge artifacts
- 2a46582 Build SecureWave demo single-app experience
- 68609ab Modernize UI with Bootstrap 5.3 and fresh deployment

Pattern: `SECRET_KEY\s*=\s*["\047]?[A-Za-z0-9_\-]{16,}`

- 1324e76 feat: production reliability engineering (watchdog + geo reco + cost guardrails)
- 76a1dfd test: add realism simulation suite and reports
- 8599b42 hetzner: add terraform module, sync tool, and runbook
- b4a2ef4 security: harden gitignore and add gitleaks scanning
- 5a2cd35 chore: remove Azure remnants and purge artifacts
- 2f1c667 (tag: v1.0.0-non-apple) chore(release): freeze + non-Azure simulation hardening
- 37c592d feat: comprehensive testing, refactoring, and production readiness
- 3138a63 Update app assets, security, ML, and cleanup
- 2a46582 Build SecureWave demo single-app experience
- 68609ab Modernize UI with Bootstrap 5.3 and fresh deployment

## Notes
- This scan is heuristic and may flag test fixtures or documentation examples.
- If a real secret is detected, rotate it immediately and rewrite git history.
