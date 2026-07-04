# Linux VPN Setup

SecureWave v1 is Linux desktop first. WireGuard is the primary production
runtime path. OpenVPN is supported only when backend server metadata and local
runtime checks both pass. IKEv2 uses NetworkManager strongSwan and is reported
connected only when route, DNS, and XFRM ESP evidence all pass.

## Runtime Model

- MethodChannel: `securewave/vpn` (`isAvailable`, `connect`, `disconnect`,
  `getStatus`, `getTrafficStats`)
- Full routing package: SecureWave `.deb`
- Portable packages: AppImage, tarball, or zip UI only unless the `.deb`
  helper service is already installed
- Helper service: `securewave-helper.service`
- Helper daemon: `/usr/local/libexec/securewave-helperd`
- Helper script: `/usr/local/libexec/securewave-wg-quick`
- Helper contract: `/usr/local/libexec/securewave-wg-quick.contract`
- Helper socket: `/run/securewave/helper.sock`
- Runtime group: `securewave`
- WireGuard interface: `sw-wg`
- WireGuard config file: `~/.config/securewave/sw-wg.conf`

The `.deb` package installs the app, root-owned SecureWave helper service,
helper executable, contract file, systemd unit, tmpfiles runtime directory
configuration, and VPN runtime package dependencies. Package installation may
ask for normal OS authorization once. Connect in the app should not ask for
sudo, pkexec, or a password after the `.deb` is installed.

## Requirements

- Install the SecureWave `.deb` package for full-device routing.
- Use portable packages only for the UI unless the helper service is already
  installed.
- The backend must return a real profile for the selected protocol.
- WireGuard requires `wireguard-tools`; OpenVPN requires `openvpn`; IKEv2 must
  remain unavailable unless local services and live evidence prove it works.

## Verification

Check that the installed helper service and contract are present:

```bash
test -x /usr/local/libexec/securewave-helperd
test -x /usr/local/libexec/securewave-wg-quick
cat /usr/local/libexec/securewave-wg-quick.contract
systemctl status securewave-helper.service --no-pager
test -S /run/securewave/helper.sock
```

Connect in the app, then verify WireGuard runtime evidence:

```bash
ip link show sw-wg
ip route get 1.1.1.1
curl -fsS https://api.securewaveapp.com/api/health
wg show sw-wg transfer
```

`ip route get 1.1.1.1` should route through `sw-wg` while connected. The live
API health check must still work through the tunnel. Traffic counters should be
readable; if they are not, the app should show diagnostics instead of marking
the tunnel as proven.

## Config File Permissions

The app writes runtime configs under `~/.config/securewave/` and sets config
permissions to `0600`. The helper daemon refuses config, PID, log, auth, and CA
paths outside approved SecureWave runtime locations.

## Manual Cleanup

The normal path is app disconnect through the helper service. If the service or
host state needs repair after a failed transition, reinstall the `.deb` or
restart the helper service:

```bash
sudo systemctl restart securewave-helper.service
python3 scripts/linux_vpn_runtime_verifier.py --json
```

If a host-level `wg-quick@*.service` exists, stop that explicit systemd unit
after confirming it is not needed by another service:

```bash
systemctl list-units --type=service --all 'wg-quick@*.service'
sudo systemctl stop wg-quick@NAME.service
```

Treat IKEv2 as connected only when NetworkManager VPN, route/DNS, and XFRM ESP
evidence are all present. Do not work around protocol failures by broadening
app-side privilege. Fix the helper service, packaging, backend profile, or host
network state first.
