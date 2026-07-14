# Linux runtime support and bounded testing

The Linux runtime uses a privileged helper service and the allowlisted helper
socket. Connect and disconnect operations do not invoke `sudo` or `pkexec`.
Only the one-time package installation/upgrade path is privileged.

## Redacted operational diagnostics

An administrator can request `GET /api/diagnostics/operational`.

The response contains a schema version, environment/database engine, evidence
TTL, bounded capacity counters, health timestamps, protocol availability, and
fixed failure/recovery transitions. Server references are short hashes. It
does not return user IDs, email addresses, provider IDs, public/private
addresses, endpoints, VPN configurations, certificates, keys, tokens, or raw
probe/exception output. A `failed` or stale protocol is unavailable until a
fresh authenticated probe records recovery.

## Monitoring behavior

The fleet monitor probes the authenticated server manager, persists only
booleans, timestamps, and a fixed vocabulary (`initial`, `steady_healthy`,
`steady_failed`, `failed`, `recovered`), and marks probe exceptions as
`probe_exception`. A persistence failure rolls back the database transaction;
the failing server cannot poison the next server's check. Alert/support data
is isolated from manager output and never carries exception text or VPN state.

## Bounded local/staging test envelope

Tests must target an in-memory/local disposable service or an explicitly named
staging target. Production hosts, production URLs, provider APIs, and real
user credentials are out of scope.

The default bounded envelope for an explicitly authorized staging run is:

| Signal | Limit | Abort condition |
| --- | ---: | --- |
| Concurrent workers | 8 | Any unapproved increase or queue growth |
| Duration | 60 seconds | Hard timeout or unbounded retry |
| Requests | 100 total | More than the documented cap |
| p95 latency | 1,000 ms | Exceeded twice consecutively |
| p99 latency | 2,000 ms | Any sustained breach |
| HTTP 5xx/error rate | 1% | More than 5% or any auth/secret leak |
| CPU | 80% average | 95% sustained for 10 seconds |
| Memory | 75% of available | 85% or monotonic unbounded growth |

The abort action is to stop the client, disconnect any test tunnel, run the
SecureWave-only cleanup verifier, and retain redacted logs. No load test was
run against production as part of this certification. The local pass uses
single-process in-memory SQLite and bounded pytest execution; it does not
claim staging performance or live data-plane proof.

Representative local checks:

```bash
timeout 120s /home/sp/cyber-course/projects/securewave/.venv/bin/python -m pytest -q \
  tests/unit/test_protocol_monitoring.py \
  tests/integration/test_vpn_profile.py \
  tests/unit/test_linux_package_lifecycle.py
python3 scripts/linux_vpn_runtime_verifier.py --skip-build-checks --json
```

The verifier is structural unless a real, explicitly authorized staging
connection supplies live interface, handshake, route, DNS, HTTPS, exit-IP,
counter, disconnect, and residue evidence.
