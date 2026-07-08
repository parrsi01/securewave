# Post-Merge Enterprise Release Blocker Resolution Plan

Date: 2026-07-08

## Scope and Guardrails

This is a docs-only/planning evidence report. No runtime code changes were made.
No production deploy was run. No `terraform apply` was run. No VPN protocol
behavior, helper logic, runtime logic, or secrets were changed or printed.

## Current Repository State

- Current branch: `master`
- Current commit: `c440c396d94f68ed949860353ea91cb912888659`
- Tracking state: `master...origin/master`
- Metadata sync: `git fetch origin --prune` completed with no output/errors.
- Working tree caveat: the repo already contains many untracked local artifacts.
  This plan intentionally limits the intended change to this file.

## Missing Hetzner Deploy Files

Current `origin/master` status:

- `deploy/hetzner/compose.yaml`: missing
- `scripts/deploy_production.sh`: missing

History found for the missing paths:

- `705f15d7d924cb20458282d91a646c96ab0695af` - `Add release automation and cleanup hardening`
  - Added `scripts/deploy_production.sh`
- `38c7459525996f10d1e720a2ad3dd8bd040bf714` - `chore: harden Hetzner backend deployment config`
  - Added `deploy/hetzner/compose.yaml`
  - Modified `scripts/deploy_production.sh`
- `221a82056fc34183bd1f3d33a5e2f78816642e3b` - `chore: harden Hetzner backend deployment config`
  - Added `deploy/hetzner/compose.yaml`
  - Modified `scripts/deploy_production.sh`
- `e253d8cf12c496072ab7aab9383ae0c4ae31496a` - `chore: harden Hetzner backend deployment config`
  - Added `deploy/hetzner/compose.yaml`
  - Modified `scripts/deploy_production.sh`
- `6729683ce8b7b5c958c6b1eff721a474655f0782` - `Harden Linux no-prompt VPN packaging`
  - Modified `deploy/hetzner/compose.yaml`
  - Modified `scripts/deploy_production.sh`

The latest deploy-file commit, `6729683ce8b7b5c958c6b1eff721a474655f0782`,
is contained in:

- `codex/linux-enterprise-vpn-certification`
- `codex/linux-ikev2-wireguard-parity`
- `codex/linux-no-prompt-portable-vpn`
- `codex/linux-openvpn-wireguard-parity`
- `origin/codex/linux-enterprise-vpn-certification`
- `origin/codex/linux-ikev2-wireguard-parity`
- `origin/codex/linux-no-prompt-portable-vpn`
- `origin/codex/linux-openvpn-wireguard-parity`

The older Hetzner hardening commit `38c7459525996f10d1e720a2ad3dd8bd040bf714`
is contained in `Linux` and `origin/Linux`.

## Candidate Branch Inspection

| Ref | compose exists | deploy script exists | latest compose touch | latest script touch | Assessment |
| --- | --- | --- | --- | --- | --- |
| `codex/linux-no-prompt-portable-vpn` | yes | yes | `6729683c` | `6729683c` | Contains the most hardened deploy files, but the branch also carries runtime/app/package changes. Do not merge wholesale for this blocker. |
| `origin/codex/linux-no-prompt-portable-vpn` | yes | yes | `6729683c` | `6729683c` | Same as local branch; open PR #13 targets `master`. |
| `codex/linux-enterprise-vpn-certification` | yes | yes | `6729683c` | `6729683c` | Contains the most hardened deploy files, but the branch also carries runtime/app/package changes. Do not merge wholesale for this blocker. |
| `origin/codex/linux-enterprise-vpn-certification` | yes | yes | `6729683c` | `6729683c` | Same as local branch; open PR #15 targets `master`. |
| `Linux` | yes | yes | `38c74595` | `38c74595` | Has an older deploy-only baseline; lacks the later guardrail improvements from `6729683c`. |
| `origin/Linux` | yes | yes | `38c74595` | `38c74595` | Same as local `Linux`. |
| `origin/master` | no | no | n/a | n/a | Missing both files. |

Why the files are absent from current `master`: the commits that introduced and
hardened these deploy files are present on side branches/open PR heads, but they
are not reachable from `origin/master` at `c440c396d94f68ed949860353ea91cb912888659`.

## Enterprise Evidence Expectations

The latest candidate files from `origin/codex/linux-no-prompt-portable-vpn` match
the deploy-safety expectations better than the older `Linux` versions:

- `deploy/hetzner/compose.yaml`
  - Uses `postgres:15-alpine`, `redis:7-alpine`, and an externally supplied
    `${SECUREWAVE_IMAGE}`.
  - Requires `POSTGRES_PASSWORD`.
  - Sets `ENVIRONMENT=production`, `DEMO_MODE=false`, and `WG_MOCK_MODE=false`.
  - Binds the app to `127.0.0.1:8080:8080`.
  - Healthcheck verifies both `/api/health` and `/downloads/manifest.json`.
  - This is deployment configuration, not application runtime or VPN protocol logic.
