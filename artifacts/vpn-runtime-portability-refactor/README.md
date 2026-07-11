# VPN Runtime Portability Refactor Evidence

Date: 2026-07-11 UTC

- Branch: `codex/vpn-runtime-portability-refactor`
- Base: `origin/master` at `d8ddec2d`
- Host: Linux AArch64 / Debian ARM64
- Production deployment: not performed
- Artifact publication or manifest availability change: not performed
- External load testing: not performed
- Live credentials or real VPN infrastructure changes: not used

## Outcome

The Linux Flutter runner now uses the package-installed Unix socket helper
instead of direct `pkexec`, `wg-quick`, or shell execution. Helper contract
10 adds strict request/config validation, narrow user authorization, bounded
socket I/O, deterministic status/counter evidence, and safer package cleanup.
Windows is explicitly WireGuard-only and macOS remains unavailable.

The current host proves an ARM64 build and package payload only. Helper install,
socket operation, and live protocol routing are blocked because the helper is
not installed, passwordless root is unavailable, and no authorized live
credentials were used.

See:

- `runtime-inventory.md`
- `arm64-package-evidence.md`
- `test-results.md`
- `blocked-boundaries.md`
- `runtime-verifier-summary.json`
- `../../docs/PORTABILITY_RUNTIME_MATRIX.md`
- `../../docs/LINUX_X64_DEB_GITHUB_ACTIONS_RUNBOOK.md`
