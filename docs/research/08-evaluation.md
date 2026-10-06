# 8. Evaluation methodology

## 8.1 Evidence hierarchy

Source analysis identifies mechanisms. Unit and contract tests examine chosen
inputs under controlled fixtures. Native tests exercise helper parsing,
ownership, accounting and cleanup with controlled process/network substitutes.
Real PostgreSQL tests examine row-lock races and migration preservation. GUI
goldens establish presentation expectations. Installed acceptance observes the
actual kernel, helper, network and backend. Each layer answers a different
question; passing one does not imply passing all others.

| Layer | Main question | Limitation |
| --- | --- | --- |
| Python contract suite | Are validation, ownership and replay semantics correct for tested cases? | Fixtures simulate peer infrastructure |
| PostgreSQL suite | Does concurrent replay count once; is legacy migration additive? | Disposable database, not production load |
| Native helper suite | Do authorization, parser, journal and cleanup cases behave correctly? | Controlled commands, not live tunnel proof |
| Flutter service suite | Are lifecycle and API errors interpreted correctly? | Mock channels and HTTP adapters |
| Flutter UI/goldens | Are controls, layout, text scaling and state displays consistent? | Rendered fixture state, not network evidence |
| Package provenance | Do installed bytes identify the intended clean source and architecture? | Identity and integrity only |
| Live/reboot acceptance | Does the installed product complete the real lifecycle? | Environment-specific observation |

## 8.2 Reproducible software checks

The consolidated checks use Python 3.12, Flutter 3.41.4/Dart 3.11.1, pinned
Python requirements and Flutter's lockfile. `make test-backend`,
`make test-flutter`, `make test-native` and `make check` are the review entrypoints.
The PostgreSQL tests require `SECUREWAVE_TEST_DATABASE_URL` pointing only to a
disposable database; without it, those tests are explicitly skipped. CI runs
them against its own service. Results and environment limitations belong in
[current state](../current-state.md), not a mutable assertion in each chapter.

Test values exceeding 32-bit integer range assess the widened accounting
contract. Conflicting replay, decreasing totals, final mutation and
cross-account requests are negative cases. Native tests examine ownership and
finalization failures. Flutter tests include endpoint-aware 401 handling,
malformed helper output, missing handshake, absent counters, route/egress
failure, transitions, keyboard focus and layouts at larger text scales.

## 8.3 Installed acceptance protocol

The retained harness is `scripts/securewave_post_reboot_acceptance.py`. It
interacts with the installed GUI through accessibility actions and records
independent observations to a private existing evidence directory. A baseline
captures route tables, rules, DNS, public egress, daemon state and absence of
stale interface/configuration. After authenticated Connect, verify the expected
peer, fresh handshake, interface, protected config mode, route, DNS and changed
egress. Generate bounded test traffic and confirm counter growth. Disconnect
and compare restoration; reconnect and repeat; finish disconnected.

The script's lifecycle command does not independently verify the final
production usage ledger. Complete accounting acceptance additionally requires
owner-scoped backend history or a separately authorized database observation,
matching the session, sequence, counters, final reason and quality. Registration
of a disposable live account is an explicit separate operation, used only when
authorized; no credentials are printed or included in evidence.

## 8.4 Crash and reboot experiments

For GUI SIGKILL, establish a verified connection, generate traffic, record the
session, terminate only the owning process, then observe helper finalization,
interface removal, reporter acknowledgement and final history. For reporter
outage, retain unacknowledged journals, restore delivery and test that replay
adds no duplicate bytes. For reboot, record boot identity and a pre-reboot
baseline; after startup, verify the new boot, enabled/active services, recovery
quality, absence of stale networking, cold launch and a fresh authenticated
connect/disconnect/reconnect sequence.

Historical usage-candidate evidence is archived with its original source and
version. On 6 October 2026 the installed candidate's post-reboot baseline and
cold launch passed, but the saved session had expired. Authenticated post-reboot
VPN acceptance remains pending sign-in. Those observations do not establish
acceptance of the consolidated 1.0.0 source or package.

## 8.5 Threats to validity

Internal validity is affected by other network managers, cached session state,
clock drift and external probe failure. Construct validity depends on using
kernel transfer counters rather than interpreting a UI animation as traffic.
External validity is limited to the tested Ubuntu ARM64 environment; x86_64,
mobile, different DNS managers and hostile local users need separate evidence.
Fixture tests may omit timing races and production permissions. A small
concurrency experiment is evidence for one race, not a full scalability study.

No fabricated performance table is presented. A future benchmark should
compare the normal link and tunnel under the same route, server, CPU load and
traffic generator; report repeated-trial throughput and latency distributions,
packet loss, handshake time, CPU use and confidence intervals. Recovery tests
should vary outage duration and inject faults before/after each durable write
and database commit. Such experiments would strengthen the assurance case.
