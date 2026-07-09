# SecureWave Full Application Baseline and Refactor Plan

Baseline branch: `codex/full-app-baseline-and-architecture`
Baseline date: 2026-07-09 UTC
Release conclusion: **not release-ready; no deployment or release publication was performed.**

This is a repository-grounded planning document, not a release certification.
It records what local checks prove, what source code implements but has not
been proven in a representative runtime, and what is blocked or absent.

## Scope and status vocabulary

| Status | Meaning in this document |
| --- | --- |
| **Verified** | A local command, test, or source inspection directly established the claim. |
| **Implemented but unproven** | Code or packaging exists, but required runtime, clean-host, or live-path evidence is absent. |
| **Blocked** | The current code or prerequisites prevent the required evidence. |
| **Not implemented** | No coherent implementation exists for the required behavior. |

Hard boundaries observed by this baseline:

- No production deployment, release publication, download-status change, signing,
  certificate procurement, SMTP/provider work, external load test, or live VPN
  test was performed.
- Existing untracked artifacts, private material, generated clients, and local
  worktrees were preserved and not staged.
- WireGuard remains the primary protocol. OpenVPN and IKEv2 are described below
  only at the level supported by source and local evidence.

## Current architecture map

```text
Browser / static site                         Flutter desktop/mobile client
static/*.html, static/js/*                   securewave_app/lib/*
        |                                             |
        | /api/* and /downloads/*                     | MethodChannel: securewave/vpn
        v                                             v
                         FastAPI control plane
 main.py -> routes/ + routers/ -> services/ -> models/ -> SQLAlchemy
       |                   |                  |              |
       |                   |                  |              +-- Alembic migrations
       |                   |                  +-- auth, billing, email, VPN profile logic
       |                   +-- downloads, VPN, auth, devices, diagnostics
       +-- mounts static/ and exposes health/readiness/download endpoints
                                                    |
                                                    | WireGuard/OpenVPN/IKEv2 profiles
                                                    v
Linux active path: GTK runner -> pkexec -> wg-quick / openvpn
Linux dormant path: helperd socket/service -> privileged helper contract v9
                         (currently no active runner IPC client)

Build / packaging / deployment:
GitHub Actions -> Python tests, Flutter Linux build, Docker image build
Docker + Compose -> FastAPI + PostgreSQL + Redis (runtime currently blocked)
Terraform + bootstrap -> Hetzner host/firewall (policy is internally inconsistent)
Website downloads -> manifest/API/static artifacts (artifact truth needs repair)
```

### Ownership boundaries

| Boundary | Current owner type | Components | Required contract |
| --- | --- | --- | --- |
| Control plane | Backend | `main.py`, `routes/`, `routers/`, `services/`, `models/` | Versioned API, schema migration ownership, explicit production startup gate. |
| Client state and UX | Flutter | `securewave_app/lib/` | Capability-aware protocol UX, no false connected state, stable API/profile parsing. |
| Native VPN bridge | Platform client | MethodChannel `securewave/vpn`, Linux/Android/iOS/Windows native code | Backward-compatible method and payload contract with per-protocol availability. |
| Linux privilege boundary | Linux/runtime | GTK runner, helperd, service, helper script, `.deb` | Authenticated socket contract, least privilege, route/state proof, cleanup semantics. |
| Artifact truth | Web/release | `static/downloads`, manifest, download API, package scripts | Architecture/version/availability must be attested before public claims. |
| Infrastructure | Platform/operations | Docker, Compose, Terraform, bootstrap, runbooks | One policy source for topology, ports, costs, database migration and host setup. |
| Release/security | Security/release owner | CI, secret scanning, signing, external credentials | No deployment/publication without scoped secrets and independently reviewed evidence. |

## Repository inventory

| Area | Tracked implementation | Baseline assessment |
| --- | --- | --- |
| Backend/API | FastAPI in `main.py`; `routes/`, `routers/`, `services/`, `models/`, `database/` | Broad mocked test coverage exists, but non-test import and fresh migrations are blocked. |
| Database | SQLAlchemy and Alembic `0001`–`0005` | Schema ownership is split between metadata creation and migrations; clean migration is broken. |
| Flutter | `securewave_app/`, Riverpod/Dio/secure storage, 24 Dart tests | Analyze, tests, Linux debug build verified; no native/integration test layer. |
| Linux VPN | GTK runner, helper daemon, helper script, service, `.deb`/AppImage recipes | Two divergent paths are tracked; helper service is not used by the active runner. |
| Protocol handling | Backend profile issuance plus Flutter/native handling | WireGuard is primary but live proof absent; OpenVPN is incomplete; IKEv2 correctly blocked in Linux UI. |
| Website/downloads | `static/`, API manifest fallback, tracked binaries | Static checks pass; artifact architecture/version/public-root truth has high-risk gaps. |
| Deployment | Dockerfiles, `deploy/hetzner/compose.yaml`, Terraform, bootstrap scripts | Syntax/config checks pass; fresh runtime/migration/IaC policy are unproven or contradictory. |
| Workflows | `ci-cd.yml`, Flutter/Linux evidence, Apple workflows | Useful build coverage but lacks critical runtime, migration, secret, IaC, and static checks. |
| Tests/artifacts/docs | `tests/`, `securewave-tests/`, `artifacts/`, docs/runbooks | Tests are mostly mocked/source-contract checks; docs and version sources drift. |

