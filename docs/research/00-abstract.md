# Abstract and research questions

SecureWave is a Linux desktop VPN application with a Flutter interface, a
FastAPI control plane, PostgreSQL persistence and a narrowly scoped privileged
WireGuard helper. Its central engineering problem is keeping the user-facing
connection state, the operating system's network state and the backend's
usage ledger consistent despite partial failure. Authentication can succeed
while provisioning fails; an interface can exist without a usable tunnel;
traffic can continue after a GUI failure; and an accepted HTTP update can lose
its acknowledgement. Treating these events as a single success flag would
produce misleading connection and accounting claims.

This report derives the implementation's component model and algorithms from
the source. It examines client-owned key generation, authenticated peer
provisioning, evidence-based connection verification, process-owned teardown,
durable local accounting and transactionally idempotent cumulative
checkpoints. Formal notation describes the verification predicate and ledger
invariants. Correctness arguments are conditional on stated trust, storage and
database assumptions; they are not machine-checked proofs.

Evaluation combines backend contract tests, real PostgreSQL concurrency and
migration tests, native helper tests, Flutter service and presentation tests,
and a separate installed-product acceptance protocol. Automated test results
establish selected contracts. They do not establish current production
availability, reboot acceptance or cryptographic security. The report records
these limits explicitly rather than inventing benchmark measurements.

**Keywords:** WireGuard; Flutter; Linux; privilege separation; state machines;
idempotency; durable accounting; PostgreSQL; reproducibility.

## Research questions

- RQ1: What observable evidence justifies displaying Connected?
- RQ2: How can a GUI control privileged networking without exposing a general
  privileged command interface?
- RQ3: How can retryable reports update a usage ledger without counting the
  same observed bytes twice?
- RQ4: What can be recovered after process failure or reboot, and which
  missing measurements must remain explicit?
- RQ5: Which evidence connects a source commit to an installed and tested
  product, and which claims require separate experiments?

The contribution is an integrated engineering design and a reviewable
assurance argument. WireGuard provides the cryptographic transport [1]; this
project does not introduce a new VPN protocol or cryptographic primitive.
