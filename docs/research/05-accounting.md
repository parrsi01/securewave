# 5. Durable usage accounting

## 5.1 Measurement model

WireGuard exposes peer transfer counters. The helper samples the expected
peer, accumulates changes and journals cumulative session totals. Let c_t be
one raw counter, a_t its accumulated observed total and g a sticky gap flag.
The rule is applied independently to sent and received directions:

```text
δ_t = c_t - c_(t-1)      if c_t ≥ c_(t-1)
δ_t = c_t               if c_t < c_(t-1), and g ← true
a_t = a_(t-1) + δ_t
0 ≤ a_t ≤ 2^63 - 1
```

A reset exposes the bytes visible after reset but cannot reveal bytes between
the last sample and that reset. Marking a gap is therefore more defensible than
claiming complete measurement. Raw counters are bounded and parsed before
use; arithmetic overflow is rejected. Counter totals measure WireGuard peer
transfer, which can include protocol effects. They are not identical to a
browser's downloaded file length or billable application payload.

## 5.2 Protected local journal

Each usage session has a restricted journal under
`/var/lib/securewave/usage`. The directory is mode 0700, record files mode
0600, and record names and contents are validated. Records include session
identity, capability, expected peer, boot identity, owner identity, cumulative
counts, sequence and finalization state. The account JWT and client private
key are not stored in this usage journal.

Writes use GLib's consistent and durable file replacement flags [7]. Under the
documented filesystem assumptions, a successful write avoids exposing a
partially overwritten record and requests persistence. This mechanism does not
make failed writes succeed or eliminate hardware/filesystem faults. The
daemon must still remove privileged networking when journal persistence fails;
safety of teardown takes priority over claiming complete accounting.

## 5.3 Algorithm 3: sample and finalize

```text
Input: active UsageRecord, expected peer, kernel runtime
1  read validated transfer counters for the expected peer
2  compute nonnegative direction deltas; mark gap on reset/unavailable data
3  update bounded cumulative totals and checkpoint sequence
4  durably replace the protected record
5  on disconnect/owner exit: quiesce and sample final observable counters
6  mark final reason and stop time; durably save final checkpoint
7  tear down interface and safely remove temporary configuration
8  release process ownership regardless of journal-write success
```

Actual finalization paths distinguish connect failure, owner exit and recovered
interruption. Recovery of an unfinished record from a previous boot resets the
raw-counter baseline and marks a gap; it does not invent a final kernel sample.
Once replayed, a final record carries the best retained observations with an
explicit quality indication.

## 5.4 Delivery protocol

The reporter periodically requests pending records from the helper and submits
HTTPS checkpoints. The interval is two seconds in the current loop; it is an
implementation parameter, not a reporting latency guarantee. The
`Authorization: UsageSession …` capability scopes reporting to one session.
The backend compares its SHA-256 hash in constant time. The reporter
acknowledges the helper after a successful accepted response. A response lost
after commit leaves the checkpoint pending, so the next attempt repeats it.

The journal supplies retry persistence and the backend supplies idempotent
effects. Neither component guarantees eventual delivery if the server remains
unavailable forever, the disk is lost or the reporter is permanently disabled.
Journal retention and a practical operational storage budget require explicit
monitoring; this report does not assert a proven global bound for arbitrary
offline duration and session churn.

## 5.5 Algorithm 4: transactional checkpoint acceptance

Let n be the submitted sequence, (S,R) cumulative totals and h the digest of
the canonical complete payload. Let (n*,S*,R*) describe the last accepted
session state.

```text
Input: session id, capability, n, S, R, final, quality and stop metadata
1  lock the session row inside a database transaction
2  verify capability hash, session existence and payload constraints
3  compute digest h over counts, sequence, flags, reason and stop metadata
4  if n ≤ n*:
5      accept as duplicate only when the stored event has the same digest
6      otherwise reject the conflicting replay
7  reject new mutations of an already finalized session
8  require S ≥ S* and R ≥ R*
9  ΔS ← S - S*; ΔR ← R - R*
10 atomically update session totals, peer totals and unique event record
11 persist sticky gap/verification quality and final state if requested
12 commit and return acknowledgement
```

A larger sequence may skip an earlier checkpoint: cumulative counts preserve
the observed byte delta. A repeated exact earlier event can be acknowledged
without effect. A changed payload using an old sequence is rejected. The
digest includes quality and finalization metadata so that identical byte
counts cannot conceal a conflicting semantic replay.

## 5.6 Exactly-once effects, conditional measurement completeness

The useful guarantee is that an accepted logical checkpoint has at most one
ledger effect under the transaction and uniqueness assumptions. Delivery can
occur multiple times. This is not an exactly-once network transport guarantee.
The ledger may still be incomplete if a crash precedes sampling or persistence.
Quality metadata distinguishes accepted accounting from complete observation.

Client measurements and server-side snapshots occupy separate fields. Adding
both as if they were independent traffic would double-count the same flow.
Server snapshots can support future reconciliation, but the current ledger
protocol does not constitute a fully independent reconciliation or billing
audit system.

## 5.7 Calendar-month account projection

The account view is a projection of accepted ledger events, not a second
measurement system. For each cumulative session, the highest accepted sent
and received values within a UTC calendar month are reduced by their highest
preceding values. Summing these differences across account-owned sessions,
plus legacy increment events, produces the monthly total. Device revocation
does not remove historical events. Server snapshots remain excluded.

The Free allowance is 5,000,000,000 bytes, with decimal display units. The app
adds only positive differences between its local observations and acknowledged
session counters to the saved projection. Pending display observations are
account-keyed; they cannot update the ledger. This preserves monotonic session
presentation across disconnect and reauthentication without double-counting a
checkpoint when the reporter catches up.

Accepted-event timestamps determine month attribution. This permits efficient
aggregation with existing indexes but assigns late offline reports to their
receipt month. Trusted interval-level timestamps would be needed for exact
offline allocation across month boundaries. Client-side cap enforcement and
backend provisioning checks also permit sampling/reporting overrun; they are
not equivalent to independent server-side shaping. Detailed implementation and
tests are in the [monthly usage guide](../development/monthly-usage.md).
