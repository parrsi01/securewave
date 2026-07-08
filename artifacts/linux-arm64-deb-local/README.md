# SecureWave Linux ARM64 `.deb` Local Evidence

Generated: 2026-07-08 UTC

Scope: local ARM64 packaging evidence only. This is not x64 evidence and not a
published release artifact.

## Host Verification

```text
$ uname -m
aarch64

$ dpkg --print-architecture
arm64
```

## Branch

```text
codex/linux-arm64-deb-local-evidence
```

`master` was synced first:

```text
$ git pull --ff-only origin master
Already up to date.
```

## Initial Package Inspection

The first build from the current `master` packaging script produced:

```text
securewave_app/build/packaging/securewave-vpn_4.0.0+1_arm64.deb
```

Initial package truth:

- ARM64 `.deb` was built.
- App binary was present.
- Desktop entry was present.
- Helper payload was missing:
  - `securewave-helperd`
  - `securewave-wg-quick`
  - `securewave-wg-quick.contract`
  - `securewave-helper.service`
  - `securewave-helper.tmpfiles`
- Runtime `Depends` field was missing.

Fix decision: helper/service payload was missing, so packaging assets and the
Linux helper build target were restored from prior SecureWave history and
`securewave_app/scripts/build_deb.sh` was updated to package the helper payload
locally without publishing to `static/downloads`.

## Rebuilt Local Package

Command:

```bash
cd securewave_app
bash scripts/build_deb.sh
cd ..
```

Result:

```text
OK: Built /home/sp/cyber-course/projects/securewave/securewave_app/build/packaging/securewave-vpn_4.0.0+1_arm64.deb
OK: Local package only; no release artifact was published.
```

Package file:

```text
securewave_app/build/packaging/securewave-vpn_4.0.0+1_arm64.deb
15255926 bytes
sha256 fd0ded7b4eab60995c226e1e35405571cc243c9c69b518576aae2d86c6eed867
```

`file`:

```text
Debian binary package (format 2.0), with control.tar.zst, data compression zst
```

Control metadata:

```text
Package: securewave-vpn
Version: 4.0.0+1
Architecture: arm64
Depends: wireguard-tools, openvpn, network-manager, network-manager-strongswan, strongswan, strongswan-swanctl, strongswan-charon, libcharon-extra-plugins, libstrongswan-extra-plugins, iproute2, iptables, acl, systemd
Description: SecureWave VPN desktop client
```

Maintainer scripts:

```text
postinst
prerm
postrm
```

Required package contents:

```text
./usr/bin/securewave-vpn
./usr/lib/securewave/securewave_app
./usr/share/applications/securewave-vpn.desktop
./usr/lib/securewave/packaging/linux/securewave-helper.service
./usr/lib/securewave/packaging/linux/securewave-helper.tmpfiles
./usr/lib/securewave/packaging/linux/securewave-helperd
./usr/lib/securewave/packaging/linux/securewave-wg-quick
./usr/lib/securewave/packaging/linux/securewave-wg-quick.contract
./usr/lib/tmpfiles.d/securewave-helper.conf
./usr/share/securewave/packaging/linux/securewave-helper.service
./usr/share/securewave/packaging/linux/securewave-helper.tmpfiles
./usr/share/securewave/packaging/linux/securewave-helperd
./usr/share/securewave/packaging/linux/securewave-wg-quick
./usr/share/securewave/packaging/linux/securewave-wg-quick.contract
```

Extracted binary truth:

```text
usr/lib/securewave/securewave_app: ELF 64-bit LSB pie executable, ARM aarch64
usr/share/securewave/packaging/linux/securewave-helperd: ELF 64-bit LSB pie executable, ARM aarch64
usr/share/securewave/packaging/linux/securewave-wg-quick: Bourne-Again shell script
securewave-wg-quick.contract: 9
```

## Optional Install Proof

Install proof was not run because unattended sudo is unavailable:

```text
$ sudo -n true
sudo: a password is required
```

All declared runtime dependency packages were already installed on this VM, but
`dpkg -i`, service status, socket proof, and uninstall cleanup require
privileged installation. Because interactive sudo would block the automation,
the install/service/socket proof remains missing.

## Release Truth

- Built: yes, ARM64 only.
- Helper payload included: yes, after packaging fix.
- Install/service/socket proof: not proven.
- Publishable: no. This package is local evidence only until install,
  `securewave-helper.service`, `/run/securewave/helper.sock`, launch, uninstall,
  and cleanup proof are completed.
