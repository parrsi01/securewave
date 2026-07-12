# Staging VPN server audit

## Scope and result

**Audited revision:** `b2c69ade` (`origin/master` at audit start)

**Audit branch:** `codex/audit-staging-vpn-infrastructure`

**Date:** 2026-07-12 (UTC)
**Result:** **not ready for staging tunnel certification**. WireGuard and
OpenVPN are correctly unavailable until server-side prerequisites and fresh,
protocol-specific evidence exist. IKEv2 remains intentionally disabled on
Linux.

This was a source and local-runtime audit only. No staging, production,
Hetzner, SSH, cloud API, database, firewall, DNS, VPN endpoint, credential,
key, or profile was accessed. No infrastructure or production state was
changed. Hostnames, addresses, tokens, keys, and profile content are omitted.

## Evidence boundaries

| Layer | Status | Evidence and limit |
| --- | --- | --- |
| Local Linux helper | verified locally | `securewave-helper.service` was active and enabled; the helper socket was `0660 root:securewave`; installed helper contract was `10`. This only proves local privilege-boundary readiness. |
| Backend API metadata | fail-closed by implementation | `ProtocolAvailabilityService` requires active/degraded and freshly checked server state, capacity, provider `running` state, complete protocol metadata, and fresh healthy evidence for the requested protocol. |
| Usable VPN server runtime | not verified | No authorized staging runtime was contacted. The authenticated API state supplied for this audit reports no usable WireGuard or OpenVPN runtime evidence. |
| Profile issuance | partially implemented; not live-proven | WireGuard blocks issuance unless peer registration succeeds. OpenVPN can build a client configuration only after its availability gate but has no demonstrated server-side user credential/provisioning flow. |
| Live tunnel | not tested | There is no interface, route, DNS, endpoint-bypass, exit-IP, counter, disconnect, or cleanup evidence from an authorized staging tunnel. |

The local helper result must not be interpreted as backend availability, a
registered VPN server, profile usability, or a connected tunnel.

## Backend control-plane findings

`services/protocol_availability_service.py` enforces the following before it
reports a protocol available:

1. Server status is `active` or `demo`, health is `healthy` or `degraded`, and
   `last_health_check` is fresh (default evidence TTL: 300 seconds, bounded to
   30--3600 seconds).
2. The server has capacity and provider state `running`.
3. WireGuard requires `supports_wireguard`, endpoint, public key, and fresh
   healthy `wireguard` evidence.
4. OpenVPN requires `supports_openvpn`, an endpoint/public address, CA data,
   and fresh healthy `openvpn` evidence.
5. Every other protocol, including IKEv2, is false with the reason that it is
   not release-ready.

`routes/vpn.py` exposes only WireGuard and OpenVPN as Linux-supported
protocols. It also deliberately returns `supports_ikev2: false` for Linux
server responses. Consequently, changing server metadata alone cannot enable
an honestly available protocol; the availability service will still reject
missing, unhealthy, or stale runtime evidence.

## Profile and device-registration findings

### WireGuard

The `/api/vpn/profile` route evaluates readiness before it creates device key
material. It then creates/reuses a device peer and invokes the remote
WireGuard management API or SSH path before returning a private-key-bearing
profile. A failed registration returns `503` and clears the active server
assignment. `routes/devices.py` applies the same WireGuard readiness and peer
registration check.

This is the correct control-plane direction, but it is not staging data-plane
proof. It needs a real registered server and a successful bounded test peer
before a client tunnel can be certified.

### OpenVPN

The backend can issue an OpenVPN client configuration containing endpoint,
transport, DNS directives, and CA data. It marks that result
`openvpn_profile_issued`; it does **not** register a client on a server or
issue per-user OpenVPN credentials/certificates. The returned configuration
uses `auth-user-pass`, but this audit found no corresponding server-side
credential lifecycle or device-registration implementation. A syntactically
generated profile therefore is not usable-runtime or live-tunnel proof.

### IKEv2

Linux excludes IKEv2 from `_platform_supported_protocols`, and the availability
service unconditionally treats it as not release-ready. IKEv2 must remain
disabled. Enabling it requires separate authorization and a complete
server/client credential lifecycle, protocol-specific runtime verification,
and route/data-plane proof (including the pref-220 routing-loop guard); none
were attempted here.

## Deployment and runtime audit

### WireGuard missing prerequisites

