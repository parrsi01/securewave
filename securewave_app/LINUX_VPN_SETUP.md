# Linux VPN Setup

SecureWave v1 is Linux desktop first. WireGuard is the primary public runtime
path. The Flutter MethodChannel writes a backend-issued profile under the
user's SecureWave config directory, then asks the installed SecureWave helper to
bring up the `sw-wg` interface through PolicyKit.

## Runtime Model

- MethodChannel: `securewave/vpn` (`isAvailable`, `connect`, `disconnect`,
  `getStatus`, `getTrafficStats`)
- Public v1 protocol: WireGuard
- Interface: `sw-wg`
- Config file: `~/.config/securewave/sw-wg.conf`
- Privileged helper: `/usr/local/libexec/securewave-wg-quick`
- Helper contract: `/usr/local/libexec/securewave-wg-quick.contract`
- PolicyKit rule: `/etc/polkit-1/rules.d/50-securewave-wg.rules`

The `.deb` package installs the helper, contract, and PolicyKit rule. The rule
is scoped to `/usr/local/libexec/securewave-wg-quick` and `wg show`; it does not
authorize arbitrary `pkexec` commands.

## Requirements

- Install the SecureWave `.deb` package, not only a raw Flutter bundle.
- `wireguard-tools` must be installed (`wg`, `wg-quick`).
- PolicyKit must be available. With the packaged rule installed, authorized
  users should not see an interactive password prompt for the SecureWave helper.
- A signed-in account must receive a real WireGuard profile from the backend.

## Verification

Check that the installed helper and contract are present:

```bash
test -x /usr/local/libexec/securewave-wg-quick
cat /usr/local/libexec/securewave-wg-quick.contract
```

Check prompt-free PolicyKit authorization for the helper:

```bash
pkexec --disable-internal-agent /usr/local/libexec/securewave-wg-quick probe wireguard
```

Connect in the app, then verify runtime evidence:

```bash
wg show sw-wg
ip route get 1.1.1.1
curl -fsS https://api.securewaveapp.com/api/health
```

`ip route get 1.1.1.1` should route through `sw-wg` while connected. The live
API health check must still work through the tunnel.

## Config file permissions

The app writes runtime configs under `~/.config/securewave/` and sets config
permissions to `0600`. The helper refuses config and runtime paths outside the
allowed SecureWave locations.

## Manual cleanup

If the app exits during a tunnel transition, clear the SecureWave WireGuard
link and policy state:

```bash
pkexec --disable-internal-agent /usr/local/libexec/securewave-wg-quick policy-clear-link sw-wg
```

If a host-level `wg-quick@*.service` exists, stop that explicit systemd unit
after confirming it is not needed by another service:

```bash
systemctl list-units --type=service --all 'wg-quick@*.service'
sudo systemctl stop wg-quick@NAME.service
```

Do not enable OpenVPN or IKEv2 as a workaround for public v1 WireGuard runtime
failures. Fix the WireGuard helper, packaging, backend profile, or host network
state first.
