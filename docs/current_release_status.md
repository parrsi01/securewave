# SecureWave - Current Release Status

Last audited: 2026-07-14 UTC

## Candidate under certification

- Branch: `codex/linux-runtime-final`
- Source head: `b45b093b4969a0ff3e8c27b0011ebf30a4d6070c`
- Base: `origin/master` at `b2c69ade88a6d7d96a1478f792c39ec793888fac`
- Application/package version: `4.0.0+3`
- Local ARM64 package: `securewave_app/build/packaging/securewave-vpn_4.0.0+3_arm64.deb`
- Local ARM64 package SHA-256: `bc6c47e209138567e4f07d8e24b681cd3195b33d6dec8d036f0a916f6b20e909`
- No artifact was published, signed, or deployed by this certification.

## Protocol truth

WireGuard is the primary Linux protocol. The normal Flutter -> backend profile ->
helper IPC path is implemented. The candidate source and release bundle require
helper contract 13. The local host has an existing contract-13 helper
installation, while this rebuilt package remains a local artifact pending a
fresh install/lifecycle proof.

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
  PostgreSQL; PostgreSQL `alembic check` and the concurrent usage single-winner
  test pass.
- The documented infrastructure target is Hetzner Cloud, with managed
  PostgreSQL and Redis; no provider or production endpoint was contacted by
  this local certification.
- Compose app/PostgreSQL/Redis health and migration checks pass with a production-
  style environment that does not inherit production dotenv settings.
- The candidate package definition includes the helper daemon, wrapper, contract
  13, systemd, systemd-resolved, nftables, tmpfiles, and paired strongSwan
  routing-mark payload. The current local ARM64 rebuild is the recorded
  contract-13 package; it has not been published or deployed.
- The release Flutter binary starts on this Linux host. The headless graphics
  environment emits Mesa cursor/driver warnings; no crash was observed during the
  bounded run.
- Real interface, handshake, endpoint-bypass, IPv4/IPv6 route, DNS, HTTPS,
  exit-IP, counter, disconnect, upgrade, purge, and residue evidence requires an
  explicitly authorized staging account and an installed package. It was not
  claimed from local mocks or helper capability probes.

## Artifact and platform limits

- The local ARM64 `.deb` is not a public download. Install it from its local path
  only after verifying the checksum.
- The Linux x64 `.deb` remains `coming_soon` in the public manifest. Workflow
  `29348878602` at source head `164098b136c9d6eeba7d0a94ec8a4ab38c0d19e9`
  passed the contract-13 package and ephemeral lifecycle checks and produced
  private evidence with SHA-256
  `48768524c4682d5d85027531fae9a499acd6eb4f45f6cc83b9d13f8bae54fd91`.
  No x64 artifact is public because live authenticated data-plane evidence is
  still absent.

## Current private x64 workflow evidence

The current x64 evidence is retained only in the GitHub Actions artifact for
run `29339889834`; it is not a public download. It proves x86_64/amd64 ELF
payloads, contract 13, declared dependencies, ephemeral install, active
helper/socket, structural verifier, bounded app launch, purge, and networking
residue checks. It does not prove live protocol routing or release readiness.
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
deb="$PWD/securewave_app/build/packaging/securewave-vpn_4.0.0+3_arm64.deb"
echo "bc6c47e209138567e4f07d8e24b681cd3195b33d6dec8d036f0a916f6b20e909  $deb" | sha256sum -c -
sudo apt install "$deb"
systemctl is-enabled securewave-helper.service
systemctl is-active securewave-helper.service
cat /usr/local/libexec/securewave-wg-quick.contract
```

Upgrade with `sudo apt install /path/to/securewave-vpn_NEW.deb`; purge with
`sudo apt purge securewave-vpn`, then run the disconnected runtime verifier and
check that the helper socket, service payload, and contract are gone. An ARM64
package cannot be installed on an x86_64 host; use the matching architecture.
