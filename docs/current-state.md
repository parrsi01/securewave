# Current validation record

Updated **6 October 2026**. The consolidated application source is **1.0.0**.
`master` integrates usage recording, the navy/cyan UI presentation and PyJWT
2.15.0 maintenance. Helper contract **15**, socket request protocol **1**, and
usage protocol **2** remain distinct compatibility identifiers.

## Consolidated software checks

| Check | Result | Environment and scope |
| --- | --- | --- |
| Backend contracts + JWT authentication | 54 passed | Python 3.12, pinned requirements, ephemeral PostgreSQL 16 plus disposable SQLite fixtures |
| PostgreSQL race | Passed | Two identical concurrent cumulative reports counted once; totals exceed 32-bit range |
| PostgreSQL migration | Passed | Preserved legacy rows; migration run twice against disposable legacy-shaped schema |
| Flutter static analysis | No issues | Flutter 3.41.4 / Dart 3.11.1 |
| Flutter tests | 120 passed | API/VPN/usage service, UI/accessibility and visual fixtures |
| Native helper and wrapper | Passed | Temporary compiled helper tests; no host tunnel mutation |
| Architecture report | 29-page PDF | Rebuilt from 7,400+ words of chapter sources and original SVG diagrams; reviewed sample pages |

The pre-consolidation backend also passed in a fresh-source copy without
ignored local environment files. Consolidated CI is defined in
[Review checks](../.github/workflows/ci.yml). Local checks do not establish a
completed GitHub Actions run; the workflow records its own result for each SHA.

## Package and installed-product evidence

The reviewed source is ready for an exact-commit candidate build. The package
must carry 1.0.0 and the clean source markers described in the
[release procedure](development/releasing.md). Building source does not replace
the installed package or change existing public downloads.

The VM currently has the historical **4.0.0+12** ARM64 usage candidate, source
`c90dc03f5ccbab5fffb2fcaefedc72ea36e34527`, clean tree, helper contract 15.
The new boot began **2026-10-06 08:37:39 UTC**. Helper startup, disconnected
baseline networking and visible cold launch passed. The app's saved session
expired; authenticated post-reboot lifecycle and final usage history remain
pending private sign-in. No 1.0.0 installed/reboot acceptance is claimed.

The existing public release baseline is **4.0.0+11**; its publication record is
[archived](archive/releases/4.0.0+11-publication.md). No deployment or website
publication is part of this source/documentation consolidation.

## Preserved history

- [Usage candidate verification](archive/releases/4.0.0+12-verification.md)
  records earlier traffic, cleanup, recovery and backend persistence observations.
- [Post-reboot checkpoint](archive/releases/4.0.0+12-post-reboot.md) records the
  exact installed candidate and remaining authenticated test.
- [State before consolidation](archive/current-state-2026-10-06-before-consolidation.md)
  preserves the prior branches and versions as a historical snapshot.
- [Archive index](archive/README.md) separates these records from the current
  developer and recruiter reading paths.

Run the [testing workflow](development/testing.md) to reproduce software checks.
Read the [report](research/README.md) for algorithms and the limits of the
correctness argument. Private local artifacts and configuration are retained
outside the public Git source.
