# Historical Linux release-status snapshot

Saved 2026-10-06 from the pre-existing local note dated 2026-09-29.
The candidate and pending checks below describe that earlier checkpoint;
this is not the current installed-package or release status. Current candidate
evidence is recorded in [4.0.0+12 verification](releases/4.0.0+12-verification.md).

---

# SecureWave Linux Release Status

**Author:** Simon Parris

**Date:** 2026-09-29

**Release status:** candidate build prepared; installed-app, VPN, and reboot acceptance pending.

## Candidate

- **Version:** 4.0.0+10, from `securewave_app/pubspec.yaml`
- **Accepted core commit:** `7f6ec88e1fb995c4d1acf963308c0983ba9518b4`
- **Rollback tag:** `securewave-linux-core-verified`
- **Package:** `securewave-vpn_4.0.0+10_arm64.deb`
- **Target:** Ubuntu 24.04, ARM64 (`arm64`)
- **Package checks:** release build, Flutter analysis/tests, provenance, archive contents, and secret-pattern scan passed. Installation and runtime release checks are pending.

## Install, launch, and remove

From the directory containing the package, install it with:

```sh
sudo apt install ./securewave-vpn_4.0.0+10_arm64.deb
```

Launch **SecureWave VPN** from the desktop Applications list or run `securewave-vpn`.
The package installs the app under `/usr/lib/securewave`, its launcher at
`/usr/bin/securewave-vpn`, the desktop entry and icon, and the privileged helper
with its systemd service.

Disconnect before removing the package. Removal is supported with
`sudo apt remove securewave-vpn`; `sudo apt purge securewave-vpn` also removes
the helper allowlist and its group. Package removal refuses to proceed while
the `sw-wg` interface is active.

## Runtime requirements and local data

The package depends on WireGuard tools, `iproute2`, `iptables`, systemd,
`systemd-resolved`, GTK 3, libsecret, EGL, and GLES libraries. It needs a
running systemd service manager and a desktop Secret Service session. Flutter,
Dart, the source checkout, and developer environment variables are build-time
tools; the package contains the Flutter application, engine, assets, and
helper payload.

The app stores its login token and per-account WireGuard private key through
Flutter Secure Storage backed by the desktop Secret Service. The temporary
WireGuard configuration is `~/.config/securewave/sw-wg.conf`, created with
mode `0600` and removed on disconnect. The app runs unprivileged; its local
systemd helper performs the privileged WireGuard operations through the
`/run/securewave/helper.sock` socket.

## Verified core flow

The accepted core commit passed production registration, login, and session
validation, followed by production WireGuard provisioning, a real WireGuard
handshake, full-tunnel internet and DNS, real traffic counters, disconnect and
route restoration, reconnect, and logout with and without an active tunnel.
This historical core acceptance does not replace the pending installed-package
and reboot checks for this candidate.

## Current limitations

- This package targets Linux ARM64 and supports WireGuard.
- This package has no automatic updater; upgrades require installing a newer
  package.

## Terms

- **WireGuard:** the VPN protocol that encrypts IP traffic between a client and
  a server using public/private keys.
- **VPN tunnel:** the virtual network link that carries that encrypted traffic.
- **Handshake:** the exchange that establishes a secure WireGuard session with
  a peer.
- **Full-tunnel routing:** sending the device's default internet traffic
  through the VPN tunnel.
- **DNS:** the service that looks up IP addresses for domain names.
- **NAT:** the server-side address translation that lets VPN client traffic
  reach the public internet and receive replies.
- **Helper/privilege boundary:** the unprivileged app asks a restricted local
  service to perform only the privileged WireGuard operations needed by the
  client.
