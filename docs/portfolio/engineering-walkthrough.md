# Engineering walkthrough

## Trace a connection

Start at [`_HomeViewState._connect`](../../securewave_app/lib/app.dart): capture
baseline egress, load account-specific keys, provision the peer, start local
metering and the helper, then verify the tunnel before displaying Connected.

Follow these boundaries:

1. [`ApiService`](../../securewave_app/lib/services/api_service.dart):
   unauthenticated registration, bearer calls, and contextual 401 handling.
2. [`routes/vpn.py`](../../routes/vpn.py): owner-scoped peer provisioning from
   the client's public key.
3. [`VpnService`](../../securewave_app/lib/services/vpn_service.dart): method
   channel and real interface/handshake/counter/route/egress checks.
4. [`my_application.cc`](../../securewave_app/linux/runner/my_application.cc):
   Dart-to-Unix-socket bridge.
5. [`securewave_helperd.cc`](../../securewave_app/linux/helperd/securewave_helperd.cc):
   local caller checks, fixed operations, safe config paths, network wrapper.

The private client key never goes to the provisioning API. Tunneled packets
go to the WireGuard gateway rather than through the FastAPI process.

## Trace measurement and recovery

Read [`usage_recorder.h`](../../securewave_app/linux/helperd/usage_recorder.h),
the separate
[`reporter`](../../securewave_app/packaging/linux/securewave-usage-reporter.py),
and [`UsageMeteringService.checkpoint`](../../services/usage_metering_service.py).
Reports contain cumulative totals. Row locks and exact-payload retry checks
give one database effect per accepted checkpoint; they do not promise
exactly-once network delivery. Counter resets and interrupted recovery are
explicit measurement gaps.

## Design decisions

| Decision | Benefit | Cost or boundary |
| --- | --- | --- |
| Unprivileged GUI plus fixed root helper | Small privileged interface | IPC and packaging complexity |
| Account-specific client key | No server possession of client private key | Secret Service availability |
| Evidence before Connected | Provisioning is not mistaken for a tunnel | Additional network probes |
| Durable journal and separate reporter | Reporting survives GUI exit | More recovery state and disk writes |
| Cumulative sequence/digest protocol | Lost acknowledgements cannot duplicate bytes | Updates need transactional serialization |
| Explicit gap flag | Missing observations remain visible | Lost traffic cannot be reconstructed |

## Review exercises

- Why does a login 401 differ from a protected-endpoint 401?
- What happens if provisioning succeeds but the peer never handshakes?
- Why does a lost HTTP acknowledgement not double-count traffic?
- Which state survives SIGKILL of the owning GUI?
- Which concurrency tests need real PostgreSQL instead of SQLite?
- Why does a matching package hash not prove post-reboot VPN acceptance?

Run the [test workflow](../development/testing.md), then read the formal
[algorithms and arguments](../research/README.md). See
[current state](../current-state.md) for the limits of the evidence.
