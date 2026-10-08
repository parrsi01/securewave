# Monthly usage validation — 8 October 2026

The owner-reported successful manual VPN test was committed and pushed first
as `d88075267eda5b706c1499eeb87c8e66a1be6340`. The existing MARL+XGBoost routing
implementation and automated live acceptance were already on `master`.

This change adds owner-scoped UTC monthly aggregation, a 5,000,000,000-byte
Free allowance, retained last-session presentation, pending-byte reconciliation
across sign-out/sign-in, a usage bar and a simple account/VPN settings summary.
See the [implementation guide](monthly-usage.md) for algorithms and limits.

## Focused repository cleanup

Reference checks found no use of five Plus Jakarta Sans font files, their
license file, an old adblock fallback list, an unused SVG logo or the obsolete
root `.build_timestamp`. These nine tracked files were removed. The shipping
icon, active fonts and their licenses remain. Ten duplicate ignored `.bak`
files were also removed from the two local `ui_legacy_source` directories.
Those directories contained only abandoned Dart UI backups and had no build,
test, packaging or documentation references.

The unused lifetime peer-total quota and remote-usage sync helpers were removed
from subscription access. Monthly access now uses the same durable ledger as
the displayed balance. This also avoids network calls during quota checks.

Dependency manifests stay at the repository root: Python tooling, CI and
hosting expect those paths. Runtime/deployment configuration, build outputs,
private evidence, credentials and unrelated ignored files were preserved.
Current architecture remains in `docs/research`, developer workflows in
`docs/development` and recruiter entrypoints in `docs/portfolio`.

## Verification record

| Software check | Result |
| --- | --- |
| Backend and routing tests, disposable PostgreSQL 16 included | 189 passed |
| Flutter API, accounting, presentation and visual regression | 144 passed |
| Flutter static analysis | No issues |
| Linux debug build against live API | Passed |
| Native helper/wrapper tests | Passed |
| Versions, Markdown destinations and whitespace | Passed |
| Research architecture PDF | Rebuilt with monthly-accounting analysis |

The PostgreSQL concurrency check independently verifies monthly totals after
two simultaneous identical reports: they count once. An existing routing
fixture now explicitly sets its intended public-directory mode, making the
negative permissions test portable under a restrictive creation mask.

All five [GitHub Review checks passed](https://github.com/parrsi01/securewave/actions/runs/37706763905)
on `2d5149b5a8fadeda4cf48d36ef50003d44c76248`: backend, desktop,
documentation, website and routing research.

## Live API overlay

The live backend retained its existing full release at
`/opt/securewave-beta/releases/20261006T000751Z-usage-c90dc03f5ccb`.
Only `services/monthly_usage.py`, `routes/usage_recording.py` and the reviewed
monthly-access functions in `services/subscription_access.py` changed.
Existing production demo/mock compatibility branches were preserved. No schema
migration, account rewrite or blanket deployment occurred. Authentication,
JWT, routing shadow integration and metering implementation bytes were checked
unchanged. Guards verified the prior file hashes and production/nonmock runtime
before mutation; readiness and protected monthly-endpoint authentication passed.

The rollback backup is root-only
`/var/backups/securewave-monthly-usage-20261008T000842Z`. Its manifest identifies
source `988563281f3fd5660e49616706fcb97abbe282ed` and deployed hashes:

| Deployed module | SHA256 |
| --- | --- |
| Monthly aggregation | `15e87f722a72e68bc84822d863decc4e37458b952462e12f578617941019f0a5` |
| Usage endpoints | `7431ac7c85c2f877e02d11a87bc751516e80f2555d42725b7b731cee2a873ac1` |
| Preserved backend with monthly subscription-access changes | `efab15229748c7a3f1493d5d46d51a840a1f58ae268e16a600eab70b7c86058c` |

## Actual app acceptance

At **00:20:35 UTC**, the source debug build from clean commit
`2d5149b5a8fadeda4cf48d36ef50003d44c76248` passed supervised real GUI
acceptance on an isolated display with the installed helper/reporter and live
API. Registration, sign-in, two Connect/real 3-MiB-download/Disconnect cycles,
settings, sign-out, repeat sign-in and final logout passed.

| Durable session | Sent bytes | Received bytes | Quality |
| --- | ---: | ---: | --- |
| First | 75,820 | 3,379,056 | Complete, finalized |
| Reconnect | 115,080 | 4,041,388 | Complete, finalized |

The monthly endpoint returned **7,611,344 bytes**, exactly the sum of these
two accepted sessions. The GUI showed **7.61 MB of 5 GB used** after disconnect
and after sign-out/sign-in, with retained final download/upload values. A
different newly registered Free account independently returned **0 bytes** and
the same 5,000,000,000-byte allowance. Settings exposed Free account type,
actual location, Disconnected state, WireGuard and version 1.0.0. Named native
Settings/Back controls were exercised; readable snapshots were inspected.

Each cycle had the expected peer and a one/two-second handshake, increasing
real counters and changed egress. Disconnect restored IPv4/IPv6 routes, rules,
DNS/domains and egress exactly; no tunnel or temporary configuration remained.
The helper and reporter remained active and final app logout cleared its token.
The disposable PostgreSQL container and volume were removed after testing.

Private raw evidence is at
`/var/tmp/securewave-monthly-usage-20261008/qa/20261008T001955Z`, with 0700
directories and 0600 records. Test credentials existed only in memory and a
volatile isolated Secret Service collection. No durable secret keyrings were
created; the only keyring-directory file was nonsecret session-alias metadata.

Source version remains 1.0.0 and master remains the sole branch. This acceptance
used a source debug build; the installed GUI and public installer retain their
earlier identified provenance. No installation or reboot occurred. MARL+XGBoost
remains routing shadow only, with no usage prediction or quota discount claim.
