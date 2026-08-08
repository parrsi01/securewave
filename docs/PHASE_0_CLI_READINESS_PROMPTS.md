# Codex CLI-only Phase 0 Readiness Prompt Pack

This runbook provides a non-interactive, Codex CLI-only workflow for
reconciling a prior Phase 0 report, running local readiness checks, validating
one operator authorization packet, and producing a fail-closed handoff.

It does **not** authorize deployment, SMTP, Terraform mutation, public URL
checks, live VPN traffic, or any other external mutation. Codex CLI can
validate supplied authorization and evidence; it cannot invent an accountable
owner, grant authorization, or prove target-specific capacity without an
authoritative target-specific record.

## Operating assumptions

- Run from `/Users/simonparris/Documents/securewave`, or replace that path with
  the actual repository root.
- Treat every prior report as external input until it is reconciled with the
  current checkout.
- Use a fresh **evidence run**, not a fresh Git repository, branch, or commit.
- Keep the operator packet outside the repository and free of secrets.
- Use read-only mode for discovery and gate evaluation.
- Use workspace-write mode only for local checks that may create ignored test
  caches or the non-secret Flutter environment asset.
- Never use `--dangerously-bypass-approvals-and-sandbox`.

## Canonical controller surface and branch policy

The repository has one operator-facing automation surface:
`scripts/codex_cli_controller.py`.  The controller exposes fixed operations
only; it does not accept arbitrary shell commands or arbitrary script paths.
The implementation helpers (`scripts/codex_local_e2e.py`,
`scripts/release_arm64.py`, and the local email provider) are not independent
deployment interfaces.

The GitHub repository is intentionally limited to three active branches:

1. `master` — the protected default branch;
2. `agent/securewave-model-reliability` — the current implementation branch;
3. `codex/linux-arm64-wireguard-beta-final` — the retained ARM64 beta branch.

Deleted branch tips are retained only as archive tags for audit/recovery; they
are not active branches.  Do not create a fourth long-lived branch.  A fresh
evidence directory or a new review run is preferred to another branch.

## Credentialless local lane

After the checkout is clean, the local lane is run through the controller:

```bash
cd /Users/simonparris/Documents/securewave
.venv/bin/python scripts/codex_cli_controller.py local-e2e \
  --evidence-dir /tmp/securewave-codex-local-evidence
```

It creates a temporary SQLite database outside the repository, applies the
existing Alembic migrations, seeds only non-production users in process, and
exercises the real login, `/auth/me`, session, refresh, logout, invalid
password, and unverified-account contracts.  It keeps `DEMO_MODE=false` and
`WG_MOCK_MODE=false` and uses `EMAIL_PROVIDER=local_capture` only with
`ENVIRONMENT=codex-local`.  The capture provider writes redacted evidence
outside the repository and never opens a network connection.  This lane is
not evidence of staging or production health.

The local package is explicitly non-production and must remain outside the
download manifest:

```bash
bash scripts/build_codex_local_deb.sh \
  --api-base http://127.0.0.1:<ephemeral-port>/api \
  --output-dir /tmp/securewave-codex-local-artifacts
```

The package is named `securewave-vpn-codex-local`, embeds a loopback API base,
forces mock API behavior off, and is never eligible for publication.

## ARM64 release operation

The fixed release surface is deliberately split into preflight and publish:

```bash
python3 scripts/codex_cli_controller.py release-arm64 \
  --mode preflight \
  --packet /external/securewave-release-authorization.txt \
  --artifact /external/securewave-arm64-release/securewave-vpn_arm64.deb \
  --evidence-dir /external/securewave-arm64-release-evidence
```

Publish mode requires the same exact candidate, an immutable ARM64 package
checksum, an independent signed approval, a production target, an immutable
backend image digest, a clean tree, and the external CI/ARM64 runtime
contracts.  Missing ARM64 tooling, GitHub/registry authorization, SSH access,
provider credentials, target-specific headroom evidence, or a proven fixed
image-builder contract is a blocker.  The controller does not replace those
external systems and does not guess them.  It also does not mark an ARM64
artifact available in `static/downloads/manifest.json` unless the exact
artifact and public verification evidence exist.

The local lane and the ARM64 release lane are separate profiles.  Production
packaging rejects loopback/HTTP API bases, Codex-local flags, dirty trees, and
mock mode.  The current production deployment guard remains the only
production deployment path.

## CLI invocation model

The installed Codex CLI supports `codex exec`, stdin prompts, `--sandbox`,
`--ephemeral`, `--json`, and `-C`.

### Read-only runs

```bash
cd /Users/simonparris/Documents/securewave

codex exec \
  --sandbox read-only \
  --ephemeral \
  -C /Users/simonparris/Documents/securewave \
  --json \
  - <<'PROMPT'
PASTE_PROMPT_HERE
PROMPT
```

