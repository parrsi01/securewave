# Post-Merge Enterprise Release Evidence

Generated from `docs/POST_MERGE_ENTERPRISE_RELEASE_TODO.md` in read-only evidence mode.

## Current Checkout

- Branch: `master`
- Commit: `86a24679c98472f8b8d30045169c4d373367c86e`
- Production deploy run: no
- Terraform apply run: no
- External load test run: no
- Production state modified: no

## Checklist Status

| Checklist item | Status | Evidence |
| --- | --- | --- |
| Production Compose validation | blocked | `compose-dummy-config.status`, `compose-dummy-config.out`, `compose-temp-env-config.status`, `compose-temp-env-config.out` |
| Deploy guardrails | blocked | `guardrail-*.status`, `guardrail-*.out` |
| Hetzner fleet audit | blocked | `credential-presence.txt`, `hetzner-fleet-audit.status` |
| Authorized external load test | not run | `external-load-test-not-run.md` |
| x64 Linux `.deb` publication | blocked | `download-manifest-report.json`, `live-api-downloads.body` |
| Public download manifest verification | pass | `download-manifest-report.json`, `live-api-downloads.status` |
| Protocol documentation truth update | blocked | `protocol-doc-truth-scan.md` |
| Monitoring and alerting requirements | blocked | no deployed monitoring evidence or dashboard links available in this read-only run |
| Support/debug runbook | partially ready | existing docs were scanned, but post-release support runbook publication still needs final protocol/package evidence |
| Backend/API readiness where possible | pass | `pytest-downloads-vpn-profile.status`, `json-validation.status`, `python-compile.status`, `bash-syntax.status`, live API status files |

## Commands Run

```bash
git fetch origin
git status --short --branch
sed -n '1,240p' docs/POST_MERGE_ENTERPRISE_RELEASE_TODO.md
mkdir -p artifacts/post-merge-enterprise-release-evidence
git rev-parse HEAD
git branch --show-current
command -v docker || true
docker compose version || true
command -v terraform || true
command -v gh || true
command -v python3 || true
SECUREWAVE_IMAGE=ghcr.io/parrsi01/securewave:test POSTGRES_PASSWORD=dummy docker compose -f deploy/hetzner/compose.yaml config
SECUREWAVE_ENV_FILE=<temporary dummy env> SECUREWAVE_IMAGE=ghcr.io/parrsi01/securewave:test POSTGRES_PASSWORD=dummy docker compose -f deploy/hetzner/compose.yaml config --quiet
SECUREWAVE_PRODUCTION_HOST=prod.securewave.example SECUREWAVE_PRODUCTION_IMAGE=ghcr.io/parrsi01/securewave:test bash scripts/deploy_production.sh
SECUREWAVE_PRODUCTION_HOST=prod.securewave.example SECUREWAVE_PRODUCTION_IMAGE=ghcr.io/parrsi01/securewave:latest CONFIRM_DEPLOY=securewave-production bash scripts/deploy_production.sh
SECUREWAVE_PRODUCTION_IMAGE=ghcr.io/parrsi01/securewave:test CONFIRM_DEPLOY=securewave-production bash scripts/deploy_production.sh
SECUREWAVE_PRODUCTION_HOST=prod.securewave.example CONFIRM_DEPLOY=securewave-production bash scripts/deploy_production.sh
python3 -m json.tool static/downloads/manifest.json
pytest tests/unit/test_downloads_manifest.py tests/integration/test_vpn_profile.py -q
python3 -m json.tool artifacts/linux-enterprise-vpn-certification/smoke/*.json
python3 -m py_compile infrastructure/hetzner/audit_vpn_fleet.py
bash -n scripts/hetzner_bootstrap.sh
curl -fsS --max-time 20 https://api.securewaveapp.com/api/health
curl -fsS --max-time 20 https://api.securewaveapp.com/api/downloads
```

## Production Blockers

- `deploy/hetzner/compose.yaml` is not present on current `master`, so Compose validation is blocked before production env validation.
- `scripts/deploy_production.sh` is not present on current `master`, so deploy guardrail checks are blocked by missing script.
- `HETZNER_API_TOKEN`, `HCLOUD_TOKEN`, and `TF_VAR_hcloud_token` are unset, so the read-only Hetzner fleet audit was not run.
- `terraform` is not installed on PATH; no Terraform validation or apply was run.
- No external load-test authorization was provided in this prompt, so load testing was not run.

## x64 `.deb` Status

- Local `static/downloads/manifest.json`: Linux x64 `.deb` is `coming_soon`.
- Live `/api/downloads`: only Linux ARM64 `.deb` is advertised as available; no Linux x64 `.deb` is available.
- Result: blocked for x64 Linux `.deb` publication.

## Hetzner Audit Status

Blocked. Required token environment variables are unset, and no Hetzner API calls were attempted.

## External Load-Test Authorization Status

Not run. This read-only run recorded the command shape, required authorization, expected target, and safety limits in `external-load-test-not-run.md`.

## Protocol Documentation Truth Status

Blocked for final release truth update. Current docs still present WireGuard as primary/default, OpenVPN as limited or fallback, and IKEv2 as disabled, unavailable, or experimental. That may be truthful for current `master`, but it does not yet reflect final post-PR #15 production evidence.

## Final Recommendation

Partially ready. Local backend/download/profile checks, JSON validation, script compile, bash syntax, public health, and downloads probes passed. Release remains blocked on missing production deploy files on current `master`, missing Hetzner credentials, missing Terraform binary, unavailable Linux x64 `.deb`, missing external load-test authorization, and final protocol documentation truth updates.