The repository contains `infrastructure/wireguard_vm_setup.sh`, which
provisions a WireGuard host with forwarding, NAT, firewall opening, `wg0`, and
a management API path. `deploy/hetzner/compose.yaml` deploys the backend,
database, and Redis only; it does not deploy a VPN server.

To become honestly available in staging, WireGuard needs all of the following:

1. An authorized, isolated staging WireGuard server provisioned from reviewed
   configuration, with service/config/UDP listener, forwarding, NAT, firewall,
   DNS reachability, and endpoint-bypass behavior verified.
2. A server registry record containing the real endpoint and public key, with
   correct capacity/provider state. Registration must follow, not substitute
   for, server verification.
3. A secured backend-to-server management path whose real peer add/remove and
   health check succeed.
4. Fresh healthy WireGuard-specific evidence written by the monitor within the
   availability TTL.
5. An authorized test account/device and live evidence: interface, selected
   routes, DNS, protected data-plane traffic, endpoint bypass, changed exit
   IP, counters, disconnect, and cleanup.

### OpenVPN missing prerequisites

There is no tracked OpenVPN server-provisioning implementation in the audited
deployment paths. `infrastructure/hetzner/audit_vpn_fleet.py` can inspect an
already-provisioned host for OpenVPN binary/service/config/cert/listener and
firewall facts; it does not provision one.

Additionally, `services/vpn_health_monitor.py` and the administrative health
endpoint record **WireGuard** protocol evidence only. They contain no OpenVPN
runtime probe, so OpenVPN cannot obtain the fresh evidence required by the
availability gate through the present monitor.

For honest OpenVPN availability, staging needs:

1. An authorized OpenVPN server deployment with reviewed server configuration,
   CA/server certificate lifecycle, authentication model, service/listener,
   forwarding/NAT, firewall, and DNS configuration.
2. A secure per-user credential or certificate issuance, rotation, revocation,
   and device association path that matches `auth-user-pass`; profile metadata
   and CA data alone are insufficient.
3. An OpenVPN-specific, non-secret health probe that records compact fresh
   evidence independently of WireGuard health, plus failure/recovery tests.
4. The same authorized end-to-end client proof required for WireGuard,
   including route, DNS, data plane, endpoint bypass, exit IP, counters, and
   cleanup.

`infrastructure/hetzner/sync_vpn_servers.py` can store support flags and
endpoint/CA metadata. It must be used only after the above conditions are
verified; setting `--supports-openvpn` is not a valid enablement action.

## Staging audit tooling

The existing server auditor can safely collect boolean/configuration state
from an explicitly authorized fleet: WireGuard/OpenVPN/IKEv2 binary, service,
listener, configuration, certificate-presence, firewall, forwarding, NAT, and
route facts. It should be run only with approved staging host scope and a
redacted artifact destination. It does not establish client data-plane proof,
and it must not be pointed at production under this work item.

## Checks performed

All commands below were read-only except the test database lifecycle managed
by the existing test suite. No output containing sensitive infrastructure
details was retained.

```text
git rev-parse --short HEAD
systemctl is-active securewave-helper.service
systemctl is-enabled securewave-helper.service
stat -c 'socket=%a owner=%U group=%G' /run/securewave/helper.sock
cat /usr/local/libexec/securewave-wg-quick.contract
/home/sp/cyber-course/projects/securewave/.venv/bin/python -m pytest \
  tests/integration/test_vpn_profile.py \
  tests/integration/test_vpn_flow.py \
  tests/integration/test_device_acl.py \
  tests/unit/test_vpn_server_inventory_filter.py -q
```

Results:

| Check | Result |
| --- | --- |
| Audited revision | `b2c69ade` |
| Helper service | active and enabled |
| Helper socket | `0660`, owner `root`, group `securewave` |
| Installed helper contract | `10` |
| Backend/profile/device/inventory tests | **36 passed** in 7.01 seconds |
| Staging server audit | not run: no explicit staging target scope/credentials were supplied |
| Live tunnel proof | not run: no authorized staging profile/account or runtime target was supplied |

The test run emitted one existing `pytest-asyncio` deprecation warning about
the unset default event-loop scope; it did not fail the suite.

## Required next authorization and evidence

Before changing availability, provide explicit staging-only authorization that
names the target servers, approved test account/device, allowed ports and
traffic limits, credential handling method, rollback owner/path, and data
retention/redaction rules. Then execute the existing fleet audit, complete
the missing server/control-plane work above, and collect live protocol proof.

Until then, keep WireGuard and OpenVPN unavailable and IKEv2 disabled. This
audit makes no release-readiness claim.