### Local verification runs

Use workspace-write only when the selected checks may create ignored local
state:

```bash
cd /Users/simonparris/Documents/securewave

codex exec \
  --sandbox workspace-write \
  --ephemeral \
  -C /Users/simonparris/Documents/securewave \
  --json \
  - <<'PROMPT'
PASTE_PROMPT_HERE
PROMPT
```

The prompts below remain fail-closed even if the CLI is accidentally started
with broader permissions.

## Shared safety preamble

Prepend this preamble to every stage prompt.

```text
You are operating as a non-interactive Codex CLI readiness controller for SecureWave.

Repository root:
 /Users/simonparris/Documents/securewave

Read and obey:
- /Users/simonparris/Documents/securewave/AGENTS.md
- /Users/simonparris/Documents/securewave/SECURITY.md
- the repository coding-agent contract contained in AGENTS.md

This run is evidence collection and readiness evaluation only.

Before making any claim, run and record:
1. git status --short --branch
2. git rev-parse --show-toplevel
3. git rev-parse HEAD
4. git branch --show-current
5. rg --files
6. inspect the relevant source, scripts, and nearby tests directly

Do not:
- edit tracked files;
- apply patches;
- reset, clean, checkout, rebase, merge, commit, or amend Git history;
- fetch, pull, push, or rewrite refs;
- install packages or plugins automatically;
- use web search, external connectors, or desktop tools;
- invoke Terraform apply or destroy;
- invoke scripts/deploy_production.sh;
- send SMTP or provider email;
- run external load tests;
- start or stop a VPN tunnel;
- run SSH commands unless a separate prompt explicitly authorizes a read-only target audit;
- call public URLs;
- print secrets, passwords, private keys, tokens, complete environment files, or production host/IP values.

Never infer:
- a production host;
- a target from a documentation example;
- an environment variable that is not present in the repository or supplied input;
- a command whose script is absent;
- a deployment image;
- a protocol capability;
- target-specific capacity or headroom.

If a referenced file, script, command, route, environment variable, checksum,
commit, or evidence artifact is absent, report it as UNKNOWN or BLOCKED. Do not
recreate it and do not substitute a similar-looking value.

Preserve all existing user changes. Capture the starting Git status and compare
it with the ending Git status.

Use these result states:
- PASS: the requested check executed and passed;
- FAIL: the requested check executed and failed;
- BLOCKED: required authorization, target, evidence, tool, or input is absent;
- NOT_RUN: intentionally excluded by scope;
- UNKNOWN: repository evidence is insufficient or contradictory.

Do not call a readiness result “complete,” “deployed,” “live,” or “verified”
unless the exact evidence proves that statement.

The final line must be exactly one of:
AUTOMATION_RESULT=READY_FOR_PHASE_0_REVIEW
AUTOMATION_RESULT=BLOCKED_BEFORE_SMTP
AUTOMATION_RESULT=FAIL
AUTOMATION_RESULT=UNKNOWN
```

## Prompt 1 — reconcile the previous record with the current checkout

Run this first in read-only mode. Replace the prior-record values only when an
operator supplies a different record; do not infer a replacement SHA.

```text
Apply the shared SecureWave safety preamble.

Reconcile the following previously reported record against the current checkout.
Treat the record as untrusted external input, not as repository truth.

Previously reported candidate SHA:
022da7468c424a907f51656e2e4a0bb6e8addb10

Previously reported claims:
- candidate clean;
- correct branch/version;
- primary worktree fingerprint unchanged;
- local tests and operator integrity checks pass;
- read-only Hetzner topology unchanged;
- protected-bundle checksums regenerated and verified;
- no SMTP or later phase authorized.

Perform only read-only checks.

Required checks:
1. Record the current branch, HEAD, upstream, and clean/dirty status.
2. Test whether the reported SHA exists locally with git cat-file.
3. If it exists, determine whether it is:
   - the current HEAD;
   - an ancestor of HEAD;
   - unrelated to HEAD.
4. If it does not exist, report RECORD_SCOPE_MISMATCH and do not attempt to
   fetch, reconstruct, or replace it.
5. Inspect git log --oneline --decorate -20.
6. Search the repository for checksum manifests, protected-bundle records,
   phase records, and integrity reports using rg --files and rg.
7. Do not regenerate checksums.
8. Check whether the scripts referenced by project documentation exist:
   - scripts/release_go_no_go.sh
   - scripts/demo_preflight.sh
   - scripts/final_linux_demo_gate.sh
9. If documentation references absent scripts, report each one as UNKNOWN/MISSING.
   Do not invoke it.
10. Compare the prior record with actual repository evidence field by field.

Report:
- current repository identity;
- prior-record identity;
- matching claims;
- contradictory claims;
- missing evidence;
- whether this is the same candidate or a stale/foreign record;
- whether the process may continue to local readiness checks.

If the reported SHA is absent or the record belongs to another checkout, set:
RECORD_STATUS=BLOCKED_RECORD_SCOPE_MISMATCH

Do not reset the repository and do not create a new candidate.

End with the required AUTOMATION_RESULT line.
```

