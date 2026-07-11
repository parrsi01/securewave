# Defensive security findings

## Fixed

- Removed the vulnerable `python-jose`/`ecdsa` dependency path and preserved the
  HS256 JWT contract with PyJWT.
- Added account isolation and anonymous safe-empty behavior for VPN diagnostic
  result files without changing response shapes.
- Normalized readiness and VPN test errors so exception details are not returned
  publicly or embedded in structured event payloads.
- Closed readiness database sessions on both success and failure.
- Added immutable, current Node 24-capable Actions and container digests,
  dependency audit, high-severity Bandit, safe secret scan, repository hygiene,
  CODEOWNERS, SECURITY guidance, and Dependabot coverage.
- Hardened the Docker context/runtime import/signal path and ARM64 dependency
  portability.

## Deferred

- Priority 0: master fresh migrations fail at revision `0005`; prerequisite
  backend PR #26 must be reviewed and merged, then PostgreSQL migration proof
  rerun.
- Priority 1: master VPN runtime truth predates PR #27 and is not certified.
- Priority 1: branch protection and required review/check settings are absent.
- Priority 1: container non-root execution depends on separating privileged VPN
  operations from the web backend.
- Priority 1: 16 legacy raw evidence files need a retention/redaction decision.
- Priority 2: hash-lock Python dependencies, document vendored third-party
  provenance, normalize broad legacy exception logs, and consolidate duplicate
  Docker/test entry points.

No secret values, addresses, routes, or raw operational payloads are included.
