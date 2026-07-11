# Certification check results

## Passed

- Backend/API/security: 295 tests.
- Focused JWT, account-isolated VPN diagnostics, and readiness boundary: 81
  tests.
- Flutter: analyze clean, 24 tests, ARM64 Linux release build.
- Python dependency audit: no known vulnerabilities after dependency changes.
- Bandit: no high-severity findings.
- Docker: both Dockerfile checks clean; standard ARM64 image built and imported
  the complete runtime module set.
- Repository hygiene, redacted secret scan, Python compile, tracked shell
  syntax, tracked JavaScript syntax, UI guards, plan-copy guards, release
  guards, Xcode workspace guards, YAML parsing, and diff checks.

## Failed

- Fresh Alembic upgrade from an empty database fails at revision `0005` because
  the migration expects an `audit_logs` table that the earlier chain did not
  create. This is a release blocker, not a pass.

## Blocked or unavailable

- Android local build: Java/JDK unavailable. The first pinned Java 17 CI build
  found the invalid foreground service type `vpn`; the manifest now uses the
  supported VPN-app `systemExempted` type. The next compile exposed stale
  Kotlin activity-result, service-import, and config-parser calls; those now use
  compile-compatible APIs with static regression tests. GitHub run
  `29150029857` subsequently passed the Android debug compile.
- ShellCheck and actionlint: unavailable locally.
- Windows and macOS native builds: unavailable on Linux ARM64.
- x64 package/install/runtime: wrong host architecture.
- Live VPN routing/DNS/exit-IP/data-plane: no authorized credentials or runtime
  change; not run.
- Terraform apply, production deploy, publication, signing, SMTP/provider work,
  and external load tests: explicitly excluded.

An unavailable tool or blocked boundary is never reported as passing.