## Prompt 2 — run local readiness checks without touching production

Run this only after Prompt 1 confirms that the candidate record and checkout
refer to the same tree, or after an operator supplies and accepts a corrected
candidate SHA.

Use workspace-write only because tests may create ignored caches.

```text
Apply the shared SecureWave safety preamble.

Run a local-only readiness pass. This pass must not contact production, SMTP,
Hetzner, Terraform, Docker registries, or public URLs.

Before running checks:
1. Capture git status --short --branch.
2. Check whether /Users/simonparris/Documents/securewave/securewave_app/.env
   already exists.
3. Do not overwrite an existing securewave_app/.env.
4. Inspect each script before invoking it.
5. Do not run any script that is absent.

Run these existing local checks where the required files and tools exist:

1. git diff --check

2. python3 -m py_compile main.py

3. bash scripts/verify_release_guards.sh

4. python3 scripts/check_repository_hygiene.py

5. python3 scripts/scan_repository_secrets.py

6. bash scripts/verify_website.sh

7. Backend tests without automatic dependency installation:
   PYTHON_BIN=python3
   SKIP_INSTALL=true
   bash scripts/run_backend_tests.sh

For each command record:
- exact command;
- whether the command existed;
- exit code;
- PASS, FAIL, BLOCKED, or NOT_RUN;
- concise relevant output;
- no secret values.

Flutter checks:
- If securewave_app/.env is absent, do not create it unless the operator
  explicitly authorizes creation of the repository’s non-secret Flutter
  environment asset.
- If authorized, use only the existing helper:
  bash scripts/prepare_flutter_env.sh
- Never use FORCE_FLUTTER_ENV=true when an existing securewave_app/.env is present.
- If Flutter is available and the environment asset is safely available, run:
  cd securewave_app && flutter analyze
  cd securewave_app && flutter test --reporter compact
- If Flutter or the environment asset is unavailable, report BLOCKED or NOT_RUN.
  Do not install Flutter or dependencies automatically.

Do not run scripts/certify_repository.sh automatically if doing so would
overwrite an existing securewave_app/.env. Inspect that script first and
explain the reason if it is skipped.

After all checks:
1. Run git status --short --branch again.
2. Confirm that no tracked files changed.
3. Identify any ignored files created by the check.
4. Do not delete, reset, or overwrite pre-existing ignored files.

Do not interpret local tests as proof of:
- production health;
- target capacity;
- SMTP delivery;
- live VPN traffic;
- Hetzner topology;
- production deployment.

End with the required AUTOMATION_RESULT line.
```

The existing `scripts/certify_repository.sh` is described as a maximum-safe
local certification script, but it invokes `FORCE_FLUTTER_ENV=true`. Do not
run it when doing so would overwrite a pre-existing ignored Flutter environment
file.

If the environment is known not to contain user-owned ignored files, the
aggregate certification may be run only after inspecting the script:

```text
After inspecting scripts/certify_repository.sh and confirming that no
pre-existing user-owned ignored files will be overwritten, run:

PYTHON_BIN=python3 bash scripts/certify_repository.sh

Preserve its distinction between:
- failures;
- blockers caused by unavailable tools;
- passed checks.

Do not convert blockers into passes.
```

## Prompt 3 — create and validate one authorization input packet

Do not provide missing authorization values as scattered chat messages. Put
them in one non-secret operator packet outside the repository, for example:

```text
/Users/simonparris/Documents/securewave-phase0-authorization.txt
```

This is an operator-input format for the CLI workflow. It is not a SecureWave
runtime configuration file.

Use this structure and fill it with approved values before validation:

```text
packet_version=2

accountable_owner=
approver_role=

authorized_target_reference=
environment=
production_excluded=

operator=
reviewer=
evidence_owner=

authorization_window_start_utc=
authorization_window_end_utc=

headroom_evidence_reference=
headroom_result=

candidate_sha=
original_expected_sha=
# Use exactly one: same_candidate, accept_promoted_candidate,
# or require_original_expected_sha.
sha_acceptance_decision=
api_base_fingerprint=

email_provider=sendgrid
allowed_operations=login_diagnostic,sendgrid_check,sendgrid_canary
sendgrid_recipient_allowlist=
smtp_recipient_allowlist=
approval_public_key_file=
approval_ledger_file=

authorized_scope=phase0_readiness_only
not_authorized=mock_login,email_verification_bypass,2fa_bypass,SMTP_without_approval,email_without_approval,production_deploy,later_phases
read_only_external_audit_authorized=false
```

