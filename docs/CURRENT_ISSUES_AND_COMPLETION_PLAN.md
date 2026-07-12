# SecureWave Current Issues and Completion Plan

Last verified: 2026-07-12 UTC

Audit revision: `origin/master` at
`b2c69ade88a6d7d96a1478f792c39ec793888fac`

Primary execution host: Linux `aarch64` / Debian `arm64`

Additional permitted host: a Mac running Codex, for Apple-native work only

## Executive verdict

SecureWave's merged `master` is repository-healthy but not product- or
release-complete. The backend, Flutter client, migrations, Linux helper source,
security scans, Docker build, and CI gates are in good condition. The remaining
work is concentrated in live runtime proof, clean package lifecycle proof,
operational readiness, Apple-native implementation/evidence, dependency and
code-structure debt, documentation drift, and GitHub governance.

No production deployment, external load test, package publication, provider
configuration, or live VPN activity was performed for this report.

## Evidence collected

The repository certification command was run from a clean worktree:

```bash
PATH="/tmp/securewave-shellcheck/usr/bin:/tmp/securewave-actionlint:$PATH" \
PYTHON_BIN=/home/sp/cyber-course/projects/securewave/.venv/bin/python \
bash scripts/certify_repository.sh
```

Results:

- Repository hygiene, redacted secret scan, release/UI/Xcode guards: passed.
- Python compile, Bandit high-severity scan, and dependency audit: passed.
- Backend tests: 381 passed, 1 skipped, 2 SQLite reflection warnings.
- The skip is the PostgreSQL concurrency test when
  `SECUREWAVE_TEST_POSTGRES_URL` is absent locally. The current GitHub CI job
  supplies PostgreSQL and runs this path.
- Flutter analyze: no issues.
- Flutter tests: 26 passed.
- Flutter Linux release build: passed for ARM64. This is not x64 proof.
- Docker build check and image build: passed.
- Shell syntax, ShellCheck, actionlint, and JavaScript syntax: passed.
- Android build: unavailable locally because Java is absent; the corresponding
  `Flutter Android Debug Build` job is green on current `master` CI.
- Certification summary: `failures=0 blockers=1` (local Java only).

Current GitHub `master` CI run `29165957528` is green. Its coverage artifact
reports 9,173 of 14,969 lines covered: 61.28% overall. Coverage is uneven:
services 35.6%, routers 54.2%, database 54.5%, routes 60.5%, models 88.1%, and
utils 96.1%.

## Current issues, ordered by severity

### Critical release gates

#### 1. Live staging and production runtime remain uncertified

There is no currently authorized staging target, approved load envelope,
staging credential set, deployed revision proof, monitoring access, rollback
proof, or backup/restore evidence in this environment. Consequently the full
user lifecycle, per-protocol data plane, operational recovery, and bounded load
tests remain unproven.

Completion evidence:

- Written target authorization and isolation from production.
- Exact deployed commit and immutable image digest.
- Health/readiness, monitoring, alerts, logs, rollback, and restore proof.
- Registration through logout/login persistence and device/profile lifecycle.
- Per-authorized-protocol route, DNS, endpoint bypass, exit-IP, counters,
  disconnect, and cleanup evidence.
- Approved 100-to-1,000-user staged load plan with abort thresholds and results.

#### 2. Linux package lifecycle coverage is incomplete

This host proves ARM64 source/build behavior but is not a clean VM and lacks
passwordless root. A historical x64 workflow artifact has a valid amd64 package
and checksum, but it predates helper contract 10. It cannot certify the current
merged runtime.

Completion evidence:

- Build current contract-10 ARM64 and x64 `.deb` files from one reviewed SHA.
- Clean native ARM64 and x86_64 systemd VM install/uninstall proofs.
- Helper binary, service, contract, tmpfiles, socket owner/group/mode, IPC
  allowlist, application launch, and residue cleanup proof.
- Authorized live protocol proof for the exact installed package, separately
  from build/install proof.

#### 3. Protocol release truth remains intentionally limited

WireGuard is the strongest Linux path. OpenVPN depends on real profile and
server authentication compatibility. Linux IKEv2 helper orchestration exists,
including the pref-220 loop guard, but the backend intentionally refuses Linux
IKEv2 profiles. macOS has no Network Extension provider. Windows has only an
implemented WireGuard service path and no native runtime evidence.

Do not enable or advertise protocols to make the matrix look complete. A
protocol becomes available only after the normal backend/client/helper path and
full data-plane/cleanup evidence pass.

### High-priority engineering and operational issues

#### 4. GitHub does not enforce the repository's own gates

- `master` is not protected and no repository rulesets exist.
- The production environment exists but has no protection rules.
- Actions are enabled with `allowed_actions=all`; GitHub-level SHA pinning is
  not required, although the tracked workflows currently use immutable pins.
