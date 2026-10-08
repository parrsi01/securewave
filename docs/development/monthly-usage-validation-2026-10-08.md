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
| Flutter API, accounting, presentation and visual regression | 143 passed |
| Flutter static analysis | No issues |
| Linux debug build against live API | Passed |
| Native helper/wrapper tests | Passed |
| Versions, Markdown destinations and whitespace | Passed |
| Research architecture PDF | Rebuilt with monthly-accounting analysis |

The PostgreSQL concurrency check independently verifies monthly totals after
two simultaneous identical reports: they count once. An existing routing
fixture now explicitly sets its intended public-directory mode, making the
negative permissions test portable under a restrictive creation mask.

Live deployment and GUI results are recorded after their checks complete.
Source version remains 1.0.0 and master remains the sole branch. No installer,
public download or reboot claim follows from a debug build.
