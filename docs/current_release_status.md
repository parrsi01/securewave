# SecureWave - Current Release Status

Last audited: 2026-07-13 UTC

## Candidate under certification

- Branch: `codex/linux-runtime-final`
- Base: `origin/master` at `b2c69ade88a6d7d96a1478f792c39ec793888fac`
- Application/package version: `4.0.0+1`
- Local ARM64 package: `securewave_app/build/packaging/securewave-vpn_4.0.0+1_arm64.deb`
- Local ARM64 package SHA-256: `6bdd66e246a5ddd6de0037266d193101291a47395857777103e954a49c73ad5b`
- No artifact was published, signed, or deployed by this certification.

## Protocol truth

WireGuard is the primary Linux protocol. The normal Flutter -> backend profile ->
helper IPC path is implemented. The candidate source and release bundle require
helper contract 11; the installed host remains on contract 10 until the Phase 3
package reinstall, so current runtime checks are intentionally fail-closed.

OpenVPN remains unavailable unless both backend server evidence and fresh
data-plane evidence are usable. Local helper capability alone does not enable it.
IKEv2 remains unavailable because the backend/runtime proof gates are not both
green. No unsupported protocol is presented as release-ready.

## Verified candidate behavior

- Registration, login, logout, restoration, device/profile allocation, retry and
  rollback paths, key rotation, revocation, usage accumulation/idempotency,
  disconnect persistence, and API failure handling are covered by the backend and
  Flutter suites.
- Fresh and repeatable Alembic migrations pass on SQLite and disposable
  PostgreSQL; the PostgreSQL usage concurrency test passes.
- Compose app/PostgreSQL/Redis health and migration checks pass with a production-
  style environment that does not inherit production dotenv settings.
- The current ARM64 release bundle contains the helper daemon, wrapper, contract
  11, systemd, and tmpfiles payload. The previously recorded `.deb` and checksum
  predate contract 11 and must be replaced by the Phase 3 rebuild.
- The release Flutter binary starts on this Linux host. The headless graphics
  environment emits Mesa cursor/driver warnings; no crash was observed during the
  bounded run.

## Artifact and platform limits

- The local ARM64 `.deb` is not a public download. Install it from its local path
  only after verifying the checksum.
- The Linux x64 `.deb` remains `coming_soon` in the public manifest. GitHub-hosted
  x86_64 workflow `29261131617` from source head `9243c862` passed and produced
  SHA-256 `c51616246415d405a45305d923332f989c0fa71c6b01ddc99ed86f3d0ea394c9`;
  this does not prove clean VM installation or live VPN routing.
- Portable archives are UI/runtime-independent packaging and do not install the
  privileged Linux helper.
- Windows, macOS VPN tunneling, and IKEv2 have no release claim from this pass.

## Canonical branch model

`master` is canonical. Focused work is performed on short-lived branches, based
on updated `origin/master`, and merged through a single review. Documentation and
release commands must not instruct users to treat a feature branch as canonical.

## Install the verified local ARM64 package

```bash
cd /path/to/securewave-linux-runtime-final
deb="$PWD/securewave_app/build/packaging/securewave-vpn_4.0.0+1_arm64.deb"
echo "6bdd66e246a5ddd6de0037266d193101291a47395857777103e954a49c73ad5b  $deb" | sha256sum -c -
sudo apt install "$deb"
systemctl is-enabled securewave-helper.service
systemctl is-active securewave-helper.service
cat /usr/local/libexec/securewave-wg-quick.contract
```

Upgrade with `sudo apt install /path/to/securewave-vpn_NEW.deb`; purge with
`sudo apt purge securewave-vpn`, then run the disconnected runtime verifier and
check that the helper socket, service payload, and contract are gone. An ARM64
package cannot be installed on an x86_64 host; use the matching architecture.
