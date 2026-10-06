# 9. Delivery workflow and reproducibility

## 9.1 Source organization

The repository has one active branch, `master`. Integrated feature histories
remain reachable through merge commits and archive tags. Recruiters can begin
with `docs/portfolio/`; engineers can follow `docs/development/`; the formal
analysis lives here. `docs/archive/` preserves earlier release and handoff
records without presenting their version numbers as current source metadata.
Private credentials, local build outputs and generated unsupported platform
scaffolding are excluded from the public source surface.

The 1.0.0 application version is distinct from helper contract 15, helper
request protocol 1 and accounting protocol version 2. Renaming the application
does not reset those compatibility identifiers. Original historical packages
continue to identify their actual 4.0.0+… versions. The existing historical
v1.0.0 Git tag is not silently moved; a new candidate can use a distinct tag.

## 9.2 Source-to-package chain

A defensible release chain is:

```text
reviewed master commit
  → clean detached checkout
  → locked dependency resolution and release build
  → package metadata + embedded source/tree/architecture/contract markers
  → checksum and source sidecars
  → explicitly identified candidate asset
  → installation on the supported device
  → cold launch + authenticated real lifecycle + reboot proof
  → authorized public publication and download verification
```

The Debian builder packages the Flutter bundle, helper, wrapper, reporter,
systemd units, launcher and icon. The source marker identifies the exact commit;
the tree-state marker distinguishes a clean build from uncommitted inputs.
An ARM64 ELF check confirms architecture rather than relying solely on the
filename. Checksums prove the identity of transferred bytes, not their
correctness or origin independently of the embedded marker.

## 9.3 Version normalization

Application metadata is normalized to 1.0.0 in `VERSION`, the Flutter pubspec
and backend release metadata. Debian regards 1.0.0 as lower than 4.0.0+12,
so an installed older-labelled candidate may require an explicit version
downgrade operation. This should be documented rather than disguised by
retaining a higher hidden package number. Changing source metadata alone does
not replace a previously installed package or existing public download.

## 9.4 CI and reviewer workflow

Continuous integration runs for master pushes and review requests, with
read-only repository permissions and no production credentials. Jobs validate
backend contracts against disposable PostgreSQL, Flutter static analysis and
tests, native helper tests, source versions, documentation links and PDF
rebuilding. A CI pass is recorded for its exact SHA. It does not install the
desktop app on the user's VM or alter live peer infrastructure.

The release workflow is documented rather than automated into an uncontrolled
production deployment. Database migration, server provisioning and public
publication are separate operational actions requiring their own environment
and evidence. The repository keeps their scripts inspectable while avoiding
the suggestion that a recruiter needs production access to review the code.

## 9.5 Reproducibility limits

Pinned dependencies and provenance improve repeatability. They do not guarantee
bit-identical binaries across all machines: toolchain versions, environment,
timestamps and platform libraries can affect bytes. The report renderer embeds
fonts, uses deterministic PDF metadata and stores SVG source figures; reviewers
can rebuild the document without a remote service. Any deterministic-output
claim should be verified by comparing hashes from two runs in the same pinned
environment.

The public validation record distinguishes local software checks, package
provenance, installed acceptance and serving evidence. Raw secret-bearing logs
and private evidence directories are not copied into GitHub to manufacture a
more impressive-looking evidence bundle.
