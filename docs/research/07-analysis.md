# 7. Correctness arguments and complexity

## 7.1 Invariants

| Symbol | Intended invariant | Enforcement point |
| --- | --- | --- |
| A1 | A peer's authenticated owner cannot be changed by another account's request | Provisioning ownership checks |
| L1 | Connected follows successful current verification | App state owner and VpnService |
| L2 | Cleanup failure retains possible-active state | Disconnect and compensation paths |
| M1 | Accepted cumulative totals never decrease | Checkpoint validation under row lock |
| M2 | Each accepted sequence has one canonical payload | Event identity and digest comparison |
| M3 | Peer delta and session/event update commit together | Checkpoint database transaction |
| M4 | Finalized state rejects new mutation | Final sequence guard |
| M5 | A known measurement gap never becomes complete by a later report | Sticky quality update |
| S1 | Local privileged action is restricted to authorized fixed operations | Helper protocol, peer credentials and path validation |

These are source-derived design properties with corresponding tests. They are
not unconditional guarantees under arbitrary kernel, root or database
compromise. L1 concerns the transition instant; later network failure is
detected by polling rather than prevented by the assertion.

## 7.2 Proposition 1: retry cannot add the same checkpoint twice

Assume PostgreSQL serializes competing updates to one session row; all relevant
ledger effects occur in the same transaction; and the event's logical identity
and digest remain intact. Consider two identical submissions (n,S,R,h). The
first successful transaction changes the accepted state from (n*,S*,R*) to
(n,S,R) and adds (S-S*,R-R*) to the peer. The second transaction reads n as the
current sequence, matches the retained digest and returns idempotently before
performing an increment. If the first transaction rolls back, its ledger
effects are absent and a later submission can perform them once.

An HTTP acknowledgement can be lost after commit without changing this
argument. The retry observes committed state. The argument would fail if the
peer update occurred outside the transaction or if a stale read could bypass
serialization. This is why the real PostgreSQL race test matters.

## 7.3 Proposition 2: cumulative updates tolerate omitted intermediate reports

For accepted checkpoints indexed 0 through m, define ΔS_i = S_i-S_(i-1),
with S_0=0. The total added is:

```text
Σ(i=1..m) ΔS_i = Σ(i=1..m) (S_i - S_(i-1)) = S_m
```

The same telescoping identity holds for received bytes. Skipping an
intermediate sequence does not change the final observed total, provided the
later cumulative value contains its observations and is accepted. It does not
repair unobserved traffic. A decreasing total cannot be interpreted as a new
positive delta and is rejected.

## 7.4 Proposition 3: quality remains conservative

Let g_i indicate that the client reported a gap or the stored session already
had gap quality. The service chooses gap whenever g_i is true. Induction on
accepted updates shows that once gap is stored, no later accepted update can
make it complete. Finalization freezes the accepted endpoint. This is a
conservative record of known uncertainty, not proof that an unflagged session
contains every packet: undetected loss remains a threat to validity.

## 7.5 Lifecycle safety and liveness

The lifecycle algorithm prevents a config response alone from publishing
Connected. Compensation requests teardown after side effects may have begun.
The helper finalizes before removal when observable counters are available,
but removal remains necessary if persistence fails. These choices prioritize
network-state safety and truthful quality reporting.

Conditional liveness requires that the helper can execute teardown, the network
eventually reaches the reporting server, pending records remain durable, and
the reporter continues running. Permanent network partition or storage loss
violates those assumptions. No algorithm can guarantee successful remote
acknowledgement when the receiver is permanently unreachable.

## 7.6 Complexity model

Let P be the number of peers returned by a local runtime query, J the retained
local journal records, H an account's history rows and B the bounded page size.
Counter parsing and peer selection are O(P); the desktop's expected single-peer
interface makes this practically small without changing the general bound.
Returning pending journals requires O(J) inspection in the current helper and
caps each returned batch at 16. Sampling one session uses O(1) arithmetic and
bounded record storage. Rewriting a journal costs filesystem I/O, which is not
captured by an arithmetic-only complexity statement.

A checkpoint performs a bounded number of row queries and updates. Index
lookup costs depend on table size and the database plan; lock waiting depends
on contention and cannot be bounded by saying O(1). History returns O(B)
records after a filtered ordered query; suitable indexes determine whether
lookup remains efficient as H grows. Event retention grows with accepted
checkpoints and needs an operational retention decision.

The report does not claim measured latency, throughput, memory savings or
energy efficiency. Such claims would require controlled benchmarks and an
explicit hardware/software environment.
