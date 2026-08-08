# SecureWave Codex CLI Workflow

This is the repository-native, Codex-CLI-only local readiness path. It uses
the existing fixed controller and writes all generated evidence outside the
checkout.

## Local command

Run from a clean checkout with the candidate identity supplied explicitly:

```bash
cd /Users/simonparris/Documents/securewave
.venv/bin/python scripts/codex_cli_controller.py workflow \
  --expected-branch agent/securewave-model-reliability \
  --expected-sha 449bd23c597f74a7066f6891f05f37ca93fb2e43 \
  --api-base http://127.0.0.1:18080/api \
  --evidence-dir /tmp/securewave-codex-workflows
```

The command creates a timestamped run directory below the external evidence
root. It does not install dependencies, change Git refs, send email, deploy,
run Terraform, call public URLs, or mutate VPN state.

The same controller exposes isolated local lanes when needed for diagnosis:

```bash
.venv/bin/python scripts/codex_cli_controller.py local-e2e \
  --evidence-dir /tmp/securewave-codex-local-e2e

.venv/bin/python scripts/codex_cli_controller.py local-deb \
  --api-base http://127.0.0.1:18080/api \
  --output-dir /tmp/securewave-codex-package \
  --evidence-dir /tmp/securewave-codex-local-deb
```

Use `workflow` for the preflight, local validation, and release-readiness
commands; it runs those stages in order and records their exact command/result
table in the external summary.

## Stages

1. `PRECHECK` verifies repository identity, clean state, protected files,
   tool availability, host/Docker architecture, and Git remote reachability.
2. `LOCAL_VALIDATE` runs syntax checks, release guards, website verification,
   and the focused unit contract tests. Pydantic plugin discovery is disabled
   because this lane has no application plugins and must not scan arbitrary
   installed distributions.
3. `LOCAL_E2E` runs the real credentialless authentication/session contract
   against temporary SQLite and local email capture.
4. `PACKAGE` invokes the existing controller `local-deb` operation. The
   package is non-production, ARM64-only, and remains outside the repository.
   A loopback `/api` base is required for this stage.
5. `RELEASE_READINESS` reconciles local results and records presence-only
   status for external packets, approval, and environment inputs.
6. `EXTERNAL_CANARY` and `DEPLOY` are always `NOT_RUN` from this workflow.
   Use the existing controller operations separately only with a valid packet,
   target binding, and independent signed approval.

## Result states

`PASS` means the requested check completed successfully. `FAIL` means it ran
and failed. `BLOCKED` means a required tool, input, architecture, or external
condition is absent. `NOT_RUN` means a later stage was intentionally gated.
`UNKNOWN` means available evidence was contradictory or insufficient.

`LOCAL_WORKFLOW_READY=yes` means local validation and E2E passed, and package
construction either passed or produced a deterministic environment blocker.
`PACKAGE_READY=yes` requires a verified `.deb`, metadata, ARM64 architecture,
source provenance, helper contract, and checksum. `EXTERNAL_RELEASE_READY` is
`no` until the separate authorization and target evidence exists.

An intentional dirty worktree does not prevent `LOCAL_VALIDATE` or
`LOCAL_E2E`, but it blocks `PACKAGE` with `BLOCKED_WORKTREE_DIRTY` because the
package controller requires clean source provenance. Review and commit the
intended changes before rerunning the package and release-readiness gates.

## Inputs by phase

- Local: no secrets. The expected branch/SHA and loopback package API base are
  explicit command inputs.
- Tests: no external credentials; the local lane supplies temporary test
  configuration and disables optional Pydantic plugin discovery.
- Staging: `SECUREWAVE_API_BASE_URL`, diagnostic credentials, target/image,
  staging host/user/remote directory, and `CONFIRM_DEPLOY`.
- Email: `EMAIL_PROVIDER`, `FROM_EMAIL`, and the selected SMTP or SendGrid
  variables. Check-only is not delivery evidence.
- Production: production host/image/user/remote directory plus the existing
  signed packet and approval contract.

## ARM64 packaging

The package lane requires Docker server platform `linux/arm64`; x86_64 is not
substituted. If unavailable, the result is `BLOCKED_ARM64_RUNTIME_REQUIRED`.
The package is built and inspected in the existing pinned Docker toolchain,
then written to the external evidence run only. It is never added to
`static/downloads/manifest.json` and does not prove installation, systemd,
secure storage, remote login, or WireGuard routing.

## Release boundary

Codex may inspect the checkout, run bounded local checks, create temporary
external evidence, and build the non-production local package. Human-approved
external packet, target, credential, and signed approval inputs are required
before login diagnostics, provider sends, staging deployment, production
deployment, release publication, Terraform mutation, public URL verification,
or live VPN testing. No workflow stage invents or bypasses those inputs.