Do not put passwords, API tokens, SSH private keys, SMTP credentials, or
complete `.env` contents in this packet.

```text
Apply the shared SecureWave safety preamble.

Read the operator packet at:

/Users/simonparris/Documents/securewave-phase0-authorization.txt

Do not invent or fill any blank field.

Validate the packet as a fail-closed Phase 0 readiness input.

Required fields:
- accountable_owner;
- approver_role;
- authorized_target_reference;
- environment;
- production_excluded;
- operator;
- reviewer;
- evidence_owner;
- authorization_window_start_utc;
- authorization_window_end_utc;
- headroom_evidence_reference;
- headroom_result;
- candidate_sha;
- original_expected_sha;
- sha_acceptance_decision.
- api_base_fingerprint;
- allowed_operations;
- approval_public_key_file;
- approval_ledger_file.

Validation rules:
1. Blank values are invalid.
2. Values such as TBD, unknown, later, soon, n/a, or to-be-decided are
   invalid for required fields.
3. production_excluded must be explicitly true.
4. authorized_target_reference must be a specific approved inventory/reference
   identifier, not a guessed hostname, IP address, URL, or vague word such as
   staging.
5. The authorization window must contain an explicit UTC start and end.
6. The current time must be compared with the window. If outside the window,
   report BLOCKED.
7. headroom_evidence_reference must refer to target-specific evidence. A
   general cost guardrail, repository test, or Hetzner documentation statement
   is not sufficient.
8. headroom_result must state the observed result, not merely that someone
   believes capacity is sufficient.
9. candidate_sha must exist locally and must be compared with the
   current HEAD.
10. If candidate_sha differs from original_expected_sha,
    sha_acceptance_decision must explicitly state whether the promoted
    candidate is accepted or the original SHA is required.
11. A missing or contradictory SHA decision is BLOCKED.
    The controller packet uses `same_candidate`,
    `accept_promoted_candidate`, or `require_original_expected_sha`.
12. authorized_scope must remain phase0_readiness_only.
13. SMTP, production deployment, Terraform apply, public URL verification, and
    later phases must remain explicitly unauthorized.
14. Do not print or inspect secret values.
15. Do not contact the target.
16. api_base_fingerprint must be a SHA-256 fingerprint of the explicit API
    base supplied through the execution environment; do not put the URL in
    this packet.
17. allowed_operations must use only repository-defined controller operations.
18. approval_public_key_file and approval_ledger_file must point outside the
    repository. Private signing keys must not be present.

For every field output:
- PRESENT and valid;
- PRESENT but contradictory;
- MISSING;
- UNKNOWN.

Do not mark the packet authorized merely because all fields are syntactically
present. State whether the packet is sufficient for review.

Use:
PACKET_STATUS=VALID_FOR_REVIEW
or:
PACKET_STATUS=BLOCKED

End with the required AUTOMATION_RESULT line.
```

## Prompt 4 — optional read-only Hetzner evidence collection

Use this only if the packet contains:

```text
read_only_external_audit_authorized=true
```

This does not authorize deployment, SSH mutation, SMTP, or Terraform changes.

```text
Apply the shared SecureWave safety preamble.

Read and validate:
 /Users/simonparris/Documents/securewave-phase0-authorization.txt

Proceed only if:
1. PACKET_STATUS is valid for review;
2. authorized_target_reference is present;
3. production_excluded=true;
4. read_only_external_audit_authorized=true;
5. the packet explicitly authorizes a read-only Hetzner audit.

If any condition is false, stop with BLOCKED_EXTERNAL_AUDIT_NOT_AUTHORIZED.

Inspect:
- /Users/simonparris/Documents/securewave/infrastructure/hetzner/audit_vpn_fleet.py
- /Users/simonparris/Documents/securewave/docs/HETZNER_RUNBOOK.md
- /Users/simonparris/Documents/securewave/scripts/check_cost_guardrails.sh

Never print:
- HETZNER_API_TOKEN;
- TF_VAR_hcloud_token;
- SSH private-key contents;
- raw production hostnames;
- public or private IP addresses;
- complete raw audit output.

Check only whether HETZNER_API_TOKEN is present. Do not print its value.

If the existing audit script and token are available, run only the non-SSH
read-only audit, capturing all raw output into a temporary location outside the
repository. Use the existing script and documented arguments only. Do not add
--ssh-checks unless a separate explicit authorization exists.

The allowed audit shape is:

python3 infrastructure/hetzner/audit_vpn_fleet.py \
  --only-running \
  --json-out <temporary-output-path>

Redirect stdout and stderr so raw server identifiers and IP addresses are not
displayed. Summarize only:
- command exit code;
- total server count;
- running server count;
- firewall-validation count;
- private-network count;
- reverse-DNS count;
- whether backend comparison was available;
- whether the exact authorized target could be matched.

Do not treat this audit as target-specific headroom proof. The repository audit
script reports fleet state and validation fields; it does not establish the
missing approval or capacity attestation by itself.

If HETZNER_API_TOKEN is absent, report:
HETZNER_AUDIT_STATUS=BLOCKED_TOKEN_NOT_PRESENT

If the target cannot be matched exactly, report:
HETZNER_AUDIT_STATUS=BLOCKED_TARGET_NOT_MATCHED

If the audit succeeds, report:
HETZNER_AUDIT_STATUS=PASS_READ_ONLY_ONLY

Do not modify infrastructure, database state, server state, firewall state, or
repository files.

End with the required AUTOMATION_RESULT line.
```

