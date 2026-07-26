# SecureWave - Current Release Status

Last audited: 2026-07-26 UTC

## Current release lineage

- Branch: `codex/production-wireguard-beta-prep`
- Provider-migration baseline SHA:
  `43ccbb0ea29f604b654d62de3f8bcd98aa932d06`
- Linux ARM64 package source SHA:
  `7595425fba5ae542d72153e0b3f50e91bb06a05e`
- Public download commit:
  `7e4ed5be3d9d88170ace2dabadb2cf6296c04e15`
- Hetzner operator-contract follow-up:
  `43ccbb0ea29f604b654d62de3f8bcd98aa932d06`
- Application/package version: `4.0.0+3`

The package source SHA intentionally predates the publication commit. The
publication commit adds the already-verified binary, checksum, manifest, and
website metadata; it does not claim that the binary was built from the later
metadata-only commit. Documentation or audit-tool follow-ups may have a newer
repository SHA without changing the published package lineage.

## Production and provider truth

Hetzner Cloud is the only active SecureWave infrastructure provider.

- `securewaveapp.com`, `www.securewaveapp.com`, and
  `api.securewaveapp.com` resolve to the Hetzner production server
  `securewave-prod`.
- `staging-api.securewaveapp.com` resolves to the Hetzner staging API server.
- Production and API health endpoints return HTTP 200.
- The obsolete provider credential was removed from GitHub Actions.
- Current tracked source, CI/CD, infrastructure, and operational documentation
  contain no active retired-provider integration.
- The former external subscription is cancelled.

The active fleet can be audited without copying a raw token when an
authenticated `hcloud` context is available:

```bash
python3 infrastructure/hetzner/audit_vpn_fleet.py \
  --only-running \
  --name-prefix securewave \
  --json-out /tmp/securewave-fleet-audit.json
```

The 2026-07-26 audit found four running SecureWave-prefixed Hetzner servers.
Production, staging API, and staging WireGuard had attached firewalls. The
separate test-client host did not have an attached firewall; that is a
test-environment configuration finding, not evidence about production ingress.
The production host also passed `docker compose config --quiet` against the
protected production environment file. That validation did not pull an image
or change a running service.

The obsolete mutable production watchdog was retired and replaced by the
repository-provided `securewave-health-monitor.timer`. Its unprivileged,
read-only probe checks the existing local health, readiness, and guarded
download-manifest routes every five minutes. The replacement passed a live
production invocation. This does not prove external alert delivery or complete
production observability.

## Public Linux ARM64 beta

The WireGuard-only Linux ARM64 beta is publicly available:

- URL:
  `https://securewaveapp.com/downloads/securewave-linux-arm64.deb`
- Package: `securewave-vpn`
- Version: `4.0.0+3`
- Architecture: `arm64`
- SHA-256:
  `b9885574860b434bf0b9ad1187fd7ebe93f548001d25b759299f7a00ec7dc8b2`
- Dependencies: `wireguard-tools`, `iproute2`, `iptables`, `nftables`, `acl`,
  `systemd`, and `systemd-resolved`

The public manifest exposes exactly three desktop choices:

- macOS universal: `coming_soon`, URL `#`
- Windows x64: `coming_soon`, URL `#`
- Linux ARM64: `available`, guarded local download URL and matching checksum

The two obsolete Linux portable archives were removed from the public download
directory and their former URLs return HTTP 404.

## Package and CI evidence

The retained ARM64 workflow proved:

- native ARM64 package and ELF architecture;
- embedded package source SHA and clean-source marker;
- contract-13 helper payload;
- WireGuard-only runtime dependencies;
- package install, helper/socket startup, structural verifier, and bounded
  non-root application launch;
- package purge and networking-residue cleanup;
- manifest checksum and guarded-publication contract.

The publication commit passed repository guards, Python tests, dependency and
code security checks, Flutter analysis/tests, Android compilation, Linux
release build, Docker build, and the ARM64 package lifecycle workflow. The
Hetzner operator follow-up passed the same repository CI checks.

## Protocol truth

WireGuard is the only Linux v1 protocol advertised by the public beta.
OpenVPN and IKEv2 remain unavailable in the Linux v1 product boundary and must
fail closed regardless of legacy host packages, retained future source, or
server metadata.

Historical staging evidence for source SHA
`59d524329cff8ca43fc066447e66c6b470b222d5` proves an earlier WireGuard
connect/hold/disconnect run. It is not fresh runtime evidence for the published
package source SHA. The same historical environment reported unresolved
host-level IKEv2 residue at preference/table 220; no ownership was established
and no cleanup was performed. This limitation must not be used to enable or
advertise IKEv2.

## Platform limits and remaining work

- Linux x64 remains unpublished and `coming_soon`; no x64 public package claim
  is made.
- macOS and Windows remain `coming_soon`.
- The public ARM64 package has CI lifecycle evidence, but a friend/user
  acceptance test on the downloaded public file remains valuable beta feedback,
  not a prerequisite for accurately serving the verified artifact.
- Fresh final-package staging tunnel proof remains separate from package
  lifecycle and publication proof.
- External alert delivery and monitoring ownership, external load testing, and
  production container migration remain operations work; they are not
  attributed to the retired provider.

## Install and verify

```bash
curl -fLO https://securewaveapp.com/downloads/securewave-linux-arm64.deb
echo "b9885574860b434bf0b9ad1187fd7ebe93f548001d25b759299f7a00ec7dc8b2  securewave-linux-arm64.deb" \
  | sha256sum --check
sudo apt install ./securewave-linux-arm64.deb
systemctl is-enabled securewave-helper.service
systemctl is-active securewave-helper.service
cat /usr/local/libexec/securewave-wg-quick.contract
```

Upgrade with `sudo apt install ./securewave-linux-arm64.deb`. Purge with
`sudo apt purge securewave-vpn`, then verify that the helper socket, service
payload, contract file, routes, rules, and firewall residue are absent.

## Branch model

`master` remains canonical. Focused work is performed on reviewed branches and
merged through the repository review process. Production state must be
described by public runtime evidence and exact-SHA CI, not by branch names.
