# SecureWave Repository Certification Report

Last audited: 2026-07-11 UTC

## Verdict

Current `origin/master` is **not release-certified**. This pass establishes
stronger repository, CI, dependency, Docker, and defensive security gates, but
does not override unmerged prerequisite work or treat blocked checks as passes.

Audit basis:

- Base: `origin/master` at `d8ddec2d`
- Branch: `codex/repository-security-certification`
- Host: Linux ARM64
- Backend PR #26, mobile/UI PR #25, baseline PR #24, and VPN runtime PR #27
  were open drafts and unmerged when this branch was created.
- No work from those branches was silently copied into this branch.
- VPN PR #27's first Python CI run exposed missing GLib helper-test build
  dependencies. Its focused workflow-only correction was committed on that
  branch as `0082f354`; this report still treats its replacement CI as an
  external prerequisite until completed.

## Verified commands and results

| Area | Command | Result |
| --- | --- | --- |
| Backend/API | `.venv/bin/python -m pytest -q tests` | 293 passed |
| Focused security/API | `.venv/bin/python -m pytest -q tests/security/test_security.py tests/security/test_vpn_test_result_isolation.py tests/smoke/test_api_endpoints.py` | 81 passed |
| Python dependencies | `.venv/bin/python -m pip_audit -r requirements.txt --strict` | No known vulnerabilities after JWT dependency replacement |
| Python security | `.venv/bin/python -m bandit -q -lll -r main.py routes routers services models database scripts infrastructure` | No high-severity findings; documented `nosec` warnings remain visible |
| Python syntax | `.venv/bin/python -m compileall -q ...` | Passed for repository Python surfaces |
| Flutter | `flutter analyze` | No issues after creating the non-secret CI env asset |
| Flutter | `flutter test --reporter compact` | 24 passed |
| Linux app | `flutter build linux --release` | Passed on ARM64; this is not x64 or live VPN evidence |
| Android app | `flutter build apk --debug` | Blocked locally: Java/JDK unavailable; a pinned Java 17 CI job was added |
| Docker lint | `docker build --check .` and `docker build --check -f Dockerfile.simple .` | Passed with no warnings |
| Docker image | `docker build --tag securewave-certification:local .` | Passed on ARM64; runtime module import executed inside the image |
| Shell/static | tracked `bash -n`, tracked `node --check`, UI/plan/release/Xcode guards | Passed |
| Repository safety | `python3 scripts/check_repository_hygiene.py` and `python3 scripts/scan_repository_secrets.py` | Passed; scanners never print matched secret values |
| Alembic | fresh SQLite `alembic upgrade head` with `AUTO_CREATE_TABLES=false` | Failed at revision `0005`: expected `audit_logs` table absent |
| ShellCheck | `shellcheck` | Unavailable; not passed |
| Actions lint | `actionlint` | Unavailable; YAML parsing and local workflow guards passed, but actionlint is not claimed |
| Windows/macOS | native build/runtime tools | Unavailable on this host; not passed |

The single developer-facing maximum safe command is:

```bash
PYTHON_BIN=.venv/bin/python bash scripts/certify_repository.sh
```

It reports failures and unavailable tools distinctly and performs no deploy,
publication, signing, provider email, external load test, or live VPN action.

## Repository organization audit

- GitHub reported 16 remote branches and 10 open pull requests. Eight were
  drafts, two were non-draft, and none had a review decision.
- No branch was reported protected. CODEOWNERS is now present, but it cannot
  enforce review until repository branch protection is configured externally.
