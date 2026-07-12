# SecureWave Current Status

Last updated: 2026-07-12 UTC

This file is the current-state index. Dated certification reports remain useful
historical evidence, but their branch names and base commits are not current
instructions.

## Canonical branch

- Development and release truth: `master`.
- Work is performed on short-lived branches and merged by pull request.
- The old `Linux`, `Mac`, `Windows`, and `flutter` branch descriptions are not
  a substitute for current `master`. Preserve or retire those branches only
  after reviewing their open pull requests.

## Verified repository state

- Current audited master: `b2c69ade88a6d7d96a1478f792c39ec793888fac`.
- Master CI is green for repository guards, dependency/security scans, Python,
  Flutter Linux, Flutter Android, and Docker.
- The safe local entry point is `bash scripts/certify_repository.sh` with a
  development Python environment containing `requirements_dev.txt`.
- PostgreSQL migration and concurrency proof is available through
  `bash scripts/certify_postgres.sh`; it uses a disposable loopback-only Docker
  container and does not contact production.

## Current product truth

- Linux is the primary client platform.
- WireGuard is the strongest runtime path.
- OpenVPN requires a real backend profile and helper/runtime proof.
- Linux IKEv2 is intentionally unavailable through the product while the
  backend refuses Linux IKEv2 profiles, despite helper orchestration existing.
- Windows WireGuard and Apple native VPN remain unproven for release.
- The macOS download is a UI/account demo, not a VPN runtime.
- Linux x64 has historical build evidence, not current contract-10 clean-host
  installation or live-routing proof.

## Active completion sources

- `docs/CURRENT_ISSUES_AND_COMPLETION_PLAN.md`: remaining issues and execution
  order.
- `docs/CODE_AND_GITHUB_REFACTOR_PLAN.md`: code and repository refactor gates.
- `docs/PORTABILITY_RUNTIME_MATRIX.md`: protocol/platform evidence boundaries.
- `docs/POST_MERGE_ENTERPRISE_RELEASE_TODO.md`: externally authorized release
  and operations evidence.

## External gates

Production, staging, provider activation, load tests, package publication, and
live VPN credentials require separate explicit authorization. Apple signing and
native runtime work require a Mac with the approved Apple identities and tools.
