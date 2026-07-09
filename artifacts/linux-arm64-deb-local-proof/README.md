# Linux ARM64 Deb Local Proof

Date: 2026-07-09

Branch: `codex/linux-arm64-deb-local-proof`

This evidence captures an ARM64 local Debian package build attempt for
SecureWave on Ubuntu 24.04 ARM64. It is ARM64-only evidence and does not claim
or build x64 artifacts.

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
- Package size: 15,195,350 bytes
- Package architecture: `arm64`
- Package version: `4.0.0+1`

## Result

Blocked before install proof.

The package is a valid ARM64 Debian package and contains the SecureWave UI
binary plus desktop entry, but it does not contain the required Linux helper
payload or systemd/tmpfiles integration needed to prove no-connect-prompt full
VPN operation from the package.

Missing helper/service payload:

- `/usr/local/libexec/securewave-helperd`
- `/usr/local/libexec/securewave-wg-quick`
- `/usr/local/libexec/securewave-wg-quick.contract`
- `/usr/lib/systemd/system/securewave-helper.service`
- `/usr/lib/tmpfiles.d/securewave-helper.tmpfiles`

Missing package dependency metadata:

- `Depends` field
- `wireguard-tools`
- `openvpn`
- `network-manager`
- `network-manager-strongswan`
- `strongswan`
- `strongswan-swanctl`
- `strongswan-charon`
- `libcharon-extra-plugins`
- `libstrongswan-extra-plugins`
- `iproute2`
- `iptables`
- `acl`
- `systemd`

## Proof Status

- Build proof: passed for ARM64 `.deb` creation.
- Helper payload proof: failed, helper/service payload missing from package.
- Install proof: not run because helper payload proof failed.
- Runtime verifier: not run because package install proof was blocked.
- Launch proof: not run because package install proof was blocked.
- Uninstall proof: not run because package install proof was blocked.
- Live WireGuard/OpenVPN/IKEv2 proof: blocked; no live proof was attempted.

## Evidence Files

- `uname-m.txt`
- `dpkg-architecture.txt`
- `os-release.txt`
- `systemctl-version.txt`
- `tool-availability.txt`
- `build-script-syntax.txt`
- `build.log`
- `generated-debs-build.txt`
- `generated-debs-static-downloads.txt`
- `deb-candidates-ls.txt`
- `package-file.txt`
- `package-size.txt`
- `package-info.txt`
- `package-contents.txt`
- `package-requirements-check.txt`
