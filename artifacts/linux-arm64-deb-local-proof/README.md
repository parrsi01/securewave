# Linux ARM64 Deb Local Proof After Packaging Fix

Date: 2026-07-09

Branch: `codex/fix-linux-deb-helper-payload`

This evidence captures an ARM64-only local Debian package build after restoring
the SecureWave Linux helper payload and dependency metadata into the `.deb`
packaging path. It does not build or claim x64 artifacts, does not publish
release artifacts, and does not mark the package release-ready.

## Environment

- `uname -m`: `aarch64`
- `dpkg --print-architecture`: `arm64`
- OS: Ubuntu 24.04.4 LTS
- systemd: 255
- Required local tools were present: `flutter`, `dpkg-deb`, `wg-quick`,
  `openvpn`, and `nmcli`.

## Package Built

- Package path:
  `securewave_app/build/packaging/securewave-vpn_4.0.0+1_arm64.deb`
- Package size: 15,255,992 bytes
- Package architecture: `arm64`
- Package version: `4.0.0+1`

## Passing Proof

- Build proof passed for ARM64 `.deb` creation.
- Package metadata includes the required full VPN runtime dependencies.
- Package payload includes:
  - SecureWave UI binary
  - desktop entry
  - `securewave-helperd`
  - `securewave-wg-quick`
  - `securewave-wg-quick.contract`
  - `securewave-helper.service`
  - `securewave-helper.tmpfiles`
  - `/usr/lib/tmpfiles.d/securewave-helper.conf`
- Control scripts include:
  - `postinst`
  - `prerm`
  - `postrm`
- `postinst` installs helper payload into `/usr/local/libexec`, installs the
  helper service into `/etc/systemd/system`, installs tmpfiles config into
  `/usr/lib/tmpfiles.d`, seeds `/etc/securewave/helper-users`, creates
  `/run/securewave`, removes the old polkit rule, reloads systemd, and enables
  and restarts `securewave-helper.service` when systemd is available.
- `postrm` removes the helper socket, helper binaries, contract, service,
  tmpfiles config, helper-users file, and old polkit rule.

## Blocked Proof

Install proof could not be completed in this Codex shell because `sudo` requires
an interactive password:

```text
sudo: a password is required
```

The host already has an older `securewave-vpn` package installed:

```text
install ok installed 4.0.0+2
```

Because the new `4.0.0+1` package was not installed, the existing
`/usr/bin/securewave-vpn` binary was not used as launch proof for this package.

## Proof Status

- Build proof: passed.
- Helper payload proof: passed at package-content level.
- Depends metadata proof: passed.
- Install proof: blocked by non-interactive sudo password requirement.
- Helper service proof: not run because install proof was blocked.
- Helper socket proof: not run because install proof was blocked.
- Runtime verifier: not run because install proof was blocked; additionally,
  `scripts/linux_vpn_runtime_verifier.py` is absent on this branch.
- Launch proof: not run because the package under test was not installed.
- Uninstall proof: not run because the package under test was not installed.
- Live WireGuard/OpenVPN/IKEv2 proof: not attempted.

## Evidence Files

- `uname-m.txt`
- `dpkg-architecture.txt`
- `os-release.txt`
- `systemctl-version.txt`
- `tool-availability.txt`
- `build-after-fix.log`
- `generated-debs-build-after-fix.txt`
- `package-file-after-fix.txt`
- `package-size-after-fix.txt`
- `package-info-after-fix.txt`
- `package-contents-after-fix.txt`
- `control-after-fix/`
- `package-requirements-check-after-fix.txt`
- `install-after-fix.log`
- `sudo-noninteractive-check.txt`
- `dpkg-status-after-install-attempt.txt`
- `securewave-vpn-command-after-install-attempt.txt`
- `runtime-verifier-file-check.txt`
