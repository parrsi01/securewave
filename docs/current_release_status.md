# SecureWave - Current Release Status

Last audited: 2026-07-15 UTC

## Candidate under certification

- Branch: `codex/linux-runtime-final`
- Source: current PR #48 candidate; use the PR head SHA rather than a checksum
  copied from an earlier workflow run.
- Base incorporated: `origin/master` at
  `56d3126116120176152e98ab213d0fa1b19e1fdc`
- Application/package version: `4.0.0+3`
- Local ARM64 package: `securewave_app/build/packaging/securewave-vpn_4.0.0+3_arm64.deb`
- Local ARM64 package SHA-256: record the checksum from the exact retained build
  in the private PR evidence; local Debian archive timestamps make a checksum
  from an earlier rebuild unsafe to copy forward.
- No artifact was published, signed, or deployed by this certification.

## Protocol truth

WireGuard is the primary Linux protocol. The normal Flutter -> backend profile ->
helper IPC path is implemented. The candidate source and release bundle require
helper contract 13. The rebuilt ARM64 package passed install, helper/service and
socket validation, malformed and unauthorized IPC rejection, verifier, bounded
application launch, same-version upgrade, purge, and networking-residue checks
in a fresh Ubuntu 24.04 ARM64 systemd container.

OpenVPN remains unavailable unless both backend server evidence and fresh
data-plane evidence are usable. Local helper capability alone does not enable it.
IKEv2 remains unavailable because the backend/runtime and authorized external
data-plane proof gates are not all green. Its isolated local lab passed EAP,
ESP/XFRM, endpoint-bypass, private DNS/HTTPS egress, rekey, failed-authentication,
reconnect, disconnect, and cleanup assertions. No unsupported protocol is
presented as release-ready.

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
- The packaged release Flutter binary remained running for a bounded ten-second
  Xvfb launch in the clean ARM64 container. Headless graphics and keyring
  warnings are environment diagnostics; no crash was observed.
- Real interface, handshake, endpoint-bypass, IPv4/IPv6 route, DNS, HTTPS,
  exit-IP, counter, and disconnect evidence requires an explicitly authorized
  staging account. It was not claimed from local mocks or helper capability
  probes; package upgrade, purge, and disconnected residue proof are recorded
  separately above.

## Artifact and platform limits

- The local ARM64 `.deb` is not a public download. Install it from its local path
  only after verifying the checksum.
- The Linux x64 `.deb` remains `coming_soon` in the public manifest. Exact-head
  package evidence and its checksum are recorded in the private workflow and PR
  review, never copied forward from an earlier source revision. No x64 artifact
  is public because live authenticated data-plane evidence is still absent.

## Current private x64 workflow evidence

The exact-head x64 evidence and checksum belong in the private GitHub Actions
run and PR review record; they are not a public download. The workflow proves
x86_64/amd64 ELF payloads, contract 13, declared dependencies, ephemeral
install, active helper/socket, structural verifier, bounded app launch, purge,
and networking residue checks. It does not prove live protocol routing or
release readiness.
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
sha256sum "$deb"
sudo apt install "$deb"
systemctl is-enabled securewave-helper.service
systemctl is-active securewave-helper.service
cat /usr/local/libexec/securewave-wg-quick.contract
```

Compare the output with the checksum attached to the exact build in the private
PR evidence. Never substitute a checksum from an earlier local rebuild.

Upgrade with `sudo apt install /path/to/securewave-vpn_NEW.deb`; purge with
`sudo apt purge securewave-vpn`, then run the disconnected runtime verifier and
check that the helper socket, service payload, and contract are gone. An ARM64
package cannot be installed on an x86_64 host; use the matching architecture.
