# Routing reintegration validation — 7 October 2026

## Scope and source

The source baseline was clean `ee605ee4749324049d44862051bf98c15af4e530` on
the sole branch `master`. Application version remains 1.0.0. No Flutter,
native helper, authentication contract, website design or public download
manifest was changed by this implementation.

Local agents first audited research provenance, dataset quality and acceptance
prerequisites. The resulting implementation contains an offline simulator and
trainer, shared pure policy, measured-input collector, offline inference worker,
default-off shadow observer, selector integration and focused tests. See the
[routing guide](routing-optimizer.md) and [formal chapter](../research/11-routing.md).

## Automated software verification

| Check | Result |
| --- | --- |
| Initial backend, disposable PostgreSQL included | 54 passed |
| Final clean-environment backend + routing, PostgreSQL included | 168 passed |
| Routing-specific correctness and failure handling | 114 passed |
| Flutter analysis and tests, unchanged source | Clean analysis; 133 passed |
| Native helper/wrapper, unchanged source | Passed |
| Website design/download/support/navigation, unchanged source | Four checks passed |
| Repository versions, Markdown links, whitespace | Passed |
| Architecture PDF | Rebuilt with routing chapter and current revision date |

Optional dependencies were installed in a fresh private virtual environment,
not assumed from an existing development environment. Heavy model tests are
portable: they train their own temporary artifact rather than depending on a
previous `/var/tmp` result. CI now has a separate routing-research job.

The seed-42 80-episode model was retrained without holdout feedback. Model
SHA256: `8e8f3807f97431bf444babbfc4bc899664070c14996521e05584fb96be885857`.
Policy SHA256: `5f990ef2f8bd202719b6b16f4f2a65d99b8c69155bb991d0f54e069900598093`.
Frozen synthetic mean utilities: baseline 0.525263, XGBoost 0.545234,
combined 0.533659. The combined policy trails XGBoost alone; no production
uplift or activation is claimed.

## Passive production overlay

The production release pointer remains
`20261006T000751Z-usage-c90dc03f5ccb`. Its full older website/API backend was
preserved. Deployment changed only the selector import/wrapper and added
`services/routing_shadow.py` plus `ml/routing_policy.py`. A dedicated systemd
drop-in enables shadow mode, with private model/policy storage owned by the
API identity. The API does not import the trainer or native ML packages.

The guarded overlay checked the original selector AST, release pointer, full
route hash, harmless existing ML namespace and absence of conflicting files
before mutation. Original route source is preserved under root-only backup
`/var/backups/securewave-routing-shadow-20261007T201310Z`. A failed readiness
check would restore source/config and restart the previous behavior.

| Deployed source | SHA256 |
| --- | --- |
| `routes/vpn.py`, full preserved backend file with overlay | `94e4a93757c8f3f93289a4352b8baee4272ca3edc5d1628cb447a706a3251404` |
| `services/routing_shadow.py` | `85ebd02f4ed8574573eaf399fb6dee584b59c5cd178ecc24ee874d0cd6645b14` |
| `ml/routing_policy.py` | `93077f5bb0c83ef68a775db2a7138ef2e2a4ccccb5b22be1fb0fbbeb48157c38` |

API readiness returned HTTP 200 after restart, with the database connected.
Public download page and catalog returned HTTP 200 on the canonical site;
unauthenticated protected server listing correctly returned HTTP 401.

Five registry entries map to one physical IP and one eligible server for each
tier. That skips with `no_alternative`, retaining the established selector.
The external collector received no ICMP replies and could not supply RTT.
It failed without fabricating data or replacing a snapshot. No production
measured snapshot exists, and no automatic telemetry daemon was installed.
Fresh legacy health records contain estimated/simulated fields and are excluded.

## Real app evidence and remaining gate

The current public package is 1.0.0 ARM64 from clean source
`a8096ae5f8fa07e380f4fad3cf189767912b816c`, package SHA256
`52d1cb49d7152b195ead58b75623722120d1794d5cb95ffe0a6efe8210f0d00e`.
The test launched its exact extracted GUI against byte-matching installed
helper/reporter services. The installed GUI package remains `a9181ea8`.

Before the passive backend deployment, automated live acceptance passed at
20:07:36 UTC: disposable registration/sign-in, two Connect/3-MiB-traffic/
Disconnect cycles, Reconnect, finalized version-2 complete usage history and
logout. Independent checks confirmed expected peer, one-second handshake age,
increasing counters, exact IPv4/IPv6 routes/rules/DNS/domains/egress restoration,
no temporary configuration, no retained token and active services.

The post-deployment GUI rerun encountered a locked desktop before entering
credentials or starting a tunnel. The final live GUI gate is pending desktop
unlock. A healthy API or local unit test is not a replacement for that proof.
No new installation or reboot occurred in this task. Credentials/tokens are
kept in memory; screenshots and raw evidence remain private, outside Git.