The repository audit script can produce fleet evidence, but it does not prove
target-specific headroom. The packet must still contain separate approved
headroom evidence. Likewise, `scripts/check_cost_guardrails.sh` validates
static Terraform cost constraints; it is not a live capacity proof.

## Prompt 5 — final Phase 0 gate evaluation

Run this after reconciliation, local checks, and packet validation.

```text
Apply the shared SecureWave safety preamble.

Evaluate whether the current evidence is sufficient for Phase 0 review. This
is a gate evaluation only. Do not deploy, send SMTP, contact public URLs, run
Terraform, or modify the target.

A result of READY_FOR_PHASE_0_REVIEW is allowed only when all conditions below
are true:

1. The current repository identity is known.
2. The current HEAD is known.
3. The candidate SHA accepted by the packet exists locally.
4. The candidate SHA matches the current HEAD, or the packet contains an
   explicit acceptance decision for the promoted HEAD.
5. The SHA relationship is not being inferred.
6. The starting and ending worktree statuses are known.
7. No tracked user changes were overwritten.
8. Required local checks either passed or have an explicitly accepted
   non-blocking status.
9. Any unavailable tool is reported as BLOCKED or NOT_RUN, not silently
   ignored.
10. The accountable owner is explicit.
11. The approver role is explicit.
12. The target reference is explicit and exact.
13. production_excluded=true is explicit.
14. Operator, reviewer, and evidence owner are explicit.
15. The authorization window is present and currently valid.
16. Target-specific headroom evidence is present and attributable.
17. The packet explicitly excludes SMTP, production deployment, Terraform apply,
    and later phases.
18. No required evidence comes solely from documentation examples or
    historical reports.
19. No current record contradiction remains unresolved.
20. The current checkout is not being confused with a different branch or
    worktree.

If any condition fails:
- report the exact failed condition;
- identify the minimum missing input;
- do not suggest resetting or rebuilding the repository;
- do not start SMTP;
- do not call the result a release approval.

Use these final classifications:
- READY_FOR_PHASE_0_REVIEW: evidence packet is complete enough for accountable
  human review; no external mutation has occurred.
- BLOCKED_BEFORE_SMTP: one or more authorization, target, evidence, SHA, or
  tool prerequisites remain unresolved.
- FAIL: an executed check failed.
- UNKNOWN: the evidence sources contradict each other and cannot be reconciled
  locally.

The result must not say:
- production is ready;
- deployment occurred;
- SMTP works;
- the public URL changed;
- live VPN behavior is proven.

End with the required AUTOMATION_RESULT line.
```

`READY_FOR_PHASE_0_REVIEW` is not `PHASE_0_COMPLETE`. The CLI can assemble and
validate evidence; it cannot become the accountable owner or grant
authorization.

## Prompt 6 — generate the final handoff report

Use this after the final gate.

```text
Apply the shared SecureWave safety preamble.

Generate a concise, audit-friendly handoff report using exactly these headings:

Changed:
- State whether repository files changed.
- State whether external systems changed.
- Do not claim a change unless a command proves it.

Verified:
For every executed check, list:
- exact command;
- result: PASS, FAIL, BLOCKED, NOT_RUN, or UNKNOWN;
- exit code if available;
- relevant evidence path or source;
- a one-sentence interpretation.

Blocked:
List only genuine remaining blockers.
For each blocker include:
- blocker identifier;
- why it cannot be resolved from repository evidence;
- the exact operator input or external evidence required;
- whether it prevents SMTP or later phases.

Record Integrity:
- repository root;
- branch;
- HEAD;
- starting worktree status;
- ending worktree status;
- candidate SHA;
- original expected SHA;
- explicit SHA acceptance decision;
- whether the current record matches this checkout.

External-System Status:
- deployment: NOT_RUN;
- SMTP: NOT_RUN;
- Terraform mutation: NOT_RUN;
- public URL verification: NOT_RUN;
- live VPN mutation: NOT_RUN.

Do not print secrets, tokens, passwords, private keys, complete environment
files, raw provider output, or production host/IP values.

If any Phase 0 blocker remains, include exactly:
BLOCKED_BEFORE_SMTP

Do not use the words deployed, live, fixed, complete, or verified for a
behavior unless the listed command or tool output proves that specific
statement.

End with the required AUTOMATION_RESULT line.
```

