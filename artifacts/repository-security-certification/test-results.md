# Certification check results

## Passed

- Backend/API/security: 381 passed, 1 opt-in PostgreSQL concurrency skip.
- Focused JWT, account-isolated VPN diagnostics, and readiness boundary: 82
  tests.
- Flutter: analyze clean, 26 tests, ARM64 Linux release build.
- Python dependency audit: no known vulnerabilities after dependency changes.
- Bandit: no high-severity findings.
- Docker: both Dockerfile checks clean; standard ARM64 image built and imported
  the complete runtime module set.
- Repository hygiene, redacted secret scan, Python compile, tracked shell
  syntax, ShellCheck, actionlint, tracked JavaScript syntax, UI guards,
  plan-copy guards, release guards, Xcode workspace guards, Compose dummy-value
  config, Docker checks, and diff checks.

## Blocked or unavailable

- Android local build: Java/JDK unavailable. The first pinned Java 17 CI build
  found the invalid foreground service type `vpn`; the manifest now uses the
  supported VPN-app `systemExempted` type. The next compile exposed stale
  Kotlin activity-result, service-import, and config-parser calls; those now use
  compile-compatible APIs with static regression tests. GitHub run
  `29150029857` subsequently passed the Android debug compile.
- ShellCheck 0.9.0 and pinned actionlint v1.7.7 were installed temporarily and
  passed; CI now installs and runs both tools reproducibly.
- Windows and macOS native builds: unavailable on Linux ARM64.
- x64 package/install/runtime: wrong host architecture.
- Live VPN routing/DNS/exit-IP/data-plane: no authorized credentials or runtime
  change; not run.
- Terraform apply, production deploy, publication, signing, SMTP/provider work,
  and external load tests: explicitly excluded.

An unavailable tool or blocked boundary is never reported as passing.
