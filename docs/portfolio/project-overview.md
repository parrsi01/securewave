# SecureWave: project overview

**Author:** Simon Parris. **Source version:** 1.0.0, `master`.

## Problem and purpose

A VPN product needs more than encryption: account authentication, correct
peer provisioning, safe operating-system routing, truthful status, cleanup
when the desktop process dies, and reliable usage records during outages.
SecureWave addresses that complete lifecycle for a Linux WireGuard client.
WireGuard supplies encryption; the project supplies the application, control
plane, OS integration, measurement pipeline, and verification workflow.

## User workflow

Register or sign in, connect to an authorized server, inspect real upload and
download counters, disconnect, reconnect, and log out. Usage sessions also
finalize after window close or process death. Recovery marks missing
measurement instead of inventing traffic.

## Engineering work

| Area | Concrete implementation | Skills demonstrated |
| --- | --- | --- |
| Desktop | Flutter auth/VPN views and accessible controls | Dart, async state, UI, visual regression |
| API | FastAPI account, peer, and usage contracts | Python, HTTP, validation, authentication |
| Persistence | Cumulative checkpoints and additive migration | PostgreSQL, transactions, concurrency |
| Native systems | GTK method channel and fixed C++ helper | C++, Linux IPC, process lifetime |
| Networking | Client-owned identity and real runtime checks | WireGuard, routing, DNS, diagnosis |
| Reliability | Durable journal, reporter, crash cleanup | Recovery, idempotency, failure analysis |
| Delivery | Debian package and source provenance | Release engineering, reproducibility, Git |

## Delivery sequence

1. Establish authentication and client-owned peer provisioning.
2. Verify real traffic, routing, DNS, teardown, and reconnect.
3. Add durable usage, idempotent reporting, and process-exit cleanup.
4. Exercise recovery and distinguish source/package/runtime evidence.
5. Consolidate UI and maintenance work onto `master`.
6. Set the source version to 1.0.0 and document the architecture formally.

The [current record](../current-state.md) identifies completed checks and
remaining post-reboot acceptance. The [archive](../archive/README.md) retains
the identities behind earlier installed-app observations.

Read this overview, then the [engineering walkthrough](engineering-walkthrough.md),
then the [architecture chapter](../research/02-architecture.md). The repository
supports a code review and reproducible offline testing without access to
production credentials.

This is a portfolio engineering system. It does not claim security
certification, a new encryption protocol, unmeasured performance gains, or
supported packages for other platforms.
