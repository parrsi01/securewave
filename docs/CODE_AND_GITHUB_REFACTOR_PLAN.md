# SecureWave Code and GitHub Refactor Plan

Last verified: 2026-07-12 UTC

Planning base: `origin/master` at
`b2c69ade88a6d7d96a1478f792c39ec793888fac`

## Objective

Reduce coupling and operational ambiguity while preserving SecureWave's public
API, database migration chain, authentication boundaries, helper contract 10,
usage-meter idempotency, device ownership, fail-closed protocol truth, and
current release claims.

This plan deliberately separates structural refactors from dependency upgrades,
runtime changes, and release operations. Each pull request must be small enough
to review and independently revert.

## Non-negotiable compatibility boundaries

- Public HTTP paths, status codes, response schemas, and authentication modes.
- Active-user and token-version checks on protected routes.
- Per-account device/profile/test-result ownership.
- Usage-session idempotency under PostgreSQL concurrency.
- Alembic upgrade from every supported predecessor to one head.
- Linux helper socket path, permissions, request allowlist, and contract 10.
- WireGuard/OpenVPN validation and cleanup rules.
- IKEv2 pref-220 loop rejection and cleanup behavior.
- Windows WireGuard-only and macOS unavailable truth until native proof exists.
- Downloads API/manifest status and checksum semantics.

## Target code architecture

### Backend

Move toward one feature-oriented API package without a flag-day rewrite:

```text
app/
  bootstrap/        # FastAPI creation, middleware, logging, lifespan
  api/
    auth/
    devices/
    vpn/
    servers/
    billing/
    diagnostics/
    downloads/
  domain/
    identity/
    subscriptions/
    vpn_profiles/
    usage/
  infrastructure/
    database/
    payments/
    email/
    vpn_hosts/
    monitoring/
```

Use this as a destination, not an instruction to move everything at once.
Existing modules stay as compatibility adapters until callers and tests move.

### Flutter

Split `app.dart` and `vpn_state.dart` by responsibility:

```text
lib/
  app/              # router, theme, dependency wiring
  core/             # API, auth storage, shared errors
  features/
    auth/
    connection/
    servers/
    devices/
    account/
    settings/
```

Keep platform MethodChannel contracts behind one interface and provide fakes for
state tests. UI widgets should render state; orchestration belongs in feature
controllers/services.

## Pull-request sequence

### PR 1 — Characterization and contract lock

- Snapshot OpenAPI and downloads schemas in reviewable fixtures.
- Add migration-head/upgrade, auth matrix, device ownership, usage concurrency,
  helper contract, protocol truth, and IKEv2 pref-220 characterization tests.
- Add golden MethodChannel payload/error tests.

No production code movement is allowed in this PR.

### PR 2 — Static-analysis baseline

- Fix safe unused imports/locals and redundant f-strings.
- Alias the `models.user` and `routes.user` imports in `main.py`.
- Replace SQLAlchemy boolean/NULL comparisons with `.is_(True/False/None)` where
  semantically correct; do not apply Ruff's Python-boolean rewrite blindly.
- Add a reviewed Ruff configuration and ratchet CI from the current narrow
  fatal-error selection to the agreed rule set.
- Configure `asyncio_default_fixture_loop_scope` explicitly.

### PR 3 — Application bootstrap extraction

- Add an application factory.
- Move logging/redaction, middleware, static mounting, and lifespan setup out of
  `main.py` without changing routes or startup behavior.
- Retain `main:app` as the deployment entry point.

### PRs 4–6 — Backend vertical slices

Refactor one slice per PR, starting with the best-covered/highest-risk boundary:

1. Auth and identity.
2. Devices, profiles, and usage.
3. VPN servers/protocol availability and diagnostics.

For each slice:

- Separate request schemas, route handlers, domain decisions, and adapters.
- Use explicit transaction boundaries and typed result/error objects.
- Remove duplicate logic only after tests demonstrate equivalence.
- Keep compatibility re-exports until all internal callers migrate.

### PR 7 — Billing/provider boundary

- Define provider interfaces for Stripe/PayPal/email.
- Move webhook verification and idempotency to focused modules.
- Keep provider-disabled behavior fail-closed.
- Add contract tests using provider fakes; live provider activation remains a
  separate operational task.

### PRs 8–10 — Flutter feature extraction

1. Extract app/router/theme wiring from `app.dart`.
2. Split VPN connection state into profile acquisition, native lifecycle, and
   usage metering controllers.
3. Extract account/device/server/settings features and persistence adapters.

Each PR must run Linux and Android CI and preserve stored-session and stale-
device recovery tests. Mac tests run when Apple-specific code changes.

### PR 11 — Runtime/build definition consolidation

- Select one supported Dockerfile; make the other a thin documented variant or
  remove it after deployment-owner confirmation.
- Generate requirements inputs/locks from one declared dependency source, with
  hashes for production installation.
- Keep ML dependencies isolated from the minimum API/runtime environment.
- Document exactly which commands CI, developers, Docker, and production use.

### PR 12 — Test organization and coverage ratchet

- Organize tests by contract/unit/integration/runtime rather than historical
  entry point.
- Mark tests requiring PostgreSQL, root/systemd, live infrastructure, or native
  platforms explicitly.
