# 6. Backend contracts and persistence

## 6.1 HTTP surface

| Operation | Contract and authority |
| --- | --- |
| POST /api/auth/register | Unauthenticated validated registration; creates account and tokens |
| POST /api/auth/login | Credentials; returns access/refresh data; bad password is 401 |
| GET /api/auth/me | Valid access identity; returns current account |
| POST /api/auth/logout | Valid access identity; advances token generation |
| POST /api/vpn/config | Bearer account; client public key; provisions server parameters |
| POST /api/vpn/usage/sessions/start | Bearer account; starts an owned peer's usage session |
| POST /api/vpn/usage/sessions/{id}/checkpoint | Session capability; cumulative replay-safe checkpoint |
| GET /api/vpn/usage/sessions | Bearer account; paginated history scoped to owner |

Request and response schemas in the routes are the normative contract. The
table summarizes the active design; reviewers should verify exact method and
path names against `routes/usage_recording.py` and `routes/vpn.py` when changing clients. Configuration
provisioning is idempotent with respect to an owned public key, but includes
server-side reconciliation and can fail when live state is unavailable. Mock
peer registration in unit fixtures is never production acceptance evidence.

## 6.2 Entity model

`User` owns peer identities and carries the authentication token generation.
`VPNServer` describes endpoint, public identity, location and operational
capacity. `WireGuardPeer` relates an account and server to a client public key
and allocated address. `VPNConnection` represents a usage session with
metering version, cumulative counters, sequence and recording quality.
`VPNUsageEvent` records accepted checkpoint identity, cumulative counts and
payload digest. Peer totals receive the delta calculated from those counts.

The relationship can be written:

```text
User 1 → N WireGuardPeer
VPNServer 1 → N WireGuardPeer
WireGuardPeer 1 → N VPNConnection
VPNConnection 1 → N VPNUsageEvent
```

These cardinalities express the intended model, not a claim that every historic
row has complete modern metadata. Legacy rows retain metering version 1 and
legacy quality. Version 2 sessions finalize on recorded teardown, allowing a
previous pending final report to coexist with a new connection. Closing an old
version 2 session merely because another starts would fabricate measurement
endpoints and could discard its durable final checkpoint.

## 6.3 Transaction boundaries and concurrency

Start and checkpoint operations enforce ownership and serialize relevant
rows. A checkpoint locks its connection with `SELECT … FOR UPDATE` through
SQLAlchemy. The event, session and peer delta updates commit together. In
PostgreSQL, competing updates to that row wait until the owning transaction
releases its lock [2]. The second identical request then observes the accepted
sequence/digest and returns idempotently.

Two separate session rows can share a peer. Correct aggregate updates must
avoid replacing peer totals with stale values; the implementation uses
database-side increments where appropriate. Transaction ordering, event
uniqueness and rollback behavior are critical review points. Tests deliberately
submit two simultaneous identical checkpoints with totals exceeding 32-bit
range. This evaluates the race that ordinary sequential SQLite tests cannot
establish.

## 6.4 Additive migration

`scripts/migrate_usage_recording.py` provides the PostgreSQL usage migration.
It adds columns conditionally, widens counters, preserves old rows, applies
legacy defaults and adjusts the legacy active-device constraint. A transaction
and advisory migration lock serialize migration attempts, with a bounded lock
wait. Running it twice should not duplicate schema changes or alter preserved
legacy identities.

The migration tests deliberately construct a legacy-shaped schema in a
disposable database and apply the migration twice. They must never target a
production database: they drop selected test columns to recreate that legacy
shape. The migration's additive design is useful evidence but does not replace
a deployment backup, permission review or staging rehearsal on the actual
schema lineage.

## 6.5 Operational configuration

Production JWT and encryption secrets are mandatory configuration. Development
ephemeral defaults are not stable production secrets. Request logging attaches
identifiers and redacts common credential patterns; logging must not be used
to dump full request bodies or WireGuard configurations. Health and readiness
are different observations: a process can respond while its database or peer
helper remains unusable.

History uses a bounded page size and an ID cursor. This keeps one response
bounded while avoiding a full account history scan in client memory. Long-term
event retention, rate budgets and service capacity require measurements and an
operational policy; no throughput figure is inferred from passing tests.
