# Full Application Baseline Artifacts

This directory records the local-only baseline performed on the
`codex/full-app-baseline-and-architecture` branch.

`RESULTS.md` contains redacted command outcomes, scope limits, and blockers.
It intentionally contains no environment values, access tokens, private keys,
credential-bearing configs, downloaded release files, or live-service output.

The reproducible entry point is:

```bash
bash scripts/full_app_baseline.sh
```

It runs compilation, project-owned test/static guards, shell syntax, static
JavaScript syntax, Compose interpolation with dummy values, and Flutter
analysis/tests/debug Linux build. It does not deploy, publish, sign, install a
VPN package, contact live VPN infrastructure, or run external load tests.

Passing this baseline is not release readiness. See
`docs/FULL_APPLICATION_REFACTOR_PLAN.md` for what remains unproven or blocked.
