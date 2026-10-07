# Current validation record

Updated **7 October 2026**. The consolidated application source is **1.0.0**.
`master` integrates usage recording, the navy/cyan UI presentation and PyJWT
2.15.0 maintenance. Helper contract **15**, socket request protocol **1**, and
usage protocol **2** remain distinct compatibility identifiers.

The [routing validation record](development/routing-validation-2026-10-07.md)
documents the optional backend MARL/XGBoost experiment, passive production
overlay, current data limits and exact GUI/package distinction.

## Consolidated software checks

| Check | Result | Environment and scope |
| --- | --- | --- |
| Backend contracts + JWT authentication | 54 passed | Python 3.12, pinned requirements, ephemeral PostgreSQL 16 plus disposable SQLite fixtures |
| PostgreSQL race | Passed | Two identical concurrent cumulative reports counted once; totals exceed 32-bit range |
| PostgreSQL migration | Passed | Preserved legacy rows; migration run twice against disposable legacy-shaped schema |
| Flutter static analysis | No issues | Flutter 3.41.4 / Dart 3.11.1 |
| Flutter tests | 133 passed | API/VPN/usage service, UI/accessibility and visual fixtures |
| Optional routing + backend suite | 183 passed | Clean Python environment, optional ML dependencies, helper-confirmed revocation and disposable PostgreSQL 16 |
| Native helper and wrapper | Passed | Temporary compiled helper tests; no host tunnel mutation |
| Architecture report | 32-page PDF | Rebuilt from chapter sources, routing analysis and original SVG diagrams |

The pre-consolidation backend also passed in a fresh-source copy without
ignored local environment files. All three consolidated
[CI jobs passed](https://github.com/parrsi01/securewave/actions/runs/37480826413)
for `c733457d6170c5393d60f531bd8075cc46096ca4`. Later changes make the checksum
sidecar portable and record maintenance/package evidence; each push has its own
run in [Review checks](../.github/workflows/ci.yml).

## Package and installed-product evidence

The **1.0.0 ARM64 candidate** was built from a clean detached checkout of
`a9181ea8828d6b66557260042bbbcde0675c0e84`, also identified by the immutable
tag `candidate/1.0.0-20261006`. Extracted markers match that source, version,
ARM64 architecture and helper contract 15; the installed binary is an AArch64
ELF. The portable checksum sidecar verifies beside the package.

Package: `securewave-vpn_1.0.0_arm64.deb`, **15,180,502 bytes**.
SHA-256: `9b561d5444ee39259b9dad3e656f840e4657f89db18fdbfaf2396e9a8c2bc622`.
It is saved with checksum/source sidecars in the
[GitHub draft candidate](https://github.com/parrsi01/securewave/releases/tag/candidate/1.0.0-20261006).
Draft assets are owner-visible until publication. Building source does not
replace the installed package or change existing public downloads; follow the
[release procedure](development/releasing.md) for that transition.

The VM now has **1.0.0 installed**, with source
`a9181ea8828d6b66557260042bbbcde0675c0e84`, clean tree, ARM64 and helper contract
15. Administrator-authenticated installation completed on
**2026-10-06 at 18:20:02 UTC**, following recovery from laptop power loss.
The installed executable, AOT library, helper and reporter match the verified
package byte for byte. Both services are active; visible cold launch,
disconnected runtime, absence of stale interface/configuration, route/DNS/egress
baseline and production API readiness passed.

The installed 1.0.0 authenticated lifecycle passed on **2026-10-06 at
22:28 UTC**. Connect and Reconnect each transferred a real 3 MiB download;
independent peer/handshake/counter/route/DNS/egress checks passed. Both
disconnects restored baseline routes, IPv6 routes, rules, DNS/domains and
public egress exactly, and removed the session configuration. Owner-scoped
backend history confirms two finalized version-2 usage sessions, verified
timestamps, complete quality and persisted totals covering each cycle's
observed traffic. See the [acceptance record](archive/releases/1.0.0-installed-acceptance-2026-10-06.md).

The VM's current boot began **2026-10-06 at 21:39:39 UTC**, after the 1.0.0
installation. The previous 11:03 timing was stale. On 7 October the current
public UI bundle (`a8096ae5`) passed fresh cold-launch, authentication, two real
traffic cycles, ledger finalization, logout and route/DNS restoration against
the installed helper/reporter. That test launched the extracted public bundle;
it did not replace the installed GUI from `a9181ea8`. No new installation or
reboot was performed. Package-specific installed/reboot claims remain separate.

The website now offers **1.0.0 only**, published on 2026-10-06 with matching
package bytes and source provenance. See the [website publication record](development/website-readability-2026-10-06.md)
for catalogs, checksums, retired URLs, readability changes and validation limits.
The previous **4.0.0+11** publication is [archived](archive/releases/4.0.0+11-publication.md).
Historical GitHub releases are preserved; no full application/backend redeploy
was performed as part of the website update.

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