- `scripts/deploy_production.sh`
  - Requires `SECUREWAVE_PRODUCTION_HOST`, `SECUREWAVE_PRODUCTION_IMAGE`, and
    `CONFIRM_DEPLOY=securewave-production`.
  - Refuses localhost-style hosts.
  - Refuses ambiguous image tags unless explicitly overridden.
  - Copies only the compose template, validates remote `.env`, runs
    `docker compose --env-file .env config --quiet`, then updates the stack.
  - This is an operator deployment script. It can affect production only when
    executed with production credentials and explicit confirmation, but adding it
    to `master` does not modify runtime behavior by itself.

Diff from `origin/Linux` to the latest candidate is limited to stricter deploy
guardrails and compose health/env-file handling for these two paths:

- `deploy/hetzner/compose.yaml`: 8 changed lines
- `scripts/deploy_production.sh`: 64 changed lines

## Recommended Safest Path

Create a new deploy-files-only PR into `master` that restores exactly:

- `deploy/hetzner/compose.yaml` from `origin/codex/linux-no-prompt-portable-vpn`
- `scripts/deploy_production.sh` from `origin/codex/linux-no-prompt-portable-vpn`

Do not merge PR #13 or PR #15 solely to resolve these blockers. Their branch
diffs include runtime, app, packaging, workflow, service, and test changes far
beyond the two missing deploy files.

Recommended implementation path after approval:

1. Create a branch from current `master`.
2. Restore only the two deploy paths from `origin/codex/linux-no-prompt-portable-vpn`.
3. Validate bash syntax and compose config with dummy non-secret values.
4. Open a deploy-files-only PR.
5. Keep production activation blocked until credentials, authorization, and tool
   prerequisites are available.

Cherry-pick guidance:

- Avoid cherry-picking full `6729683ce8b7b5c958c6b1eff721a474655f0782` because
  it also modifies Linux no-prompt packaging and download manifest behavior.
- Prefer path-specific restore from that commit/branch for the two deploy files.
- If a cherry-pick is required for audit traceability, use `git cherry-pick -n
  6729683ce8b7b5c958c6b1eff721a474655f0782`, then reset every path except
  `deploy/hetzner/compose.yaml` and `scripts/deploy_production.sh` before commit.

Files that would be affected by the recommended deploy-only PR:

- `deploy/hetzner/compose.yaml`
- `scripts/deploy_production.sh`

## Linux x64 .deb Status

`static/downloads/manifest.json` on current `HEAD` lists:

- `securewave-linux-x64.deb`
- platform `linux`
- architecture `x64`
- status `coming_soon`
- note: Debian/Ubuntu package appears after the Linux release runner publishes it.

Repository/history checks found no `securewave-linux-x64.deb` object and no local
file with that name. Tracked download paths currently include Linux ARM64 `.deb`
artifacts and `securewave-linux-x64.tar.gz`, but not an x64 `.deb`.

Conclusion: this is a build/publish/signing/verification task, not a runtime code
task. The blocker should stay open until an x64 Linux runner builds the package,
publishes it to the download location, updates manifest/checksums, and verifies
install, launch, helper registration, connect, disconnect, and uninstall on a
clean x64 Linux VM.

## Protocol Docs Needing Truth Update

The docs scan found protocol claims that must be reconciled after final
production evidence, not during this planning pass.

Highest-priority files:

- `README.md`
  - Current top-level release truth says Linux desktop first, WireGuard strongest
    verified runtime path, OpenVPN conditional, and IKEv2 disabled until backend
    and strongSwan proof exist.
- `docs/current_release_status.md`
  - Contains the main release status claims for WireGuard/OpenVPN/IKEv2 and must
    be the canonical truth after production evidence.
- `docs/POST_MERGE_ENTERPRISE_RELEASE_TODO.md`
  - Already tracks the protocol documentation truth update as an open checklist item.
- `securewave_app/LINUX_RUNTIME_QA.md`
  - Defines protocol-specific Linux QA expectations, including OpenVPN and IKEv2.
- `securewave_app/DEBUG_CHECKLIST.md`
  - Contains concise protocol readiness/blocked-state rules.
- `securewave_app/README.md`
  - Describes profile fetch and native bridge handoff.
- `docs/runtime_process_cleanup.md`
  - Mentions protocol profile requests and IKEv2 blocked behavior.
- `docs/hr_app_process_overview/README.md`
  - User-facing process overview for WireGuard/OpenVPN/IKEv2 behavior.
- `docs/guides/DESKTOP_THREE_PROTOCOL_PLAN.md`
  - Strategic multi-protocol target; should remain clearly post-v1/backlog unless
    final evidence promotes any protocol.

No protocol docs were edited in this pass.

## Remaining Blockers

- Hetzner fleet audit remains blocked because `HETZNER_API_TOKEN` / `HCLOUD_TOKEN`
  are unset.
- Terraform remains blocked because `terraform` is not installed.
- External load test remains blocked until explicitly authorized against
  SecureWave-owned infrastructure.
- Linux x64 `.deb` remains unavailable / `coming_soon`.
- Protocol docs still need final truth update after production evidence.
- Production deployment remains blocked until the deploy files are restored,
  reviewed, and run only by an authorized operator with production credentials.

## Validation To Run For This Planning Pass

- `git diff --check`
- `git status --short`

Expected intended change: only this planning report.
