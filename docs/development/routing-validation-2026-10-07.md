# Routing reintegration validation — 7 October 2026

## User manual acceptance

On 7 October 2026, after launching the current Flutter Linux source app against
the live API, the project owner reported: “manual test was successful, all
actions worked smoothly without issue.” This is user-reported manual acceptance,
separate from the independently observed automated results below. The source at
launch was `425f53f487743a28d9321b5f96e52cdf6c487c39` (version 1.0.0).
The native application window was independently confirmed visible and showing.
The MARL+XGBoost implementation is saved on `master` and remains shadow-only;
manual VPN success does not establish a model performance improvement.

## Scope and source

The source baseline was clean `ee605ee4749324049d44862051bf98c15af4e530` on
the sole branch `master`. Application version remains 1.0.0. No Flutter,
native helper, authentication contract, website design or public download
manifest was changed by this implementation.

Implementation commits: `63d0b24c92ef0bccc4f3e17d37ada5c006d7d63d`
(routing pipeline) and `29c24967c20d690d2951f51719c2e969d6547396`
(client-owned revocation fix). All five
[Review checks passed](https://github.com/parrsi01/securewave/actions/runs/37683367506)
on the latter: backend, desktop, routing research, documentation and website.

Local agents first audited research provenance, dataset quality and acceptance
prerequisites. The resulting implementation contains an offline simulator and
trainer, shared pure policy, measured-input collector, offline inference worker,
default-off shadow observer, selector integration and focused tests. See the
[routing guide](routing-optimizer.md) and [formal chapter](../research/11-routing.md).

## Automated software verification

| Check | Result |
| --- | --- |
| Initial backend, disposable PostgreSQL included | 54 passed |
| Final clean-environment backend + routing, PostgreSQL included | 183 passed |
| Routing-specific correctness and failure handling | 114 passed |
| Client-owned provisioning and revocation contracts | 33 passed |
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
preserved. Initial deployment changed only the selector import/wrapper and added
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
| `routes/vpn.py`, preserved backend with shadow and revocation fixes | `b625e08dd2bcb4a433e499ef0923193ae45565ed05a09ae4f398827dcbd21f5b` |
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

The post-deployment API smoke confirmed registration/login/me/server-list/config
success and an actual `routing_shadow ... reason=no_alternative` log. It found
a separate existing device-revocation HTTP 500: the legacy manager initializes
`/wg` inside the API's restricted filesystem. Client-owned revocation now uses
the provisioning helper, verifies assigned-server identity before and after
removal, confirms absence and only then commits revoked state. All errors
return 503 with rollback, allowing safe retry after an already-removed peer.
Ownership, authentication and the legacy server-owned branch are preserved.
The original overlay hash was `94e4a937...`; its pre-revocation-fix route is
also backed up in the same private backup directory.

At 20:35:30 UTC, the corrected live API acceptance passed fresh registration,
login, authenticated identity, server listing, client-owned provisioning,
helper-confirmed revocation, empty active-device listing, logout and rejection
of the revoked session token. The original disposable test peer was removed
with strict owner/time guards and independently confirmed revoked/inactive;
the repeat test cleaned its own peer through the fixed authenticated endpoint.
No other account or peer was modified. No host tunnel was started by this API
smoke; it is separate from the actual GUI/tunnel evidence below.

## Real app evidence

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

The first post-deployment GUI attempts encountered a locked desktop before
entering credentials or starting a tunnel. An isolated temporary X11 display
and separate D-Bus/accessibility/Secret Service session provided fully automated
acceptance while preserving the owner desktop and keyring. The test used the
actual public binary, installed helper/reporter and deployed production API.

The final supervised run passed at **20:43:55 UTC**, exit **0**: fresh GUI
registration/sign-in, Connect, real traffic, Disconnect, Reconnect, more traffic,
final Disconnect, owner-scoped ledger verification and logout.

| Independent observation | First cycle | Reconnect cycle |
| --- | ---: | ---: |
| Real download bytes | 3,145,728 | 3,145,728 |
| Handshake age, seconds | 1 | 0 |
| RX increase, bytes | 3,355,344 | 3,356,780 |
| TX increase, bytes | 50,416 | 65,964 |
| Finalized persisted RX, bytes | 3,379,300 | 3,380,752 |
| Finalized persisted TX, bytes | 74,444 | 91,400 |

Both version-2 ledgers had complete quality and verified timestamps, with totals
covering observed traffic. Independent post-exit checks confirmed exact IPv4/IPv6
routes, rules, DNS/domains and egress restoration, no tunnel/configuration,
active services and cleared app token. Test secrets stayed in a volatile session
collection. The only keyring-directory file was exact seven-byte nonsecret
default-alias metadata; there were zero durable secret keyrings. Display
authorization used a memory file descriptor. All temporary GUI/display/D-Bus/
keyring/accessibility/portal processes and sockets were cleaned.

This is actual GUI evidence on a virtual display, distinct from the earlier
owner-desktop run. Private raw evidence is under
`/var/tmp/securewave-marl-regression-20261007/20261007T204324Z`, with directories
0700 and records 0600. No new installation or reboot occurred. Package-specific
installed/reboot evidence and untested network/failure scenarios remain separate.
The experiment remains shadow-only; successful VPN regression does not establish
real model performance or create a measured multi-server training dataset.
