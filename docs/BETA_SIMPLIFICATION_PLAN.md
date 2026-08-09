# SecureWave Beta 1 simplification plan

This is the execution plan for the Linux beta, not a promise to preserve the
historical feature set. The original dirty checkout remains preserved at its
existing SHA; this plan is being implemented in the clean candidate checkout.

## Product boundary

### Keep in the real beta

- Flutter Linux client and one privileged helper contract (contract 13)
- one canonical email/password account flow
- FastAPI, PostgreSQL, and one configured WireGuard target
- peer/profile provisioning, real handshake, traffic counters, and cleanup
- one ARM64 Debian package for the currently evidenced Linux target
- concise health/usage observation that never controls connectivity

### Simplify in place

- direct bearer-token authentication and one `/api/auth` implementation
- direct WireGuard profile issuance with `WIREGUARD_SERVER_ID`
- client state around disconnected, connecting, connected, disconnecting, and
  error
- one package build/verify path and one supported API configuration

### Remove from the active beta path

- OpenVPN, IKEv2, and strongSwan runtime branches
- protocol capability/availability/factory dispatch
- server lists, regions, ranking, failover, and server selection UI
- subscriptions, payments, premium gates, and email delivery/verification
- deployment/release gates that block ordinary auth or connect
- obsolete helper contracts and protocol-specific tests

Historical Alembic revision IDs, parents, and the schema chain remain available
for existing databases. The 0006 loader was made independent of retired runtime
model modules and guarded for absent legacy tables; old schema names are not
active runtime features.

### Demo branch only

The demo reuses the same UI and state model, replacing the API and helper at
one narrow service boundary. Its auth, connection state, health, and usage are
deterministic and always labeled `DEMO MODE`; it never supplies a real
WireGuard configuration.

### Research only

MARL remains offline/research material. XGBoost, if available, is an optional
health observer. Neither can authenticate, route, or gate a tunnel.

## Target decision

ARM64 is the current Beta 1 target because this clean candidate has a verified
ARM64 Flutter Linux build, a reproducible ARM64 `.deb`, and ARM64 helper/runtime
evidence. There is no equivalent x86_64 package/runtime proof in this checkout.
amd64 remains the next architecture, not a second Beta target during this
scope reduction.

## Branch decision

`master` remains the canonical MAIN branch until an explicitly authorized
integration/push. The finished review candidate is currently held on
`codex/linux-beta-demo`; that is a handoff ref, not a second product line. A
single local `demo` branch is created from the same candidate. Existing remote
and local branches are retained as historical evidence and are not active
product branches; they are not deleted automatically.

## Acceptance order

1. compile and focused auth/WireGuard/helper tests
2. deterministic demo flow
3. reproducible package and fresh-package verification
4. clean Linux install and real handshake/egress evidence
5. only then document MAIN/DEMO as complete; deployment and public-download
   updates remain explicit handoff items
