# Account usage and settings

Every new account uses the **Free** plan with **5 GB each calendar month**.
The allowance is exactly 5,000,000,000 bytes; KB/MB/GB display values use the
same decimal units. Both upload and download count. Existing active paid
subscriptions remain distinguishable; a `free` subscription row cannot bypass
the cap. No upgrade or paid subscription is created by registration.

## Data flow and persistence

1. The restricted helper measures the real WireGuard peer and durably journals
   cumulative session counters, including the final disconnect sample.
2. The existing reporter submits authenticated cumulative checkpoints and
   retries after network failures, logout, window closure and process death.
3. The backend locks the session and records each accepted checkpoint once.
4. `GET /api/vpn/usage/monthly` reads only the signed-in account's ledger. It
   reports the month, allowance, totals, last session and explicitly requested
   owner-scoped session counters. This endpoint remains readable at the cap.
5. The app combines that saved monthly total with only the unacknowledged
   portion of its known session. Native status from another account is never
   used to restore a disconnected view. A small account-keyed encrypted cache
   retains pending disconnect previews across sign-out/sign-in. It cannot
   submit, edit or replace the billing ledger.

Disconnect retains the last session display and the monthly bar. Signing in
again reloads the account's durable total. Other accounts receive their own
totals. Loading, unavailable and saving states are explicit; a failed request
does not invent a zero balance. The final server snapshot supersedes the local
preview, including bytes transferred between the last UI sample and teardown.

## Monthly aggregation algorithm

For each version-2 session with an accepted checkpoint in month M:

```text
month_sent(session) = max(sent checkpoints in M)
                    - max(sent checkpoints before M, default 0)
month_received(session) = analogous received difference
account_usage(M) = sum(month_sent + month_received)
                 + sum(version-1 increment events in M)
```

The service performs database aggregates, without downloading the event
history into the app. Preceding checkpoints are queried only for sessions
touched during the month. The existing user/session indexes restrict reads.
Cumulative checkpoints must never be summed directly. Revoking a device does
not erase its usage, and server transfer snapshots are not added a second time.

Months use `[first day 00:00 UTC, next first day 00:00 UTC)`. Attribution uses
the server's accepted event timestamp; a delayed offline checkpoint belongs to
its receipt month. Exact allocation of offline traffic across a calendar
boundary would require trusted per-interval observation timestamps, which this
protocol does not currently carry. Measurement gaps remain a limitation of
the underlying recorder and are not filled with invented bytes.

## Efficiency and the allowance

Local counters refresh every two seconds without an internet request. While
connected, the monthly account request runs every 30 seconds, with a short
bounded refresh sequence after disconnect. An idle disconnected app does not
continuously fetch account totals; it refreshes at month rollover or on demand.
The existing reporter and WireGuard keepalive remain unchanged.

The app disconnects when its observed monthly balance reaches the allowance.
The backend blocks further provisioning/session starts with HTTP 402, while
allowing final reports and usage reads. Sampling/reporting intervals can allow
a small overrun. This is client-ledger enforcement, not an independent server
traffic shaper or tamper-proof billing system.

Traffic is not compressed, discounted or divided to make the quota last
longer. Encryption/protocol traffic visible in WireGuard counters can differ
from a downloaded file's size. Large downloads and high-bitrate streaming
consume actual data. MARL+XGBoost remains a separate **routing shadow
experiment**: it never estimates charged bytes, modifies the quota, or claims
bandwidth savings. No representative usage dataset currently justifies a new
usage prediction model.

## Settings and tests

Settings contains email, effective account type, monthly balance and renewal,
location, truthful connection state, WireGuard protocol and app version 1.0.0.
It adds no simulated locations or unsupported toggles.

Run `make test-backend`, `make test-flutter`, `make test-native` and `make check`.
The dedicated tests cover cumulative retries, reconnects, account isolation,
revoked devices, legacy increments, rollover, free subscription rows, cap reads,
pending-preview reconciliation, logout/login persistence and accessible layouts.
See [validation](monthly-usage-validation-2026-10-08.md) for measured results.
