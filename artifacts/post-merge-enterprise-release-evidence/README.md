# Post-Merge Enterprise Release Evidence

Generated from `docs/POST_MERGE_ENTERPRISE_RELEASE_TODO.md` in read-only
evidence mode after PR #16 restored the Hetzner deploy files.

## Current Checkout

- Branch: `master`
- Commit: `69395a8a55bc15eda3fd1e815c94e60f6dfd2ff7`
- PR #16 status: merged
- Production deploy run: no
- Terraform apply run: no
- External load test run: no
- Production state modified: no
- Runtime/helper/protocol/app behavior modified: no

## Checklist Status

| Checklist item | Status | Evidence |
| --- | --- | --- |
| Hetzner deploy files restored | pass | `deploy/hetzner/compose.yaml` and `scripts/deploy_production.sh` exist on `master` |
| Production Compose validation | pass locally with dummy values | `compose-dummy-config.status`, `compose-dummy-config.out` |
| Deploy guardrails | pass | `guardrail-*.status`, `guardrail-*.out` |
| Hetzner fleet audit | blocked | `credential-presence.txt`, `hetzner-fleet-audit.status` |
| Authorized external load test | not run | `external-load-test-not-run.md` |
| x64 Linux `.deb` publication | blocked | `download-manifest-report.json` |
| Public download manifest verification | partial | `json-validation.status`, `download-manifest-report.json` |
| Protocol documentation truth update | blocked | `protocol-doc-truth-scan.md` |
| Monitoring and alerting requirements | blocked | no deployed monitoring evidence or dashboard links available in this read-only run |
| Support/debug runbook | partially ready | existing docs/TODOs exist, but final protocol/package evidence is still missing |
| Backend/download/profile validation | pass | `pytest-downloads-vpn-profile.status` |
| Script syntax/compile validation | partial | `bash-syntax.status`, `python-compile.status` |

## Commands Run

```bash
git fetch origin --prune
git switch master
git pull --ff-only origin master
sed -n '1,260p' docs/POST_MERGE_ENTERPRISE_RELEASE_TODO.md
sed -n '1,260p' artifacts/post-merge-enterprise-release-evidence/README.md
sed -n '1,260p' artifacts/post-merge-enterprise-release-evidence/blocker_resolution_plan.md
mkdir -p artifacts/post-merge-enterprise-release-evidence
test -f deploy/hetzner/compose.yaml
test -f scripts/deploy_production.sh
bash -n scripts/deploy_production.sh
SECUREWAVE_IMAGE=ghcr.io/parrsi01/securewave:test POSTGRES_PASSWORD=dummy SECUREWAVE_ENV_FILE=/dev/null docker compose -f deploy/hetzner/compose.yaml config
SECUREWAVE_PRODUCTION_HOST=prod.securewave.example SECUREWAVE_PRODUCTION_IMAGE=ghcr.io/parrsi01/securewave:test bash scripts/deploy_production.sh
SECUREWAVE_PRODUCTION_HOST=prod.securewave.example SECUREWAVE_PRODUCTION_IMAGE=ghcr.io/parrsi01/securewave:latest CONFIRM_DEPLOY=securewave-production bash scripts/deploy_production.sh
SECUREWAVE_PRODUCTION_IMAGE=ghcr.io/parrsi01/securewave:test CONFIRM_DEPLOY=securewave-production bash scripts/deploy_production.sh
SECUREWAVE_PRODUCTION_HOST=prod.securewave.example CONFIRM_DEPLOY=securewave-production bash scripts/deploy_production.sh
python3 -m json.tool static/downloads/manifest.json
git log --all --name-status -- static/downloads/securewave-linux-x64.deb
pytest tests/unit/test_downloads_manifest.py tests/integration/test_vpn_profile.py -q
python3 -m py_compile infrastructure/hetzner/audit_vpn_fleet.py scripts/linux_enterprise_vpn_certification.py
python3 -m py_compile infrastructure/hetzner/audit_vpn_fleet.py
bash -n scripts/hetzner_bootstrap.sh scripts/deploy_production.sh
git diff --check
git diff --cached --check
command -v terraform || true
uname -m
docker compose version
```

## PR #16 / Deploy Files