## Resume prompt after the packet is corrected

When the missing owner, target, attestations, roles, time window, evidence
owner, headroom reference, and SHA decision are supplied, use this instead of
starting over:

```text
Apply the shared SecureWave safety preamble.

Resume the existing Phase 0 review from the frozen candidate. Do not create a
fresh branch, rebuild the candidate, regenerate checksums, or rewrite Git
history.

First reconcile:
- current branch;
- current HEAD;
- current worktree status;
- accepted_candidate_sha in the operator packet;
- original_expected_sha in the operator packet;
- the prior evidence record.

If the current HEAD, checksum identity, or worktree state differs from the
previously reviewed candidate, stop with:
RESUME_STATUS=BLOCKED_CANDIDATE_CHANGED

If the candidate is unchanged:
1. revalidate the operator packet;
2. rerun only the required local checks whose evidence is stale or missing;
3. preserve prior passing evidence that still matches the same candidate;
4. evaluate the final Phase 0 gate;
5. do not start SMTP or any later phase.

Do not treat the existence of a corrected packet as proof that its contents are
authorized. Report the supplied authorization fields and their validation
status without inventing approval.

End with the required AUTOMATION_RESULT line.
```

## What Codex CLI can and cannot automate

Codex CLI can automate:

- repository and branch reconciliation;
- stale-record detection;
- SHA and ancestry checks;
- checksum-manifest discovery;
- detection of absent scripts;
- local syntax checks;
- backend tests;
- website and release guard checks;
- repository hygiene and secret scans;
- non-secret tool-presence checks;
- optional read-only infrastructure audit;
- structured blocker reporting;
- repeatable Phase 0 gate evaluation;
- final handoff reports.

Codex CLI cannot legitimately invent or replace:

- the accountable owner;
- the approver;
- authorization to use a target;
- production exclusion;
- an authorization window;
- evidence ownership;
- target-specific capacity/headroom;
- acceptance of a promoted commit whose SHA differs from the expected SHA;
- SMTP credentials;
- production credentials;
- deployment authorization.

## Recommended operating sequence

1. Run Prompt 1 to reconcile the previous report.
2. Run Prompt 2 for local checks.
3. Fill the single operator packet outside the repository.
4. Run Prompt 3 to validate the packet.
5. Optionally run Prompt 4 for explicitly authorized read-only target evidence.
6. Run Prompt 5 to evaluate the Phase 0 gate.
7. Run Prompt 6 to generate the handoff report.
8. If the packet is corrected later, use the resume prompt rather than
   restarting the repository.

## Codex CLI-only login diagnosis and authorized operations

The following controller is the only supported command surface for the new
login diagnostic, provider canaries, and staging/production operation workflow:

```text
python3 scripts/codex_cli_controller.py reconcile-login-history --evidence-dir <external-dir>
python3 scripts/codex_cli_controller.py diagnose-login --packet <external-packet> --evidence-dir <external-dir>
python3 scripts/codex_cli_controller.py smtp-canary --mode check-only --packet <external-packet> --evidence-dir <external-dir>
python3 scripts/codex_cli_controller.py smtp-canary --mode send --recipient <approved-recipient> --packet <external-packet> --approval-file <external-approval> --evidence-dir <external-dir>
python3 scripts/codex_cli_controller.py sendgrid-canary --mode check-only --packet <external-packet> --evidence-dir <external-dir>
python3 scripts/codex_cli_controller.py sendgrid-canary --mode send --recipient <approved-recipient> --packet <external-packet> --approval-file <external-approval> --evidence-dir <external-dir>
python3 scripts/codex_cli_controller.py deploy --environment staging --packet <external-packet> --approval-file <external-approval> --evidence-dir <external-dir>
python3 scripts/codex_cli_controller.py deploy --environment production --packet <external-packet> --approval-file <external-approval> --evidence-dir <external-dir>
```

Do not put the API URL, login email, login password, SMTP credentials, SSH
keys, approval private key, or raw provider output in a Codex prompt. Inject
runtime credentials through the process environment. The diagnostic uses:

```text
SECUREWAVE_API_BASE_URL
SECUREWAVE_DIAGNOSTIC_EMAIL
SECUREWAVE_DIAGNOSTIC_PASSWORD
```