## Validated local baseline

| Check | Result | What it proves | What it does not prove |
| --- | --- | --- | --- |
| Tracked Python compile | **Verified pass** | Python syntax across tracked source. | Runtime imports, migrations, external services. |
| `scripts/run_backend_tests.sh` | **Verified pass: 288 tests** | Mocked FastAPI, SQLite, test auth/billing/profile/static contracts. | Non-test startup, PostgreSQL migration upgrade, real Redis, live VPN, payments, SMTP. |
| Flutter analyze/test/debug Linux build | **Verified pass: analyze; 24 tests; debug build** | Dart lint/type analysis, unit/widget behavior, GTK runner/helper daemon compilation. | Native platform invocation, package install, helper service, routing, live tunnels. |
| Website/UI/static JS/manifest checks | **Verified pass** | Tracked static assets, UI guard, JS syntax, JSON syntax. | Browser behavior, integrity/architecture of download binaries, public-host response. |
| All tracked shell syntax | **Verified pass** | Bash parseability of tracked shell files. | Script safety/effects at runtime. |
| Compose config with dummy values | **Verified pass** | Compose interpolation and YAML/config syntax. | Image execution, migrations, network/TLS, host configuration. |
| Clean staged Docker builds | **Verified pass** | Both Dockerfiles build from a clean ~51 MB staged archive; `.dockerignore` prevents the dirty worktree from becoming build context. | Non-test application import, migrations, container health, or public deployment. |
| Linux package contract tests | **Verified pass: 10 tests** | Source/package string-level helper contract assertions. | Runner-to-helper IPC, authorization, install/upgrade/purge, protocol runtime. |
| AppImage packaging | **Blocked locally** | — | `appimage-builder` is unavailable; no package command was run because it would overwrite local output. |
| Python lint/security tool | **Not implemented locally** | — | No tracked linter configuration; `gitleaks`, `shellcheck`, actionlint, and yamllint are absent. |

The reproducible local command is now `bash scripts/full_app_baseline.sh`.
It intentionally performs no deployment, package install, signing, publication,
or live network test. Redacted results live in `artifacts/full-app-baseline/`.

## Verified blockers and inconsistencies

### P0: backend startup, schema, and container path

- **Blocked — non-test app import.** With `TESTING=false`, importing `main`
  fails because the SlowAPI-decorated VPN profile handler lacks a `Request`
  argument. The 288 tests set `TESTING=true`, which turns the local rate-limit
  decorator into a no-op and masks the failure.
- **Blocked — fresh migrations.** A clean Alembic upgrade with metadata
  auto-create disabled reaches revision `0005` and fails because `audit_logs`
  was never created in the migration lineage. With normal development defaults,
  metadata creation happens before revision `0001`, which then fails because
  `users` already exists. CI creates metadata and stamps head, so it never
  exercises a real upgrade.
- **Implemented but unproven — Docker runtime.** Both Dockerfiles previously
  omitted direct runtime imports such as `routes/` and `utils/`; this baseline
  adds those source copies, ARM64 native build dependencies for `psutil`, and a
  contract test. Both images now build from a clean staged archive. Container
  startup is still blocked by the non-test import/migration defects, and CI
  only builds images.
- **Verified policy drift — database ownership.** `main.py`,
  `database/session.py`, local/bootstrap scripts, and Alembic all create or
  assume schema state. One migration owner must be selected before deployment.

### P0: public static/download and repository hygiene

- **Blocked — dirty-worktree static boundary.** FastAPI mounts all of `static/`.
  The local worktree has untracked/ignored historical Flutter/build trees and an
  ignored `static/.env` (contents were not read). Docker used to send/copy the
  full dirty context. This baseline adds `.dockerignore` exclusions, but the
  public-static allowlist/separation is still required before any deployment.
