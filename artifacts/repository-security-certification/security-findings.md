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
- Corrected the Android VPN service foreground type/permission and added a
  manifest regression test without weakening BIND_VPN_SERVICE or exported-state
  restrictions.
- Corrected stale Android activity-result, service import, and WireGuard parser
  calls while preserving the MethodChannel contract and OS VPN permission flow.

## Deferred

- Priority 1: branch protection and required review/check settings are absent.
- Priority 1: container non-root execution depends on separating privileged VPN
  operations from the web backend.
- Priority 1: 16 legacy raw evidence files need a retention/redaction decision.
- Priority 2: hash-lock Python dependencies, document vendored third-party
  provenance, normalize broad legacy exception logs, and consolidate duplicate
  Docker/test entry points.

No secret values, addresses, routes, or raw operational payloads are included.