The legacy SMTP canary uses the existing `EMAIL_PROVIDER`, `SMTP_HOST`,
`SMTP_PORT`, `SMTP_USER`, `SMTP_PASSWORD`, and `FROM_EMAIL` environment
contract. The SendGrid canary instead requires `EMAIL_PROVIDER=sendgrid`,
`SENDGRID_API_KEY`, and `FROM_EMAIL`; SMTP variables are not required. Both
check-only modes never connect or send. Both send modes are available only
through the controller after a valid, non-expired, non-replayed Ed25519
approval is consumed.

The approval verifier reads only an externally provisioned Ed25519 public key;
it does not generate signing keys or approvals. The private signing key and
the independent approval decision must remain outside the repository and
outside the unattended Codex process. A certificate or mTLS path is not
invented because the current repository does not establish such a target
contract.

The controller does not provide an arbitrary command passthrough and does not
override Codex CLI sandbox permissions. Missing network, SSH, SMTP, target,
credential, image, or approval access remains `BLOCKED`.

For a deployment operation, inject the exact non-secret target reference again
as `SECUREWAVE_DEPLOY_TARGET_REFERENCE`; it must match the packet and signed
approval byte-for-byte. Staging additionally requires
`SECUREWAVE_STAGING_HOST`, `SECUREWAVE_STAGING_IMAGE`,
`SECUREWAVE_STAGING_USER`, `SECUREWAVE_STAGING_REMOTE_APP_DIR`, and
`CONFIRM_DEPLOY=securewave-staging`. The staging image must be a complete
`@sha256:<64-hex-digest>` reference. Production operations use
`SECUREWAVE_PRODUCTION_IMAGE` and the existing production environment contract
while still invoking `scripts/deploy_production.sh`. Do not put these values in
the packet or prompt; inject them into the process environment.

Use this prompt for a read-only login provenance run:

```text
Read and obey:
- /Users/simonparris/Documents/securewave/AGENTS.md
- /Users/simonparris/Documents/securewave/SECURITY.md
- /Users/simonparris/Documents/securewave/docs/PHASE_0_CLI_READINESS_PROMPTS.md

Do not edit tracked files, contact external systems, print secrets, or infer a
target. Run only:

python3 scripts/codex_cli_controller.py reconcile-login-history \
  --evidence-dir /tmp/securewave-login-history

Report the exact exit code and evidence path. End with one of the required
AUTOMATION_RESULT values from the shared safety preamble.
```

When an exact external `.deb` and a separately captured launch log are
available, add them to the same read-only operation:

```text
python3 scripts/codex_cli_controller.py reconcile-login-history \
  --deb-artifact /tmp/securewave-linux-x64.deb \
  --runtime-log /tmp/securewave-linux-launch.log \
  --evidence-dir /tmp/securewave-login-history
```

When the installed package tree is available as a separately authorized local
filesystem root, add `--installed-root /path/to/installed-root`. The comparison
is limited to the fixed application wrapper and executable paths, records only
redacted hashes and match flags, and never executes or mutates the installed
files. If no root is supplied, the report must keep the installed-file result
`UNKNOWN`; package inspection alone is not proof that the installed files match
the downloaded artifact.

The controller inspects the package without installing or executing it. The
report records only package identity, architecture, source-SHA relationship,
API-value fingerprints, auth-route markers, secure-storage presence, native
`libsecret-1.so.0` linkage, whether the Debian package declares the matching
`libsecret-1-0` runtime dependency, and safe runtime signal flags. It never
copies package strings, hostnames, account values, tokens, or raw launch-log
text into evidence.

Use this prompt for an explicitly authorized staging login diagnostic:

```text
Read and obey:
- /Users/simonparris/Documents/securewave/AGENTS.md
- /Users/simonparris/Documents/securewave/SECURITY.md
- /Users/simonparris/Documents/securewave/docs/PHASE_0_CLI_READINESS_PROMPTS.md
- /Users/simonparris/Documents/securewave-phase0-authorization.txt

Do not invent a target, URL, account, password, approval, or headroom result.
Do not print secrets, tokens, raw response bodies, or production host/IP
values. Do not register an account, bypass email verification, bypass 2FA,
send SMTP, deploy, run Terraform, or use an arbitrary command passthrough.

The shell environment must already contain the approved target's:
SECUREWAVE_API_BASE_URL, SECUREWAVE_DIAGNOSTIC_EMAIL, and
SECUREWAVE_DIAGNOSTIC_PASSWORD. The URL fingerprint must match the external
operator packet.

Run only:

python3 scripts/codex_cli_controller.py diagnose-login \
  --packet /Users/simonparris/Documents/securewave-phase0-authorization.txt \
  --evidence-dir /tmp/securewave-login-diagnostic

Return the controller result, exact exit code, and redacted evidence path.
End with exactly one AUTOMATION_RESULT value from the shared safety preamble.
```

