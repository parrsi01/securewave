# SecureWave - Current Release Status

Last updated: 2026-08-30 UTC

## Local Linux ARM64 Beta candidate

- Branch: `codex/linux-beta-release-candidate`
- Candidate base before internal remediation: `9c5921af75dd2478cb6c57b33e26a088c410faba`
- Base: `origin/master` at `f558d0337d5bd20d52cb94e8112746a4d818ab99`
- Application/package version: `4.0.0+10`
- Existing package: `securewave_app/build/packaging/securewave-vpn_4.0.0+10_arm64.deb`
- Existing package SHA-256: `749e8c4e37fea27023d9030181e5cc36c46ff2e5d60e00519fa16082853d540a`
- Package metadata: `securewave-vpn`, version `4.0.0+10`, architecture `arm64`
- Embedded package source state: clean source at `a4fcf9419d98d6b4fd78e8806993fb499ac408a7`
- Helper contract: `13`
- The corrected package is represented independently in download metadata;
  public publication and external acceptance remain separate release actions.

The current automation changes do not rebuild the package or alter its bytes.
Backend deployments preserve the native systemd/Gunicorn release architecture.

## Intended scope

This candidate targets Ubuntu 24.04 ARM64 with the native Flutter Linux client,
the light SecureWave UI, one authenticated WireGuard server/runtime, and the
real backend/PostgreSQL path. The intended acceptance flow is registration,
login, connect, disconnect, reconnect/session restoration, and logout.

OpenVPN, IKEv2, payments, SMTP/email verification, additional server catalogs,
other architectures, and formal release governance are outside this Beta
candidate. The Debian package declares only the WireGuard/Linux runtime
dependencies and does not carry the legacy secondary-protocol payload files.

## `/api/downloads` root cause and remediation

The established repository contract is `GET /api/downloads`. The website client
requests that path, `routes/downloads.py` defines it, `main.py` mounts the router,
and the production Dockerfiles copy both `main.py` and `routes/` into the image.
The public `/downloads/manifest.json` URL remains a backward-compatible route;
it is not a replacement API contract.

The live service is not running this candidate backend. Read-only live evidence
returned version `4.0.0+9` and commit
`b741a21aa53c80825405cd1797993d0ebcfed734`. Repository inspection of that exact
commit shows the old slim Linux Beta entrypoint: it imports and mounts only the
auth and VPN routers, and that commit does not contain `routes/downloads.py`.
The live OpenAPI paths likewise omit every `/api/downloads` route. This is the
exact deployed-source mismatch behind the 404.

The deployment could remain nominally healthy because the image healthcheck
required only `/api/health`, while the Compose healthcheck required
`/api/health` and `/downloads/manifest.json`. Both paths return 200 from the old
slim image even though `/api/downloads` is absent.

The smallest backward-compatible remediation is applied locally:

- `Dockerfile` and `Dockerfile.simple` now require both `/api/health` and
  `/api/downloads` in their image healthchecks.
- `deploy/hetzner/compose.yaml` now requires `/api/downloads` in addition to the
  existing health and public-manifest checks.
- focused smoke and packaging-contract tests lock the endpoint and healthcheck
  expectations.
- `routes/downloads.py`, `main.py`, the website client, and the public manifest
  were not changed because their current contracts already agree.

## Legacy test reconciliation

The initial full Python run had 26 failures. They were classified as follows:

- 25 obsolete package-lifecycle expectations for OpenVPN, IKEv2, strongSwan,
  charon-nm, and legacy offline cleanup were removed or rewritten.
- 1 package-contract test was rewritten around the current WireGuard helper,
  systemd lifecycle, helper contract 13, and current Debian dependency line.
- No genuine regression was found.

The revised tests retain Bash syntax validation, dpkg rollback boundaries,
allowlist preservation, helper probing, systemd ownership, active `sw-wg`
removal protection, and the WireGuard-only Debian control contract. No excluded
protocol or dependency was restored.

## Verification evidence

- Focused downloads/API tests: 44 passed.
- Focused package lifecycle tests: 24 passed.
- Full Python suite: 778 passed, 2 skipped, 4 migration warnings.
- Linux and website contract tests: 384 passed.
- Candidate in-process API: `/api/downloads`, `/api/downloads/list`,
  `/api/downloads/detect`, and `/downloads/manifest.json` each returned 200.