- **Blocked — artifact architecture truth.** The tracked
  `securewave-linux-x64.tar.gz` is declared available/x64 but contains an ARM64
  executable. `scripts/build_apps.sh` maps ARM hosts to the x64 label and writes
  that public filename. No availability was changed in this baseline.
- **Verified workflow contradiction repaired.** The manual x64 `.deb` evidence
  workflow required manifest status `coming_soon` while the manifest and unit
  test correctly say `beta`; its assertion now checks `beta` without changing
  any public artifact or status.
- **Verified version drift.** `VERSION` is `4.0.0`, `pubspec.yaml` is
  `4.0.0+1`, release status says `4.0.0+2`, and backend/download manifest
  sources use `1.0.0`.

### P1: protocol/runtime truth

| Protocol/path | Current status | Evidence and gap |
| --- | --- | --- |
| WireGuard/Linux | **Implemented but unproven** | Active runner calls `pkexec`/`wg-quick` and treats interface existence as connected. It has no helper-socket client. Local compile/source tests pass; routing, kill switch, cleanup, and live evidence do not. |
| WireGuard helperd | **Implemented but unproven** | Contract v9, service, socket, stronger route/XFRM checks, and package payload compile. Runner uses `securewave.conf`/`securewave`; helper expects `sw-wg.conf`/`sw-wg`, so it is not safely interchangeable. |
| OpenVPN/Linux | **Blocked** | Backend can issue a profile, but it uses `auth-user-pass` without an auth file; active runner also provides none and accepts a daemon PID after two seconds as success. Helper support is dormant. |
| IKEv2/Linux | **Blocked and correctly unavailable** | Backend excludes it from advertised Linux capability. Dormant backend/Dart/helper profile formats disagree and helper-required secret fields are absent. No signing/cert work was attempted. |
| Android/iOS/Windows OpenVPN/IKEv2 | **Not implemented truthfully** | Dart exposes protocols more broadly than native handlers implement; Android/iOS/Windows consume WireGuard configuration only. |
| Usage/rates | **Not implemented** | Flutter deliberately reports zero rates; no client traffic-counter or usage-report path is wired. |

### P1: packaging and operations

- **Implemented but unproven — Linux packages.** `.deb` packaging compiles and
  source tests assert payload metadata, but clean install, systemd socket,
  upgrades, purge, privileges, and tunnels are not proven. `postrm` and broad
  interactive-user authorization need a security/ownership review.
- **Blocked/unproven — external HTTPS topology.** Compose binds to localhost;
  bootstrap mentions nginx/certbot but the repository has no tracked virtual
  host/TLS config or backend systemd service.
- **Verified infrastructure policy drift.** Terraform sets `backups = true`,
  while `scripts/check_cost_guardrails.sh` requires false and defaults to the
  stale `infra/hetzner` directory. Terraform/docs allow `cx23` or `cx33`, while
  server sync rejects anything but `cx33`. Firewall/bootstrap protocol ports
  are also inconsistent.

### P2: organization and test debt

- `ARCHITECTURE.md` describes only a small FastAPI/static/WireGuard topology;
  it omits Flutter, MethodChannel, helperd, protocol and CI boundaries.
- `Dockerfile.simple`, `requirements_production.txt`, legacy deployment files,
  and multiple build scripts need ownership decisions before deletion.
- `scripts/check_plan_copy.sh` skips missing Flutter paths and exits zero; CI
  currently treats a no-op as coverage.
- `README.md` references a nonexistent `tests_real/`; release docs reference a
  nonexistent Flutter integration test. There is no tracked aggregate baseline
  script before this branch.

## Independently mergeable refactor PRs

This branch is **PR-00**. The remaining PRs must preserve the existing
`securewave/vpn` MethodChannel until compatibility tests authorize a migration.