- PR #16 is merged into `master`.
- `deploy/hetzner/compose.yaml` exists on `master`.
- `scripts/deploy_production.sh` exists on `master`.
- `bash -n scripts/deploy_production.sh` passed.
- Docker Compose config passed with dummy values and
  `SECUREWAVE_ENV_FILE=/dev/null`.
- No production deploy was attempted.

## Deploy Guardrail Status

All guardrail probes failed closed before any SSH/SCP/deploy step:

- Missing `CONFIRM_DEPLOY`: exit code `2`, expected failure.
- Ambiguous `latest` image tag: exit code `2`, expected failure.
- Missing `SECUREWAVE_PRODUCTION_HOST`: exit code `2`, expected failure.
- Missing `SECUREWAVE_PRODUCTION_IMAGE`: exit code `2`, expected failure.

## Downloads Manifest Status

- `static/downloads/manifest.json` is valid JSON.
- Every manifest entry marked `available` has a matching local file.
- Local SHA-256 values were computed in `download-manifest-report.json`.
- The manifest has no checksum fields, and no checksum sidecar file exists under
  `static/downloads`, so checksum matching against repository metadata is blocked.
- Linux x64 `.deb` remains `coming_soon`.
- `static/downloads/securewave-linux-x64.deb` does not exist locally.
- Git history/object checks found no tracked `static/downloads/securewave-linux-x64.deb`
  file object.

## Hetzner Audit Status

Blocked. `HETZNER_API_TOKEN` and `HCLOUD_TOKEN` are unset. No Hetzner API calls
were attempted, and no token values were printed.

## Terraform Status

Blocked. `terraform` is unavailable on `PATH`. No Terraform validation and no
`terraform apply` were run.

## External Load-Test Status

Not run. No explicit authorization was provided for an external load test against
SecureWave-owned infrastructure.

## Linux x64 Build Environment

Blocked locally. The current host architecture is `aarch64`, so this checkout is
not a native Linux x64 package build/verification environment. The x64 `.deb`
publication remains a separate build, signing, publish, and clean-VM
verification task.

## Protocol Documentation Truth Status

Blocked for final release truth update. The scan found docs/download metadata
that still need reconciliation after final production evidence:

- `README.md`: IKEv2 is described as disabled in the Linux release UI.
- `docs/current_release_status.md`: IKEv2 is described as disabled/blocked.
- `docs/hr_app_process_overview/README.md`: IKEv2 is described as disabled in
  the Linux release app.
- `docs/guides/DESKTOP_THREE_PROTOCOL_PLAN.md`: OpenVPN/IKEv2 blocked-state
  language remains in the multi-protocol plan.
- `static/downloads/manifest.json`: Linux x64 `.deb` remains `coming_soon`.

The requested scan path `securewave_app/lib/core/release` is absent on current
`master`.

No protocol docs were edited in this pass.

## Local Validation Status

- `pytest tests/unit/test_downloads_manifest.py tests/integration/test_vpn_profile.py -q`: passed, 13 tests.
- `python3 -m py_compile infrastructure/hetzner/audit_vpn_fleet.py`: passed.
- `python3 -m py_compile infrastructure/hetzner/audit_vpn_fleet.py scripts/linux_enterprise_vpn_certification.py`: blocked because `scripts/linux_enterprise_vpn_certification.py` is absent on current `master`.
- `bash -n scripts/hetzner_bootstrap.sh scripts/deploy_production.sh`: passed.
- `git diff --check`: passed.
- `git diff --cached --check`: passed.

## Remaining Blockers

- Hetzner fleet audit requires `HETZNER_API_TOKEN` or `HCLOUD_TOKEN`.
- Terraform validation requires the `terraform` binary.
- External load testing requires explicit authorization.
- Linux x64 `.deb` is unavailable and remains `coming_soon`.
- Linux x64 `.deb` clean-VM install/connect/disconnect/uninstall proof is missing.
- Public checksum verification is blocked because the local manifest has no
  checksum fields or sidecar checksum file.
- Protocol docs still need the final truth update after production evidence.
- Monitoring and alerting evidence is not available from this read-only run.
- Final support/debug runbook publication still depends on final package and
  protocol evidence.

## Final Release Readiness

Blocked.

Local deploy-file restoration, dummy Compose validation, deploy guardrails,
download/profile tests, manifest JSON validation, and bash syntax checks are in
good shape. The release is still blocked by external credentials/tools,
authorization, x64 package publication, checksum evidence, and final
protocol/support/monitoring closeout evidence.