- Local container image `securewave-downloads-remediation:local` built
  successfully as image
  `sha256:f33618e208dd7446a3779f02ab276d10065658acb2efcd0f09bfd0c76005f3af`.
- The local container's `/api/downloads` returned 200 with the expected
  `version`, `detected_platform`, and `downloads` fields and 10 manifest rows.
- Docker build-definition check: passed with no warnings.
- Compose YAML parse and healthcheck contract assertion: passed.
- Flutter analyzer: no issues.
- Flutter tests: 50 passed.
- Current light UI guard: passed.
- Release guards: passed.
- Repository hygiene: passed for 1,607 tracked files.
- Redacted tracked-source/config secret scan: passed; no values were printed.
- Tracked shell syntax, Python compile, and `git diff --check`: passed.
- Public manifest diff: unchanged.
- Existing package checksum and adjacent sidecar both verify as
  `9b170999845b6f53d22288058b314d42eda70938f4c1b37126ea20cef1ebc8fc`.

## Live endpoint boundary

Read-only verification on 2026-08-21 UTC produced:

- `https://api.securewaveapp.com/api/health`: HTTP 200,
  `service=securewave-linux-beta`.
- `https://api.securewaveapp.com/api/ready`: HTTP 200,
  `database=connected`.
- `https://api.securewaveapp.com/version`: version `4.0.0+9`, commit
  `b741a21aa53c80825405cd1797993d0ebcfed734`.
- `https://api.securewaveapp.com/openapi.json`: no `/api/downloads` paths.
- `https://api.securewaveapp.com/api/downloads`: HTTP 404 with the website HTML
  not-found page.
- `https://api.securewaveapp.com/downloads/manifest.json`: HTTP 200.

No deployment was authorized or performed, so the public endpoint remains 404.
Fixing it requires building an immutable backend image from the remediated
candidate source and deploying that image with the updated Compose template.
After deployment, the service must become healthy under the new contract and an
external unauthenticated GET to `/api/downloads` must return HTTP 200 with the
documented response fields. The deployed `/version` commit must also identify
the newly built source rather than `b741a21a...`.

## Deployment inputs prepared without deployment

- Existing mechanism: `scripts/deploy_production.sh`.
- Image input: `SECUREWAVE_PRODUCTION_IMAGE`, required and validated as an
  immutable tag or `@sha256` digest; no image reference was inferred.
- Host input: `SECUREWAVE_PRODUCTION_HOST`, required; optional existing inputs
  are `SECUREWAVE_PRODUCTION_USER` and `SECUREWAVE_REMOTE_APP_DIR` (default
  `/opt/securewave`).
- Confirmation gate: `CONFIRM_DEPLOY=securewave-production` is required by the
  script and was not supplied.
- Remote configuration: the existing remote `.env` must be non-empty; Compose
  requires the existing production environment values and `SECUREWAVE_IMAGE`.
  Values were not inspected or printed.
- Mechanism: copy the reviewed Compose template, pull the immutable image,
  run `docker compose --env-file .env config --quiet`, then `up -d --pull always`
  and `docker compose ps` on the authorized host.
- Rollback: use the previous known-good immutable application image through the
  same Compose `SECUREWAVE_IMAGE` input, following the existing operations
  runbook. No rollback action was run.
- Post-deployment proof: verify `/api/health`, `/api/ready`, `/api/downloads`,
  `/version`, and the new source identity externally; the updated Compose
  healthcheck also fails closed if `/api/downloads` is absent.

## Remaining release blockers

No internal pre-deployment blockers remain. Deployment, public endpoint
verification, clean-device installation, and authenticated VPN acceptance remain
intentionally pending because this task explicitly stops before those external
operations.

## Local inspection

```bash
cd /home/sp/cyber-course/projects/securewave-linux-beta-release-candidate/securewave_app
sha256sum build/packaging/securewave-vpn_4.0.0+10_arm64.deb
dpkg-deb -f build/packaging/securewave-vpn_4.0.0+10_arm64.deb \
  Package Version Architecture Depends
```