- Publish separate core, service, and platform coverage metrics.
- Ratchet service coverage from 35.6% to 55%, then 70%, while requiring no
  reduction in auth, ownership, metering, migration, and helper-contract tests.

## GitHub target configuration

### Protect `master`

Apply a ruleset or branch protection with:

- Pull requests required; no direct pushes.
- One approval minimum and CODEOWNERS approval for owned paths.
- Dismiss stale approvals after new commits.
- Require all conversations resolved.
- Require the branch to be up to date before merge.
- Block force pushes and deletion.
- Apply to administrators unless a documented break-glass role is required.
- Require these exact checks:
  - `Repository Guards`
  - `Dependency and Code Security`
  - `Python Tests`
  - `Flutter Linux Analyze and Build`
  - `Flutter Android Debug Build`
  - `Docker Build`

Do not require signed commits until the owner selects and documents a workable
signing policy for local Codex, GitHub Actions, Dependabot, and Mac contributors.

### Restrict Actions

- Change repository Actions policy from `allowed_actions=all` to GitHub-owned
  plus an explicit allowlist for reviewed third-party actions.
- Require immutable action SHA pinning at repository/organization level if the
  account plan supports it; keep the repository guard regardless.
- Keep default workflow permissions read-only.
- Keep `can_approve_pull_request_reviews=false`.
- Require dependency-review or equivalent policy before merging dependency PRs.

### Protect release environments

For `production`:

- Require designated reviewers and prevent self-review.
- Limit deployment branches/tags to protected `master` and signed release tags.
- Add a wait timer if it matches the operating model.
- Store only production-scoped secrets in the environment.
- Separate build jobs from deploy jobs; untrusted PR code must never receive
  production credentials.
- Use OIDC/short-lived credentials where providers support them.

Add a separate `staging` environment with independent secrets, targets,
reviewers, and lower-risk deployment permissions. Never reuse production VPN,
database, payment, email, or signing credentials.

### Workflow structure

- Keep `ci-cd.yml` as required PR validation.
- Extract repeated setup into pinned composite actions only when reuse reduces
  drift without obscuring security-sensitive commands.
- Give release workflows explicit artifact provenance, checksum, retention,
  immutable revision, and environment approval gates.
- Keep evidence builds distinct from publication and installation proof.
- Add timeouts to jobs and expensive steps.
- Keep concurrency cancellation for PR CI; preserve complete release/evidence
  runs.
- Scope caches by lockfile, tool version, OS, and architecture. Never cache
  credentials, generated `.env` files, signing material, or VPN profiles.

## Branch and PR cleanup

Current state: 28 branches and 19 open PRs.

1. Review the nine clean/green Dependabot PRs individually; merge only after
   compatibility review, then rerun the combined dependency state on `master`.
2. Split Riverpod 3 into a migration PR with state tests.
3. Close or retarget Python 3.14 until the runtime compatibility matrix supports
   it.
4. Compare PRs #12, #13, #14, #15, #18, #21, #24, and #25 with `master`.
   Preserve unique changes in small new PRs; close superseded branches with a
   comment linking the replacing merge/evidence.
5. Delete merged/superseded remote branches only after PR disposition and
   evidence retention are confirmed.
6. Enable repository branch deletion on merge only if maintainers want that
   lifecycle; do not delete long-lived environment branches automatically.

## Ownership

Extend CODEOWNERS so review responsibility is explicit:

- Backend API/auth/migrations.
- Flutter product/state.
- Linux helper and packaging.
- Apple native/signing.
- Infrastructure/deploy workflows.
- Security/release evidence and public download truth.

At least two humans should understand the helper and production deployment
paths before they are considered operationally owned.

## Documentation cleanup

- Make `README.md` a short product/developer entry point.
- Make one `docs/STATUS.md` the current truth index.
- Keep historical certification reports immutable and clearly dated.
- Replace `TODO.md` branch-specific handoffs with owner, prerequisite, command,
  evidence, and completion-gate fields.
- Archive superseded plans instead of leaving contradictory active checklists.
- Link every release claim to a current evidence packet or mark it unproven.

## Per-PR acceptance checklist

Every refactor PR must provide:

- Problem statement and explicit non-goals.
- Changed contracts and migration impact, or “none”.
- Tests added before or with the move.
- `git diff --check`, secret scan, and relevant static analysis.
- Backend/Flutter/helper tests proportional to scope.
- Fresh and upgrade migration checks for model/schema work.
- Protocol truth and package checks for runtime work.
- Before/after module ownership and rollback instructions.
- No production deploy, artifact publication, or live test unless separately
  authorized.

## Completion metrics

The refactor is complete when:

- No first-party module exceeds the agreed size threshold without a documented
  reason (recommended 500 lines; 800 hard review trigger).
- One backend route convention is canonical.
- Full selected Ruff policy is enforced with zero baseline exceptions hidden in
  CI.
- Service coverage is at least 70% and critical contracts have direct tests.
- Production dependencies are reproducibly hash-locked.
- Required GitHub checks and CODEOWNERS review cannot be bypassed normally.
- Production/staging environments have independent protection and secrets.
- Old overlapping PRs and branches have an explicit disposition.
- Current status documentation agrees with manifests, APIs, packages, and
  platform runtime evidence.
