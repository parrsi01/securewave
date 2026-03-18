# Secret Remediation (Git History Findings)

Date: 2026-02-11

## Summary

A git-history scan (Gitleaks v8.30.0) found **28 potential secret leaks** in past commits. Current working tree scan is clean (no secrets detected in the present codebase), but **git history is immutable leakage** unless you later choose to rewrite history.

This document describes what was found and what to rotate / revoke. It does **not** rewrite history automatically.

## What Was Found (File + Commit)

Findings were reported in these historical paths/commits:

- `wg_data/users/*.conf` (commit `baacabd86a13`): WireGuard client configuration files (contain tunnel private keys).
- `artifacts/vpn_tests/20260208_113437/raw/security_audit.md` (commit `ec1e04a14104`): committed test artifacts containing secret-like material.
- `.claude/settings.local.json` (commit `4470697258c5`): JWT-like token material.
- `.env.production.example` (commit `0aa59a9a0f90`): example file contained a secret-looking value (now scrubbed in HEAD).
- `SETUP_GUIDE.md` (commit `2a46582a40b9`), `DEPLOYMENT.md` / `QUICKSTART.md` (commit `1b9867ae806f`): documentation included curl auth-header patterns (likely placeholders, but treat as suspicious until confirmed).
- `securewave_app/ios/ThirdParty/...` (commit `c364c7aa2d4d`): vendored upstream test assets triggering false positives (not SecureWave-owned secrets).

## Immediate Actions (Assume Compromise)

1. **WireGuard peers**
   - If the leaked `wg_data/users/*.conf` keys ever corresponded to a reachable WireGuard server:
     - Revoke/remove those peers from the server (`wg set wg0 peer <pubkey> remove`).
     - Force client key rotation for affected devices.
   - If any server private key was ever exposed, rotate the server key and restart WireGuard.

2. **Application secrets**
   - Rotate all production secrets that may have been present at the time of the commits above, at minimum:
     - `ACCESS_TOKEN_SECRET`, `REFRESH_TOKEN_SECRET`
     - `AUTH_ENCRYPTION_KEY`, `WG_ENCRYPTION_KEY`
     - Payment provider secrets (Stripe/PayPal), email provider keys, and any `WG_API_KEY` used for server management.
   - Invalidate sessions/tokens if applicable.

3. **CI/CD + environment**
   - Ensure secrets are only provided via environment variables / secret stores.
   - Confirm `.gitignore` prevents committing `.env`, key material, terraform state, and `wg_data/`.

## Optional: History Rewrite (Not Performed)

If you decide you must remove secrets from git history, use `git filter-repo` (or BFG) to purge the leaked paths/commits, then force-push and coordinate with all clones.

This is intentionally **not** performed automatically.

## Verification

- Run a current-tree scan (CI uses this):
  - `gitleaks dir --redact --no-banner -c .gitleaks.toml .`
- Run a full history scan (will continue to flag the historical commits until rewritten):
  - `gitleaks git --log-opts="--all" --redact --report-format json --report-path <path>`