- Default workflow token permissions are read-only and workflows cannot approve
  pull-request reviews, which is correct.

This permits direct pushes and merges that bypass the six green CI jobs and
CODEOWNERS review.

#### 5. Pull-request and branch backlog is unmanaged

GitHub currently reports 28 branches and 19 open pull requests, with no review
decisions. Eleven are Dependabot PRs. Nine dependency PRs are clean and green;
Riverpod 3.3.2 fails both Flutter jobs, and Python 3.14 fails Docker. Eight older
feature/evidence PRs remain: six are dirty, one is unstable, and one is clean
but has no current checks. Several overlap work already merged through PRs
#26–#28.

#### 6. Operational completion depends on external resources

The following cannot be completed by code changes on this VM:

- Staging/production authorization and credentials.
- SMTP provider provisioning and live email proof.
- Stripe live resource creation and billing proof.
- Hetzner API/state access, reviewed production environment, and fleet audit.
- Monitoring destinations, alert owners, escalation policy, and backup restore.
- External load-test authorization and limits.
- Apple signing identities, App Store Connect access, and review account.

#### 7. Test coverage is weakest in the service layer

Overall coverage is useful but insufficient for refactoring high-risk services.
The `services` package is at 35.6%, while billing, monitoring, payments,
subscription, VPN peer management, and provider integrations contain many of
the largest modules. Coverage should rise by risk and behavior, not through
low-value line execution.

### Medium-priority code and maintenance issues

#### 8. Static-analysis debt is hidden by the narrow CI Ruff selection

Full first-party Ruff analysis reports 166 diagnostics; 104 are automatically
fixable. These include unused imports/locals, import-order problems, redundant
f-strings, and one symbol redefinition in `main.py` where model `user` and route
`user` share a name. SQLAlchemy boolean/NULL expressions also trigger generic
E711/E712 advice; these must be converted to `.is_(...)` semantics or explicitly
configured, not mechanically replaced with Python `not`.

#### 9. Core modules are too large and mix responsibilities

Largest examples:

- `securewave_app/lib/app.dart`: 1,628 lines.
- `routes/vpn.py`: 1,597 lines.
- `routes/auth.py`: 942 lines.
- `routes/devices.py`: 812 lines.
- `securewave_app/lib/core/state/vpn_state.dart`: 759 lines.
- Several billing, provider, monitoring, and support services exceed 600 lines.

The backend also has both `routes/` and `routers/` trees, making ownership and
API boundaries unclear. Flutter screens, application wiring, state, and service
logic are concentrated in a few files.

#### 10. Dependency maintenance needs controlled sequencing

Flutter reports 11 outdated direct/dev dependencies. The upgrade set includes
major changes to Riverpod, secure storage, Flutter lints, connectivity,
environment loading, and platform information. These should not be merged as
one batch. Python has several green Dependabot updates, but Python 3.14 is not a
drop-in base-image update and currently fails Docker.

#### 11. Documentation and branch instructions are stale

- `TODO.md` still instructs operators to switch to the old `Linux` branch.
- `docs/current_release_status.md` still describes a `master`/`flutter` branch
  model despite the merged product work living on `master`.
- The portability and repository-certification reports retain their historical
  pre-merge bases; those are valid audit history but need a current-state index.
- `docs/POST_MERGE_ENTERPRISE_RELEASE_TODO.md` is anchored to PR #15 even though
  newer merged work supersedes that branch stack.

#### 12. Build and dependency definitions overlap

`Dockerfile` and `Dockerfile.simple` differ only in a small set of runtime
defaults/directories. Five requirements variants contain overlapping dependency
sets without a hash-locked production artifact. These create drift risk.

#### 13. Minor warning and tooling debt remains

- `pytest-asyncio` warns that `asyncio_default_fixture_loop_scope` is unset.
- SQLite cannot reflect two PostgreSQL expression indexes during migration
  tests; PostgreSQL CI is the authoritative migration path.
- The Linux build emits deprecated literal-operator warnings from the current
  secure-storage plugin's vendored JSON header.
- Local Android certification needs a pinned JDK 17 installation.

## Successful-completion plan

The order below keeps `master` releasable and avoids combining runtime,
refactor, dependency, and infrastructure risk.

### Phase 0 — Establish one source of truth (Linux VM, 1–2 PRs)

1. Replace stale branch instructions with `master` plus short-lived PR branches.
2. Create a single current-status index linking historical evidence without
   rewriting it as current proof.
3. Classify all 19 open PRs as merge, superseded/close, split, or rebase.
4. Apply the GitHub protections defined in the companion refactor plan.

