# 10. Limitations, future work and conclusion

## 10.1 Current limits

The supported implementation is a Linux WireGuard application. Portable
Flutter widgets and protocol catalog responses do not establish working
OpenVPN, IKEv2 or cross-platform networking. The UI presents authoritative
supported state rather than fabricated server lists or throughput. Historical
production measurements belong to their original commit/package, while the
consolidated 1.0.0 candidate needs its own installed acceptance.

The verifier observes IPv4 routing and public egress. Comprehensive IPv6,
split-routing, captive portal, suspend/resume, resolver conflict and leak tests
remain further work. A hardened kill switch is a separate claim requiring
firewall-state and failure-injection evidence. Disconnect restoration does not
by itself prove continuous leak prevention during every transition.

Usage is sampled and supplied by a trusted local helper. It can be incomplete
across unsampled crashes, resets or disk faults. Root compromise can alter
measurements. Durable replay prevents duplicate accepted effects but does not
establish tamper-proof billing or indefinite offline storage capacity. A
business policy for retention, deletion, reconciliation and privacy is needed
before interpreting the ledger as a commercial billing record.

Authentication currently permits immediate registration/login without a
mailbox verification gate. Native token refresh, self-service key rotation,
device revocation UX and account lifecycle policies should be evaluated as
separate features. They should not be assumed from the presence of refresh
tokens or an `email_verified` response field.

## 10.2 Prioritized research and engineering work

| Priority | Work | Evidence needed |
| --- | --- | --- |
| 1 | Finish 1.0.0 installed/reboot acceptance | Fresh exact-package lifecycle, recovery and final ledger observations |
| 2 | Network failure and leak matrix | IPv4/IPv6, DNS, sleep/resume, unreachable endpoint, firewall inspection |
| 3 | Fault-injected journal/reporting recovery | Crash at write/commit boundaries; exact totals and quality flags |
| 4 | Parser and privilege-boundary audit | Fuzzing, permission mutation, path attacks and timeout tests |
| 5 | Retention and reconciled metering | Storage growth, server/client disagreement policy, privacy/deletion model |
| 6 | Capacity and performance study | Repeated trials, resource metrics and uncertainty intervals |
| 7 | Additional platforms | Native implementations and real device acceptance per platform |

A future anomaly detection extension inspired by the author's research would
need a new specification. Traffic metadata collection can itself affect user
privacy. Before adding federated learning, define which observations leave the
device, consent, adversarial participants, model-update protection and a
reproducible baseline. No inference model or detection accuracy is claimed in
the current application. A separate
[MARL/XGBoost routing experiment](../development/routing-optimizer.md) trains
on simulator episodes and observes measured inputs in shadow mode. Its frozen
synthetic holdout does not establish production routing gains, and the combined
policy did not outperform XGBoost alone. One physical production host cannot
validate alternative-server selection. Backend ICMP probes and normalized load
averages also differ from the simulator's client latency/congestion variables;
fresh timestamps do not remove that domain mismatch.

## 10.3 Conclusion

RQ1 is addressed by observable interface, peer, handshake, counter, route and
egress checks before the Connected transition. RQ2 is addressed by an
unprivileged GUI and a constrained credential-checked helper. RQ3 is addressed
by durable cumulative reports and transactional sequence/digest idempotency.
RQ4 is addressed by process ownership, persisted checkpoints and explicit gap
quality where recovery cannot reconstruct observations. RQ5 is addressed by
commit and package provenance followed by separate installed and public
delivery evidence.

The engineering lesson is that reliable VPN behavior depends on coordinating
several failure domains while keeping their evidence distinguishable. The
source provides mechanisms and tests for that coordination. Remaining runtime,
security and scalability questions require the targeted experiments described
above rather than stronger wording about existing results.
