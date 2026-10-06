# 1. Problem definition and requirements

## 1.1 Problem statement

A desktop VPN changes privileged operating-system state on behalf of an
unprivileged user. The application must coordinate account identity, peer
identity, interface ownership, routing, DNS and accounting. These states reside
in different processes and persistence domains. No single database transaction
can atomically include a GTK window, a kernel interface, a local journal and a
remote HTTP response. The design therefore uses explicit transitions,
verification, compensating cleanup and retryable accounting.

The supported implementation target is Ubuntu 24.04 ARM64 with a graphical
session, systemd, WireGuard tools and the Linux Flutter runtime. The Flutter
source has portable UI code; that does not establish working native VPN
support on Android, iOS, Windows or macOS. Generated mobile scaffolding is not
part of the supported product surface.

## 1.2 Functional requirements

| ID | Requirement | Observable result |
| --- | --- | --- |
| F1 | Register and authenticate an account | Valid session reaches Home; incorrect password remains rejected |
| F2 | Keep client private identity local | Configuration request transmits the public key only |
| F3 | Provision an account-owned peer | Server parameters correspond to the requesting account and device |
| F4 | Connect through the Linux helper | Fixed interface and expected peer appear in authoritative runtime output |
| F5 | Verify usable VPN connectivity | Recent handshake, counters, route and changed public egress are observed |
| F6 | Disconnect and recover | Interface/configuration are removed and network restoration is checked |
| F7 | Record measured traffic durably | Local cumulative counters survive reporting interruption |
| F8 | Avoid duplicate ledger effects | Repeated identical checkpoint is acknowledged without adding bytes again |
| F9 | Expose uncertainty | Unavailable counters and measurement gaps are visible |

## 1.3 Nonfunctional requirements

The helper should accept a finite protocol rather than arbitrary commands.
Secrets should remain in protected stores and be excluded from source,
screenshots, logs and public artifacts. UI rendering should consume
authoritative application state rather than create a second VPN state machine.
Backend updates should use bounded payloads and transactions. Releases should
identify their source commit, tree state, architecture and helper contract.
Documentation should allow a reviewer to trace an advertised property to code
and a meaningful test.

These requirements do not imply a complete formal security audit. In
particular, no claim is made that the application provides anonymity against a
global observer, protects a compromised root account, prevents every possible
IPv6 leak or reconstructs traffic never sampled before a crash.

## 1.4 Failure model and assumptions

The design considers expired authentication, provisioning failure, stale
interfaces, missing handshakes, unreachable egress probes, counter resets,
network interruptions, lost HTTP responses, concurrent checkpoint requests,
GUI exit, daemon restart and reboot. A remote service can be unavailable for an
unbounded time; successful reporting is therefore a conditional liveness
property, not a fixed completion-time guarantee.

The trusted computing base includes the Linux kernel, root helper, installed
network utilities, operating-system key store, backend and database. Local root
can read or alter protected files and kernel counters. The usage ledger is
operational metering under a trusted client/helper model, not a fraud-resistant
billing system against a hostile device owner.

The storage argument assumes successful durable writes have the filesystem's
documented persistence semantics. The accounting concurrency argument assumes
PostgreSQL row locking and transactional commits. SQLite is useful for contract
tests but cannot substitute for the production concurrency model [2].

## 1.5 Scope of the research analogy

The author's federated anomaly detection paper [9] provides a presentation
example: define the problem, specify the model, present algorithms, explain
evaluation and discuss limitations. SecureWave does not implement the paper's
multi-agent reinforcement learning, XGBoost or federated training. A future
anomaly detection experiment would require a separately defined dataset,
privacy model, baseline, metrics and implementation.