Use this prompt for an explicitly authorized controller operation. Replace the
operation command only with one of the listed controller commands; do not add
shell commands, script paths, or free-form arguments not required by that
command.

```text
You are operating as the SecureWave Codex CLI controller.

Read and obey:
- /Users/simonparris/Documents/securewave/AGENTS.md
- /Users/simonparris/Documents/securewave/SECURITY.md
- /Users/simonparris/Documents/securewave/docs/PHASE_0_CLI_READINESS_PROMPTS.md
- /Users/simonparris/Documents/securewave-phase0-authorization.txt

Do not invent credentials, hosts, target references, image references,
recipient values, approval values, or evidence.

Do not:
- use --dangerously-bypass-approvals-and-sandbox;
- bypass a project guard;
- print secrets, tokens, passwords, private keys, raw provider output, or
  production host/IP values;
- modify authentication behavior;
- enable mock login in a release build;
- bypass email verification or 2FA;
- register an account for a login diagnosis;
- invoke Terraform mutation;
- run an arbitrary shell command or arbitrary script path;
- send SMTP or SendGrid email without the controller's signed-approval path;
- deploy without a valid, non-expired, non-replayed signed approval.

The process environment must already contain only the externally authorized
runtime values required by the selected operation. Keep credentials and
private signing keys outside the packet and prompt.

Run exactly one of these controller operations, with the externally supplied
packet, evidence directory, and—when required—approval file:

python3 scripts/codex_cli_controller.py smtp-canary \
  --mode check-only \
  --packet /Users/simonparris/Documents/securewave-phase0-authorization.txt \
  --evidence-dir /tmp/securewave-smtp-check

python3 scripts/codex_cli_controller.py smtp-canary \
  --mode send \
  --recipient <approved-recipient> \
  --packet /Users/simonparris/Documents/securewave-phase0-authorization.txt \
  --approval-file <external-approval-file> \
  --evidence-dir /tmp/securewave-smtp-canary

python3 scripts/codex_cli_controller.py sendgrid-canary \
  --mode check-only \
  --packet /Users/simonparris/Documents/securewave-phase0-authorization.txt \
  --evidence-dir /tmp/securewave-sendgrid-check

python3 scripts/codex_cli_controller.py sendgrid-canary \
  --mode send \
  --recipient <approved-recipient> \
  --packet /Users/simonparris/Documents/securewave-phase0-authorization.txt \
  --approval-file <external-approval-file> \
  --evidence-dir /tmp/securewave-sendgrid-canary

python3 scripts/codex_cli_controller.py deploy \
  --environment staging \
  --packet /Users/simonparris/Documents/securewave-phase0-authorization.txt \
  --approval-file <external-approval-file> \
  --evidence-dir /tmp/securewave-staging-deploy

python3 scripts/codex_cli_controller.py deploy \
  --environment production \
  --packet /Users/simonparris/Documents/securewave-phase0-authorization.txt \
  --approval-file <external-approval-file> \
  --evidence-dir /tmp/securewave-production-deploy

If a required target, credential, image, provider value, SSH identity, network
path, approval public key, or replay ledger is absent, return BLOCKED. Do not
substitute a guessed value. Check-only SMTP and SendGrid modes must remain
no-send. A successful provider result means provider submission acceptance
only, not inbox delivery. A successful deployment command does not prove the
public URL or post-deployment behavior changed.

If an explicit login target cannot be reached because of DNS, TLS, or external
connectivity failure, the controller must emit
`CONTROLLER_RESULT=BLOCKED_EXTERNAL_ACCESS` and retain the specific diagnostic
category only in redacted evidence. Missing SSH/SCP tools must use the same
blocker; never bypass the Codex CLI sandbox.

Record the exact command, exit code, redacted evidence path, and one of PASS,
FAIL, BLOCKED, NOT_RUN, or UNKNOWN. End with exactly one required
AUTOMATION_RESULT line.
```

The operation prompt does not grant network, SSH, SMTP, provider, or target
access that the Codex CLI process does not already have. Never use
`--dangerously-bypass-approvals-and-sandbox`.

The controller and diagnostic do not alter the existing authentication routes
or make a local source change live. A new Flutter diagnostic artifact must be
built and separately distributed before a downloaded binary can contain the
new redacted login diagnostics.

The provenance report also inspects the tracked Linux x64 portable tarball when
present. If it reports `release_safety=BLOCKED_EMBEDDED_API_TEMPLATE`, treat
that artifact as historical/stale evidence and rebuild it from a clean reviewed
Linux source tree; do not manually edit or repack its Flutter `.env` asset.
