# SecureWave Linux x64 `.deb` clean-VM lifecycle proof

**Status:** completed clean-install and uninstall lifecycle proof. This is package evidence, not live VPN-routing proof or release-publication approval.

## Scope and environment

- Date: 2026-07-12 UTC
- Host: fresh, disposable native x86_64 Hetzner Cloud VM running Ubuntu 24.04 with systemd. Host address, resource identifier, and credentials are intentionally redacted.
- Architecture gate: `uname -m` returned `x86_64`; `dpkg --print-architecture` returned `amd64`; PID 1 was `systemd`.
- Privilege gate: passwordless sudo/root was available.
- Cleanliness gate before transfer: `securewave-vpn` was absent and no SecureWave-named entries were found under `/etc`, `/usr`, `/opt`, or `/run`.
- Production infrastructure and the SecureWave database were not accessed or changed.

## Artifact provenance and integrity

- GitHub Actions run: [29036573515](https://github.com/parrsi01/securewave/actions/runs/29036573515) (`Linux x64 Deb Build Evidence`), completed successfully for commit `d0a13fbf273d51f72e05bf2cbb6f6d48f9f73ea8`.
- Downloaded artifact: `securewave-linux-x64-deb-evidence-1`.
- Package: `securewave-linux-x64.deb`.
- Required and observed SHA-256: `f2718810c7dea6e2c298c159f25d904321423ab3a359c1d1428b3e824d7b4d92`.
- The VM independently recomputed the same SHA-256 before inspection and installation. The hash gate passed before package-manager activity.

## Pre-install inspection

`dpkg-deb` reported:

- Package: `securewave-vpn`
- Version: `4.0.0+1`
- Architecture: `amd64`
- Declared dependency set includes WireGuard, OpenVPN, NetworkManager, strongSwan, ACL support, and systemd.
- Payload count: 56 entries.

The payload contained the expected application launcher and desktop entry (`/usr/bin/securewave-vpn`, `/usr/share/applications/securewave-vpn.desktop`), native app bundle, helper daemon, helper executable, helper-contract file, systemd unit payload, and `/usr/lib/tmpfiles.d/securewave-helper.conf`.

## Install and installed-state checks

The package was installed through the normal APT local-package path:

```text
apt-get install -y /tmp/securewave-linux-x64.deb
```

APT completed `Setting up securewave-vpn (4.0.0+1)` and enabled `securewave-helper.service`.

- `/usr/bin/securewave-vpn` exists and is executable.
- The desktop entry exists and declares `Name=SecureWave VPN`, `Exec=securewave-vpn`, `Type=Application`, and `Categories=Network;Security;`.
- `/usr/local/libexec/securewave-helperd` and `/usr/local/libexec/securewave-wg-quick` exist and are executable.
- `/usr/local/libexec/securewave-wg-quick.contract` contains version `9`.
- `securewave-helper.service` was `enabled` and `active`.
- Service hardening/configuration observed: `User=root`, `Group=securewave`, `RuntimeDirectory=securewave`, `RuntimeDirectoryMode=0750`, `NoNewPrivileges=yes`, and `PrivateTmp=yes`.

## Runtime-directory, socket, and IPC checks

- Stopping the helper removed `/run/securewave`.
- `systemd-tmpfiles --create /usr/lib/tmpfiles.d/securewave-helper.conf` recreated `/run/securewave` as `0750 root:securewave`.
- Restarting the service recreated `/run/securewave/helper.sock` as `0660 root:securewave`.
- A safe IPC negative test sent protocol version `1` with unsupported operation `exec` and a harmless `touch`-style sentinel argument. The daemon returned `code=invalid_operation`, `message=Unsupported helper operation.`, and `ok=false`; the sentinel was absent afterward. This confirms that request was not treated as an arbitrary command.

## Application launch check

The installed launcher was run under Xvfb for 15 seconds with no SecureWave credentials or VPN actions. It remained running until the controlled timeout (`exit 124`). The only output was headless EGL/keyring warnings. This proves that the process launches in a headless test display; it does **not** claim an interactive desktop-session validation, profile acquisition, connection, data transfer, or a live tunnel.

## Runtime verifier availability

The documented live wrapper references `scripts/linux_vpn_runtime_verifier.py --json`, but `scripts/linux_vpn_runtime_verifier.py` was absent from this checkout at test time. It was therefore not run, and this report does not substitute another check as runtime-verifier success.

## Uninstall and cleanup

The package was removed with:

```text
apt-get purge -y securewave-vpn
```

Post-purge checks passed:

- `securewave-vpn` is absent from dpkg.
- `securewave-helper.service` is neither enabled nor active; its unit file is absent.
- Installed helper, helper daemon, helper-contract file, and SecureWave tmpfiles configuration are absent.
- `/run/securewave/helper.sock` and `/run/securewave` are absent.
- No `sw-wg` or `tun*` VPN interface residue was present.
- No WireGuard policy-rule or table-51820 route residue was present; the kernel reported that FIB table 51820 does not exist.
- No SecureWave NetworkManager connection or XFRM state was present.

## Explicit exclusions

No live WireGuard, OpenVPN, or IKEv2 credentials were used. No VPN routing, public-IP, data-usage, or disconnect proof is claimed. The package was not published, no downloads manifest was promoted from beta, and production/database state was not changed.