- The older Linux PR stack (#12 through #21) overlaps newer portability work
  and needs maintainer close/retain decisions. No PR or branch was deleted or
  closed automatically.
- The tracked artifact tree contained 91 files, including 16 legacy raw
  `.log`, `.out`, `.body`, or `.headers` evidence files. A baseline allowlist
  prevents new raw evidence; deleting historical evidence requires a retention
  decision and redacted replacement summaries.
- Large downloadable archives under `static/downloads/` are intentional public
  site inputs. Repository/package size should be revisited with release storage
  ownership rather than deleting public artifacts speculatively.
- README branch/test-path descriptions were corrected. `SECURITY.md`,
  CODEOWNERS, Dependabot coverage, and the certification entry point were added.
- `Dockerfile` and `Dockerfile.simple` remain duplicated runtime variants. They
  now share one entrypoint, but consolidation is deferred to avoid changing
  deployment behavior without an owner decision.

## GitHub Actions audit

Changes made:

- All third-party Actions are pinned to full immutable commit SHAs; official
  Actions use the current Node 24-capable release majors observed during audit.
- PostgreSQL, Redis, and Python container inputs are digest-pinned.
- Workflow-level permissions remain read-only by default.
- The macOS build job now has read-only contents permission. Optional publishing
  is isolated into a separate job that does not execute repository build code
  with a write token and accepts only the expected zip and JSON manifest.
- Artifact uploads use explicit 14-day retention.
- PR CI now has repository hygiene, redacted secret scanning, shell/JavaScript
  syntax, dependency audit, high-severity Bandit, backend, Flutter Linux,
  Flutter Android debug compile, and Docker build jobs.
- Dependabot monitors pip, GitHub Actions, Docker, and Dart/pub dependencies.
- Existing concurrency cancellation remains enabled for CI and disabled for
  release/evidence jobs where preserving one complete run is preferable.

Remaining GitHub gates:

- Protect `master`; require pull requests, CODEOWNERS review, conversation
  resolution, signed/verified policy as selected by the owner, and all named CI
  checks before merge.
- Restrict release workflows to approved environments/maintainers and review
  repository Actions policy settings.
- Re-run CI after prerequisite branches are merged and this branch is rebased.
- Do not treat the manual x64 packaging workflow as install/live-routing proof
  or publication authorization.

## Defensive security findings fixed

1. Replaced `python-jose`/`ecdsa` with PyJWT for the existing HS256 JWT contract;
   the previous dependency audit had one known `ecdsa` vulnerability.
2. Preserved JWT claims, expiry, access/refresh type checks, bearer/cookie
   behavior, and unauthorized responses under existing tests.
3. Isolated VPN diagnostic files per account. Anonymous status/latest endpoints
   preserve their response shapes but expose no account result, and authenticated
   callers cannot read another account's raw or historical measurements.
4. Removed exception text from VPN diagnostic logs and the public readiness
   response. Readiness now closes its database session on both success/failure.
5. Added immutable supply-chain pins, dependency/security CI, safe secret and
   repository hygiene scanners, CODEOWNERS, and private-reporting guidance.
6. Added a deny-by-default Docker build context, copied all required runtime
   modules, verified `import main` during image build, used a shared exec-based
   entrypoint for correct signal handling, and fixed ARM64 Python 3.12 package
   portability with `psutil==7.2.2`.

## Findings deferred

Priority 0 / merge blocker:

- Fresh migration-to-head fails on master at revision `0005`. Backend PR #26
  contains the migration-focused refactor and must be reviewed/merged, followed
  by clean PostgreSQL creation and upgrade-to-head evidence. CI's current model
  table creation plus `alembic stamp head` is test setup, not migration proof.

Priority 1:

- Master does not include VPN portability PR #27. Its legacy Linux helper and
  protocol truth behavior must not be certified by this report.
- `master` has no enforced branch protection despite sensitive workflows and
  CODEOWNERS. This is a repository setting, not a code-only fix.
- The Docker runtime still starts as root because current WireGuard/server
  management privilege requirements are unresolved. Move to a non-root backend
  only after privileged VPN operations are separated and proven.
- Historical raw evidence needs a retention/redaction decision. New raw
  evidence is blocked by the repository hygiene gate.

Priority 2:

- Python dependencies are version-pinned but do not use a hash-locked
  requirements artifact.
- Vendored Apple/WireGuard third-party source needs a documented provenance and
  update cadence.
- Broad legacy exception logging across provider/operations services needs a
  systematic redaction pass; speculative mass rewrites were avoided.
- Consolidate Docker variants and overlapping test entry points after deployment
  owners confirm which paths remain supported.

## Release gates still required

1. Review and merge the prerequisite UI/backend/VPN refactors, then rebase this
   certification branch and rerun every check.
2. Prove fresh and upgrade-to-head PostgreSQL migrations without ORM table
   creation or Alembic stamping shortcuts.
3. Require all CI checks through protected-branch settings.
4. Run the pinned Android CI job and architecture-valid x64 Linux packaging VM
   certification; do not infer x64 from this ARM64 run.
5. Run authorized platform-specific VPN install/helper/routing/DNS/data-plane/
   cleanup proofs. Source builds are not live VPN evidence.
6. Complete Windows and macOS native build/runtime evidence on those platforms;
   macOS VPN remains unavailable without a native provider.
7. Review legacy PRs/branches and raw evidence retention before repository
   cleanup changes.

## Excluded work

- Production deployment and Terraform apply
- External load testing
- Artifact publication or availability promotion
- Pull-request merge or branch deletion
- VPN certificate/signing work
- SMTP/provider configuration or integration work
- Live credentials or real VPN infrastructure changes

No production readiness or live production capacity claim is made by this
report.
