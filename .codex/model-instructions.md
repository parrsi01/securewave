# SecureWave Model Instructions

You are working on SecureWave, a production VPN SaaS with a FastAPI backend,
server-rendered static web pages, and a Flutter desktop/mobile client.

Treat repository evidence as authoritative. Before making a claim or edit:

1. Inspect the relevant source and nearby tests with `rg`, `rg --files`, and
   direct file reads.
2. Check `git status --short --branch` and preserve existing user changes.
3. Identify the actual source of truth. Backend page aliases and web routing
   are in `main.py`; served web pages are in `static/`; shared web styling is
   `static/css/web_ui_v1.css`; Flutter UI sources are under
   `securewave_app/lib/`.
4. If a symbol, route, API, dependency, environment variable, or behavior is
   not present in the repository or verified tool output, say it is unknown.
   Do not infer it.

SecureWave-specific invariants:

- The web and product brand use a dark navy and blue/cyan visual system. Do not
  introduce purple, violet, indigo, or a conflicting logo palette.
- WireGuard behavior must remain intact.
- OpenVPN is available only when the repository's authenticated evidence and
  runtime contracts prove it. Fail closed when proof is absent.
- IKEv2 is unavailable unless explicit current evidence and authorization prove
  otherwise. Do not infer availability from legacy metadata.
- Local source edits are not live deployment. Never claim a public URL changed
  without checking that URL after deployment.

Implementation discipline:

- Make the smallest change that satisfies the request.
- Prefer existing helpers, route maps, contracts, and test patterns.
- Do not create placeholder code, fake test results, guessed endpoints, or
  invented configuration keys.
- Do not reset, discard, or overwrite user changes.
- Use `apply_patch` for manual edits.

Verification discipline:

- For web changes, run `bash scripts/verify_website.sh`, `python3 -m py_compile
  main.py`, and `git diff --check` when applicable.
- For backend changes, run the narrowest relevant pytest selection, then the
  broader suite when shared contracts are affected.
- For Flutter changes, run `flutter analyze` and the narrowest relevant tests.
- Report exact commands and observed results. Distinguish passed, failed, not
  run, and blocked.

Deployment discipline:

- Never infer or print production hosts, immutable image references, SSH
  credentials, or production environment values.
- Use `scripts/deploy_production.sh` and its fail-closed checks.
- Do not deploy an uncommitted or unverified tree.
- If external access is missing, stop and report the exact blocker instead of
  claiming deployment or bypassing the guard.

Final response format:

- Changed: exact files and behavior.
- Verified: exact commands and results.
- Blocked: only genuine remaining blockers.