Exit gate: protected `master`, green required checks, no ambiguous canonical
branch, and every old PR has an owner/disposition.

### Phase 1 — Make local certification complete (Linux VM, 2–3 PRs)

1. Install/pin JDK 17 and make Android compile part of the local certification.
2. Add a disposable PostgreSQL container wrapper so the concurrency test and
   fresh/upgrade migrations run locally without manual environment setup.
3. Configure the pytest asyncio fixture scope explicitly.
4. Add full Ruff policy incrementally: safe F-class cleanup first, SQLAlchemy
   expression cleanup second, then enforce the selected rules in CI.
5. Raise service-layer coverage using behavior tests for auth, billing,
   metering, peer lifecycle, monitoring, and provider failure boundaries.

Exit gate: local certification reports zero failures and zero tool blockers;
PostgreSQL concurrency runs; CI remains green; service coverage reaches an
agreed first threshold (recommended 55%) with no regression in critical paths.

### Phase 2 — Refactor without changing contracts (Linux VM, 5–8 PRs)

Follow the companion code refactor plan. Freeze public API schemas, helper
contract 10, migration history, auth boundaries, protocol availability, and
usage idempotency with characterization tests before moving code.

Exit gate: smaller modules, one backend routing convention, no API/schema or
helper-contract regression, full tests green, and improved ownership.

### Phase 3 — Dependency modernization (Linux VM plus CI, one PR per risk set)

1. Merge green patch/minor updates after reviewing changelogs and rerunning CI.
2. Handle Alembic/Pydantic/scikit-learn as separate behavior-reviewed upgrades.
3. Migrate Riverpod 3 with explicit state-lifecycle tests.
4. Upgrade secure storage with Linux, Android, and Mac persistence tests.
5. Keep Python 3.12 as the runtime base until the application and dependency
   matrix explicitly supports a newer Python version.

Exit gate: no known dependency vulnerabilities, reproducible locks, green
platform builds, and no silent persistence/state change.

### Phase 4 — Current Linux packages and clean-host proof (Linux VM + external x64 VM)

1. Build current ARM64 package from the reviewed SHA and certify install/helper/
   socket/IPC/launch/uninstall on a clean ARM64 systemd VM.
2. Run the x64 GitHub build from the same SHA and certify it on a clean native
   x86_64 systemd VM. The current ARM64 VM cannot substitute for this step.
3. Keep all artifacts beta/unavailable until exact-package proof passes.

Exit gate: architecture-matched package metadata, checksums, contract 10,
systemd lifecycle, restrictive socket, no arbitrary IPC, and clean uninstall.

### Phase 5 — Authorized staging certification (external staging)

1. Obtain written scope, target, credentials, protocol endpoints, test window,
   monitoring access, and load limits.
2. Prove deployed SHA/digest, isolation, health/readiness, rollback, backup,
   restore, alerting, and privacy-redacted logs.
3. Run the complete account/device/profile/usage/session lifecycle.
4. Run full data-plane proof for each configured protocol. Verify IKEv2 never
   installs an unqualified pref-220 rule.
5. Run the approved load ramp with explicit abort thresholds.

Exit gate: reviewed redacted staging report and an explicit release decision.

### Phase 6 — Apple work (Codex app on Mac)

Use the Mac only for work Linux cannot prove:

1. Rebase the Apple project on protected `master` and run Xcode workspace,
   CocoaPods, Flutter analyze/test, unsigned iOS build, and macOS UI build.
2. Decide product scope: iOS Packet Tunnel Provider only, or a separate macOS
   Network Extension target. Do not call the UI demo a VPN client.
3. With approved Apple credentials, build/sign/archive/export and validate
   entitlements, bundle identifiers, notarization where applicable, install,
   persistence, and Network Extension behavior.
4. Return only redacted logs, checksums, signing/notarization status, and exact
   commit evidence to the repository.

Exit gate: signed native artifacts and platform-specific runtime proof, or a
truthful UI-only/unsupported status.

### Phase 7 — Production decision (separately authorized)

Production deployment, provider activation, artifact publication, and public
availability changes require a separate reviewed authorization after all prior
gates pass. Completion is a release decision, not merely a green build.

## Definition of project completion

SecureWave is complete for a claimed platform/protocol only when:

- Code, migrations, security, builds, and dependency checks are green.
- The exact package is installed and removed cleanly on each architecture.
- The normal backend/client/helper path proves route, DNS, endpoint bypass,
  exit IP, counters, disconnect, and cleanup.
- Staging proves account, device, profile, usage, monitoring, recovery, and
  approved load behavior.
- Documentation and downloads expose only verified truth.
- GitHub prevents bypass of required review and checks.
- Platform signing/runtime evidence exists where the platform requires it.
