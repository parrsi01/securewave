## Operations Runbook

### CLI-only Phase 0 readiness

For a non-interactive, fail-closed readiness workflow that reconciles prior
evidence, runs local checks, validates one non-secret authorization packet, and
stops before provider sends or production mutation, use
[`docs/PHASE_0_CLI_READINESS_PROMPTS.md`](PHASE_0_CLI_READINESS_PROMPTS.md).

The prompt pack does not grant authorization, infer targets, create
credentials, deploy, send email, or prove live capacity. Keep the operator
packet outside the repository and do not place secrets in it.

### Codex CLI login and controlled operations

For the redacted historical login report, real-account login diagnostic,
allowlisted SendGrid or SMTP canary, and approval-gated staging/production wrapper, use
only `scripts/codex_cli_controller.py`. The controller accepts no arbitrary
command or script path. Its external operations require a non-secret operator
packet, injected runtime credentials, an exact target reference, a clean
candidate, and where applicable a short-lived one-use Ed25519 approval.

The login diagnostic uses `SECUREWAVE_API_BASE_URL`,
`SECUREWAVE_DIAGNOSTIC_EMAIL`, and `SECUREWAVE_DIAGNOSTIC_PASSWORD` from the
process environment. Do not put those values in this repository, the packet,
or a Codex prompt. The SendGrid canary uses only the injected
`EMAIL_PROVIDER=sendgrid`, `SENDGRID_API_KEY`, and `FROM_EMAIL` contract. Its
check-only mode never connects or sends, and its approved send mode never
treats provider submission acceptance as proof of inbox delivery. The legacy
SMTP canary remains available only when `EMAIL_PROVIDER=smtp` is explicitly
selected.

The legacy `scripts/live_flutter_runtime_smoke.py` also requires an explicit
`--target-ref` (or `SECUREWAVE_TARGET_REF`) and the same injected diagnostic
credentials. It checks an existing account by default; its registration step is
available only when the operator explicitly supplies `--register`. Prefer the
controller's `diagnose-login` operation for a redacted login-only check.

For exact package diagnosis, `reconcile-login-history` may also receive an
external `.deb` and an external launch log through `--deb-artifact` and
`--runtime-log`. It performs static inspection only; it does not install,
execute, contact the API, or treat a keyring warning as proof of an HTTP login
failure.

`deploy_production.sh` remains the production guard. `deploy_staging.sh` is a
separate explicit staging path; it exports `SECUREWAVE_ENVIRONMENT=staging`,
and the compose contract supplies `ENVIRONMENT=staging`, `DEMO_MODE=false`,
and `WG_MOCK_MODE=false`. Neither path bypasses Codex CLI sandbox permissions
or invents target credentials.

The staging wrapper accepts only these injected non-secret operation inputs:
`SECUREWAVE_STAGING_HOST`, `SECUREWAVE_STAGING_IMAGE`,
`SECUREWAVE_STAGING_USER`, `SECUREWAVE_STAGING_REMOTE_APP_DIR`, and
`CONFIRM_DEPLOY=securewave-staging`. The controller also requires
`SECUREWAVE_DEPLOY_TARGET_REFERENCE` to exactly repeat the approved inventory
reference in the packet and signed approval. The staging image must use a
complete `@sha256:` digest; a tag cannot be proven immutable by the controller
or wrapper. Production controller operations use the analogous
`SECUREWAVE_DEPLOY_TARGET_REFERENCE` and `SECUREWAVE_PRODUCTION_IMAGE` inputs,
while still invoking `deploy_production.sh`. The controller additionally
requires the packet candidate SHA, target/environment match, local release
guards, and a valid one-use signed approval before invoking either wrapper.
Before consuming an approval, it also checks the explicit environment
confirmation and the required host/path/user inputs for the selected wrapper;
these values are never written to controller evidence.
The staging wrapper itself also requires the controller-injected approval file,
public-key file, ledger file, current candidate SHA, and target reference; it
consumes the approval immediately before any remote mutation. These approval
variables are external paths/values, not repository configuration, and must
not be copied into the operator packet or a Codex prompt.

If the login diagnostic cannot reach its explicit target because of DNS, TLS,
or external-connectivity failure, the controller emits
`CONTROLLER_RESULT=BLOCKED_EXTERNAL_ACCESS` and preserves the more specific
diagnostic category in the redacted evidence. Missing local SSH/SCP tools are
reported with the same external-access blocker; the controller never attempts
to bypass the CLI sandbox.

### Daily Checks
1. Health endpoint: `/api/health`
2. Ready endpoint: `/api/ready`
3. Admin server health check: `/api/admin/servers/{server_id}/health-check`
4. Background workers: watch logs for "VPN Health Monitor started" and "Policy Engine Worker started"

### Common Maintenance
1. Reseed production server after restart:
   - `infrastructure/init_production_server.py` or `/api/admin/servers`
2. Rotate secrets:
   - `ACCESS_TOKEN_SECRET`, `REFRESH_TOKEN_SECRET`, `WG_ENCRYPTION_KEY`
3. Update runtime environment settings:
   - `WG_MOCK_MODE=false`, `DEMO_MODE=false`, `WG_AUTO_REGISTER_PEERS=true`
   - Omitted demo/mock flags default to real control-plane behavior; set them
     to `true` only in explicitly isolated tests.
4. Database storage:
   - Set `DATABASE_URL` to managed Postgres before production traffic.
   - If using SQLite in demo: use an explicitly configured persistent path.

### Incident Triage
1. App boot issues:
   - Check process and container logs for missing dependencies.
2. VPN allocation errors:
   - Verify server is registered and health check is green.
3. Peer registration failures:
   - Confirm SSH key path and VM connectivity.

### Data Persistence
1. Move DATABASE_URL to managed DB before production.
2. SQLite backup (demo only):
   - Copy `/home/site/securewave.db` to a safe location.
3. Postgres backup (production):
   - Use `pg_dump` with daily backups and weekly retention.
4. Restore test:
   - Restore a backup to a staging app monthly.

### Deploy and Rollback
1. Deploy: follow `docs/HETZNER_RUNBOOK.md`.
2. Rollback (fast): redeploy the previous known-good container or service revision.
3. Rollback (safe): restore the previous host/application snapshot and database backup.

### Monitoring
1. Stream application and systemd/container logs during deploys.
2. Alert on:
   - HTTP 5xx rate spikes
   - /health failures
   - VPN allocation errors
