# Staging VPN server runtime preflight

## Outcome

**Audited revision:** `b2c69ade` (`origin/master` at branch creation)

**Branch:** `codex/establish-staging-vpn-runtime`

**Date:** 2026-07-12 (UTC)

**Result:** **blocked before infrastructure changes.** No staging server,
database, firewall, DNS entry, VPN process, peer, profile, or cloud resource
was created, changed, queried, or deleted. No production target was contacted.

The user authorized staging-only establishment in the task request. That
authorization cannot safely be bound to an operational target because no
staging endpoint, account scope, approved credentials, rollback owner, or
temporary-resource inventory was available in this environment. The required
preflight therefore did not pass.

## Mandatory preflight gates

| Gate | Status | Evidence |
| --- | --- | --- |
| Explicit staging-only intent | recorded | The task explicitly limits the requested work to staging and prohibits production. |
| Target is staging, not production | **blocked** | No `SECUREWAVE_STAGING_URL`, `SECUREWAVE_STAGING_API_URL`, or `SECUREWAVE_STAGING_HOST` was configured. The tracked Hetzner compose file forces `ENVIRONMENT=production`, so it cannot be used as a staging target. |
| Operational authorization for a concrete target | **blocked** | No approved staging server identity/scope or operator handoff was present. The task authorization is not enough to safely select a cloud account or host. |
| Rollback method | **blocked** | `docs/OPERATIONS_RUNBOOK.md` gives generic rollback principles, but no target-specific prior revision, snapshot/backup identifier, owner, or tested restore procedure was supplied. |
| Safe staging test account and credentials | **blocked** | A local `live_certification_account.env` exists, but no staging credential file or staging environment alias exists. Its scope was not assumed, and its contents were not read or printed. |
| Temporary resources can be deleted | **blocked** | No approved staging resource inventory or Terraform state was supplied. Terraform is not installed, so no plan/state/destroy preflight can be validated. |

## Safe local checks

The following checks were performed from the clean audit worktree. Values,
hostnames, tokens, profiles, private keys, and endpoint details were not
printed or retained.

```text
git fetch --prune origin
git worktree add -b codex/establish-staging-vpn-runtime \
  /tmp/securewave-establish-staging-vpn-runtime origin/master

# Presence-only checks; secret values were never displayed.
test -n "$SECUREWAVE_STAGING_URL"
test -n "$SECUREWAVE_STAGING_API_URL"
test -n "$SECUREWAVE_STAGING_HOST"
test -n "$HETZNER_STAGING_TOKEN"
test -f securewave_private/staging.env
test -f securewave_private/staging_certification_account.env

docker compose -f deploy/hetzner/compose.yaml config --no-interpolate
/home/sp/cyber-course/projects/securewave/.venv/bin/python -m pytest \
  tests/integration/test_vpn_profile.py \
  tests/integration/test_vpn_flow.py \
  tests/integration/test_device_acl.py \
  tests/unit/test_vpn_server_inventory_filter.py \
  tests/unit/test_vpn_service.py -q
/home/sp/cyber-course/projects/securewave/.venv/bin/python -m py_compile \
  services/protocol_availability_service.py \
  services/vpn_health_monitor.py \
  routes/vpn.py \
  infrastructure/hetzner/audit_vpn_fleet.py \
  infrastructure/hetzner/sync_vpn_servers.py
bash -n infrastructure/wireguard_vm_setup.sh
```

Results:

| Check | Result |
| --- | --- |
| Clean branch base | `b2c69ade` |
| Staging endpoint/host variables | absent |
| Staging-specific token variable | absent |
| Staging credential files | absent |
| Local certification credential file | present but scope not verified; not read |
| Terraform executable | absent |
| Docker Compose validation | passed with placeholder values only; no containers started |
| Backend/profile/device/inventory/service tests | **49 passed** in 6.77 seconds |
| Python/shell configuration syntax checks | passed |

The test run emitted an existing `pytest-asyncio` deprecation warning about
the default event-loop scope. It did not fail the tests.

## Runtime evidence status

### WireGuard

**Not established or verified.** The code has a WireGuard host bootstrap path
and a backend-to-server peer registration mechanism. It cannot be exercised
without the blocked preflight gates above. No proof exists for server
interface/process, key/profile generation, peer uniqueness, listener,
firewall, NAT, routing, DNS, usable backend-issued profile, or live API
availability. The backend's fail-closed availability check remains the only
valid state.

Before any staging change, supply an isolated staging target, approved
credential handoff, a resource tag/inventory, a deletion command or owner,
rollback revision/snapshot and restore procedure, and a limited test account.
Then run the existing redacted fleet auditor and collect server configuration
facts before a bounded profile/peer test. Only record WireGuard available
after fresh protocol-specific runtime evidence is stored and the profile path
has succeeded without exposing key material.

### OpenVPN

**Not established or verified.** The audited code can render an OpenVPN client
configuration after a strict availability check, but this repository does not
contain a tracked OpenVPN server provisioning path or a per-user credential
lifecycle matching the profile's `auth-user-pass` mode. The health monitor
records WireGuard evidence only; it does not generate the fresh OpenVPN
evidence required to make OpenVPN available.

Consequently, no server process/tun interface, firewall/NAT/route/DNS state,
backend-issued usable profile, or API availability is proven. Do not set
OpenVPN metadata to claim availability. The minimal follow-up is a separately
reviewed staging-only OpenVPN server and credential path plus an independent,
non-secret OpenVPN monitor probe; both require the blocked preflight inputs.

### IKEv2

**Disabled, unchanged.** Linux exposes only WireGuard and OpenVPN as
platform-supported protocols, and the protocol availability service rejects
IKEv2 as not release-ready. No IKEv2 resource, configuration, profile,
routing rule, or metadata was changed.

## Cleanup

No temporary staging resource was created, so there is no cloud cleanup to
perform. The only local temporary action was a clean Git worktree and branch;
it contains this evidence document for review and must not be treated as
runtime proof.

## Required handoff to unblock

Provide all of the following in a staging-only operational handoff before
retrying:

1. A named staging environment and approved host/cloud-account scope that is
   demonstrably separate from production.
2. Safe credentials delivered through an approved mechanism, plus a distinct,
   limited staging test account/device.
3. A resource inventory with required tags, a tested deletion path, and an
   accountable rollback owner with prior revision and backup/snapshot
   references.
4. Explicit traffic, port, duration, and abort limits for WireGuard/OpenVPN
   validation.
5. OpenVPN server provisioning, authentication/credential lifecycle, and
   protocol-specific monitoring design approved for staging.

Until these inputs exist, WireGuard and OpenVPN must remain unavailable and
IKEv2 must remain disabled. This document makes no release-readiness claim.
