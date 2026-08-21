# SecureWave - Current Release Status

Last audited: 2026-08-21 UTC

## Local Linux ARM64 Beta candidate

- Branch: `codex/linux-beta-release-candidate`
- Source: `0c6a0e4d10b5ecc8d1d42c6724b96f892c0d9ca7`
- Base: `origin/master` at `f558d0337d5bd20d52cb94e8112746a4d818ab99`
- Application/package version: `4.0.0+10`
- Package: `securewave_app/build/packaging/securewave-vpn_4.0.0+10_arm64.deb`
- Package SHA-256: `102e9e97d198a21c2bace69aa42d38a6d6b5ce040ab503495ac47b950c422d3c`
- Embedded package source state: `clean`
- Helper contract: `13`
- Publication, signing, deployment, merge, tag, and external acceptance: not performed.

## Intended scope

This candidate targets Ubuntu 24.04 ARM64 with the native Flutter Linux client,
the light SecureWave UI, one authenticated WireGuard server/runtime, and the
real backend/PostgreSQL path. The intended acceptance flow is registration,
login, connect, disconnect, reconnect/session restoration, and logout.

OpenVPN, IKEv2, payments, SMTP/email verification, additional server catalogs,
other architectures, and formal release governance are outside this Beta
candidate. The Debian package declares only the WireGuard/Linux runtime
dependencies and does not carry the legacy secondary-protocol payload files.

## Evidence completed locally

- `git fetch --all --prune` succeeds after moving the identified zero-byte
  `refs/codex/turn-diffs/checkpoints/...` ref to a recoverable temporary backup.
- `flutter analyze --no-pub`: no issues.
- `flutter test --no-pub`: 50 tests passed.
- Current light UI guard, release guards, repository hygiene, and redacted
  source-secret scan pass.
- `flutter build linux --debug` and the release build used by the package pass
  for the ARM64 host, including the native VPN and external-link channels.
- The package checksum sidecar verifies, and its embedded version, architecture,
  helper contract, source SHA, and clean-tree marker match this candidate.

## Remaining proof boundary

The package is a locally built candidate, not an accepted release. No clean
device install, privileged helper/service lifecycle, real account registration,
authenticated login, WireGuard handshake, traffic/egress proof, restart,
logout, or external-user acceptance was run in this recovery pass. Those steps
require the authorized target environment and credentials; none were requested,
stored, or printed here.

The public download manifest was intentionally not changed. Serving/public URL
availability, deployed backend readiness, artifact provenance, installation,
and authenticated VPN acceptance remain separate proof layers.

## Local inspection

```bash
cd /home/sp/cyber-course/projects/securewave-linux-beta-release-candidate/securewave_app
sha256sum build/packaging/securewave-vpn_4.0.0+10_arm64.deb
dpkg-deb -f build/packaging/securewave-vpn_4.0.0+10_arm64.deb \
  Package Version Architecture Depends
```
