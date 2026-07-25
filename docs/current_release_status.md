# SecureWave - Current Release Status

Last audited: 2026-07-25 UTC

## Candidate under certification

- Branch: `codex/linux-wireguard-arm64-beta`
- Source: `6e0517cc379bd6f64b123297d5dc756a6453d9c1`; this is the reviewed
  candidate commit and it tracks `origin/codex/linux-wireguard-arm64-beta`.
- The current checkout contains scoped uncommitted website/brand/docs/test
  edits from this task; no release artifact was built or published from that
  dirty checkout.
- The candidate includes the current Linux ARM64 WireGuard-only release gates.
- Application/package version: `4.0.0+3`
- Record ARM64 and amd64 checksums from the exact retained workflow artifacts;
  do not copy a checksum from an earlier source revision into a later candidate.
- No artifact was published, signed, or deployed by this certification.

## Protocol truth

WireGuard is the primary Linux protocol. The normal Flutter -> backend profile ->
helper IPC path is implemented. The candidate source and release bundle require
helper contract 13. The rebuilt ARM64 package passed install, helper/service and
socket validation, malformed and unauthorized IPC rejection, verifier, bounded
application launch, same-version upgrade, purge, and networking-residue checks
in a fresh Ubuntu 24.04 ARM64 systemd container.

OpenVPN and IKEv2 are outside the Linux v1 release boundary. They remain Coming
soon or unavailable and must fail closed regardless of installed binaries,
legacy metadata, or retained future implementation source.

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
  13, systemd, systemd-resolved, nftables, and tmpfiles. Neither package depends
  on OpenVPN, strongSwan, or NetworkManager. The exact-head native ARM64 and
  amd64 artifacts have not been published or deployed.
- The packaged release Flutter binary remained running for a bounded ten-second
  Xvfb launch in the clean ARM64 container. Headless graphics and keyring
  warnings are environment diagnostics; no crash was observed.
- The staging app was rebuilt from this exact SHA and the profile smoke passed.
  The WireGuard proof reached connected state, completed the evidence hold, and
  disconnected successfully with IPv6 recovery. SecureWave-owned WireGuard
  residue checks passed. The overall proof remains blocked by two pre-existing
  unqualified IKEv2 policy rules reported by the host verifier; ownership is
  unproven and no cleanup was performed. This is an environment gate, not
  evidence to enable IKEv2.

## Artifact and platform limits

- Both Linux `.deb` entries remain `coming_soon` in the public manifest.
  Exact-SHA package workflow evidence is retained separately; neither artifact
  is public because production image/deployment access is unavailable and the
  host residue gate remains unresolved.

## Current private x64 workflow evidence

The exact-head x64 evidence and checksum belong in the private GitHub Actions
run and PR review record; they are not a public download. The workflow proves
x86_64/amd64 ELF payloads, contract 13, declared dependencies, ephemeral
install, active helper/socket, structural verifier, bounded app launch, purge,
and networking residue checks. It does not prove live protocol routing or
release readiness.
- Portable archives are UI/runtime-independent packaging and do not install the
  privileged Linux helper.
- Windows and macOS VPN tunneling have no release claim from this pass.

## Canonical branch model

`master` is canonical. Focused work is performed on short-lived branches, based
on updated `origin/master`, and merged through a single review. Documentation and
release commands must not instruct users to treat a feature branch as canonical.

## Install the verified private ARM64 workflow package

```bash
evidence_dir="/private/path/securewave-linux-arm64-deb-evidence"
deb="$evidence_dir/securewave-linux-arm64.deb"
(cd "$evidence_dir" && sha256sum --check securewave-linux-arm64.deb.sha256)
sudo apt install "$deb"
systemctl is-enabled securewave-helper.service
systemctl is-active securewave-helper.service
cat /usr/local/libexec/securewave-wg-quick.contract
```

The checksum file and package-embedded source SHA must match the retained CI run
for the reviewed head. Never substitute evidence from an earlier rebuild.

Upgrade with `sudo apt install /path/to/securewave-vpn_NEW.deb`; purge with
`sudo apt purge securewave-vpn`, then run the disconnected runtime verifier and
check that the helper socket, service payload, and contract are gone. An ARM64
package cannot be installed on an x86_64 host; use the matching architecture.