| ID | Work and ownership | Depends on | Risk | Required evidence |
| --- | --- | --- | --- | --- |
| PR-00 | Baseline runner, redacted evidence, Docker context/source-copy contract, workflow assertion repair. Owners: platform + QA. | None | Low | Local baseline, static contract test, diff/secret checks. |
| PR-01 | Fix non-test FastAPI import and make rate-limit wiring single-source; add a non-test import/startup regression test. Owners: backend + security. | PR-00 | High | `TESTING=false` import/startup test, rate-limit request tests, no real credentials. |
| PR-02 | Make Alembic the sole schema owner; repair lineage and remove production metadata-create ambiguity. Owners: backend + database. | PR-01 | High | Fresh PostgreSQL `alembic upgrade head`, downgrade/upgrade policy, clean CI service test. |
| PR-03 | Add runnable-container health/static smoke after PR-01/02; converge/retire duplicate Dockerfile only after owner decision. Owners: platform + backend. | PR-01, PR-02 | High | Clean build context, container `/api/health`, `/api/ready`, `/downloads/manifest.json`, no production deployment. |
| PR-04 | Separate tracked public website assets from local/build content; establish one version/artifact manifest source. Owners: web + release + security. | PR-00 | High | Clean checkout/dirty-worktree deny tests, source-of-truth tests, no public status promotion. |
| PR-05 | Define and test a capability matrix for `securewave/vpn` across Flutter/Linux/Android/iOS/Windows. Disable unsupported choices until implemented. Owners: Flutter + platform. | PR-00 | High | MethodChannel compatibility fixtures, per-platform availability tests, UX error-state tests. |
| PR-06 | Move Linux WireGuard to helper socket deliberately, with a backward-compatible config/interface migration. Owners: Linux/runtime + Flutter. | PR-05 | High | Helper auth tests, route/DNS/interface proof, disconnect/cleanup/restart tests; no live claim without controlled evidence. |
| PR-07 | Define a redacted OpenVPN credential/profile contract and runtime status evidence. Owners: backend + Linux/runtime. | PR-05 | High | Profile fixture, auth-file lifecycle test, failure-path test, controlled tunnel proof. |
| PR-08 | Reconcile IKEv2 schema across backend/Dart/helper, then keep it unavailable until normal client-path proof exists. Owners: backend + Linux/runtime + security. | PR-05 | High | Parser/profile fixtures, capability-gate test, controlled strongSwan/XFRM lifecycle evidence. |
| PR-09 | Implement metering/status polling only after protocol contracts stabilize. Owners: Flutter + backend + Linux/runtime. | PR-06 | High | Counter sampling, restart/reconnect, double-count, and visible-meter tests. |
| PR-10 | Rework package metadata, architecture naming, upgrade/purge, and least-privilege user authorization. Owners: release + Linux/runtime. | PR-06–08 | High | Clean x64/arm64 VM install/upgrade/purge, helper socket, artifact SHA/architecture attestations. |
| PR-11 | Reconcile Terraform/bootstrap/Compose policy and add safe PR validation. Owners: platform + operations. | PR-02 | High | Terraform fmt/validate/cost policy, port/topology contract, no credentialed apply. |
| PR-12 | Add CI security/dependency/IaC scans and repair no-op/static checks. Owners: security + platform. | PR-00 | Medium | Gitleaks/config, dependency scan, shell/website/Compose checks, workflow semantic lint in CI. |
| PR-13 | Consolidate legacy scripts/docs/requirements after usage audit; update canonical architecture and release docs. Owners: maintainers. | PR-01–12 as applicable | Medium | Reference graph, deletion review, docs-to-command checks. |

## Dependency order

```text
PR-00 baseline
  -> PR-01 non-test import/rate limits
      -> PR-02 migrations
          -> PR-03 container runtime
          -> PR-11 IaC/Compose policy
  -> PR-04 static/download/version truth
  -> PR-05 capability matrix
      -> PR-06 WireGuard helper migration -> PR-09 metering
      -> PR-07 OpenVPN contract
      -> PR-08 IKEv2 schema/gate
      -> PR-10 packaging/privilege/artifact truth
  -> PR-12 CI/security scans
  -> PR-13 legacy consolidation (after ownership decisions)
```

## Required evidence gates

No item may be promoted from **implemented but unproven** based only on a
nearby unit test or workflow build. At minimum:

- Backend: non-test import plus fresh PostgreSQL migrations and an actual
  container health check.
- Protocol: backend-issued profile, client MethodChannel call, native runtime
  proof, disconnect/cleanup, and truthful error behavior.
- Packages: architecture attestation, clean VM install/upgrade/purge, helper
  authorization/socket evidence, and no public artifact status change without
  reviewed evidence.
- Infrastructure: Terraform/Compose policy validation and an operator-owned
  staging/host evidence path; no automatic production apply.
- Security: enforced secret/dependency/IaC checks with redacted outputs.

## Externally owned or intentionally blocked work

- VPN signing/certificate procurement and any production credential handling.
- SMTP/provider configuration and email delivery proof.
- Apple signing, notarization, and App Store release work.
- Production deployment, public download publication, and external load tests.
- Live Hetzner/API/VPN validation requiring operator-owned hosts, credentials,
  or accounts.

These remain blocked by design in this baseline and must be separately
authorized with redacted, scoped evidence.
