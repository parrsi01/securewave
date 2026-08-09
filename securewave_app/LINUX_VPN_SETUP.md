# Linux VPN Runtime Setup

SecureWave Linux uses the backward-compatible `securewave/vpn` MethodChannel
and a package-installed, root-owned helper service. The Flutter process never
runs arbitrary privileged commands and does not request elevation at connect
time.

## Runtime boundary

- Socket: `/run/securewave/helper.sock`
- Daemon: `/usr/local/libexec/securewave-helperd`
- Narrow wrapper: `/usr/local/libexec/securewave-wg-quick`
- Contract: `/usr/local/libexec/securewave-wg-quick.contract` (required: `13`)
- Service: `securewave-helper.service`
- Runtime group: `securewave`
- Explicit UID allowlist: `/etc/securewave/helper-users`
- User state: `~/.config/securewave/`, mode `0700`; configs are mode `0600`

Only the architecture-matched Debian package installs this boundary. Portable
tar/zip/AppImage builds are UI-only unless the matching helper is already
installed separately.

## WireGuard beta runtime

- WireGuard requires `wg-quick` and `wg`. Connected status requires
  `sw-wg` plus default-route evidence; cleanup checks interface, rules, table
  51820 routes, and known kill-switch rules.
- OpenVPN and IKEv2 are deferred and are not part of the Linux beta package,
  UI, or acceptance command.
- Missing tools, service/socket, contract, or runtime evidence returns an
  unavailable/error result. The app does not substitute a mock connection in
  live mode.

## Package install

Build only for the current host architecture:

```bash
cd securewave_app
bash scripts/build_deb.sh
```

Install the resulting package on a matching Debian/Ubuntu/systemd host:

```bash
sudo apt install ./build/packaging/securewave-vpn_<version>_<arch>.deb
systemctl is-active securewave-helper.service
stat -c '%U %G %a %n' /run/securewave/helper.sock
cat /usr/local/libexec/securewave-wg-quick.contract
```

A package install authorizes only the invoking non-root user when that identity
is available. It does not automatically authorize every interactive local
account. An administrator must explicitly add any additional user to both the
`securewave` group and the UID allowlist.

## Read-only verifier

Disconnected cleanup mode does not start a tunnel:

```bash
python3 scripts/linux_vpn_runtime_verifier.py
```

Active mode fails unless helper status, route, protocol safety, DNS, counters,
exit-IP change, and data-plane evidence all pass. External probes are never
implicit:

```bash
python3 scripts/linux_vpn_runtime_verifier.py \
  --active-protocol wireguard \
  --external-probes \
  --baseline-exit-ip-file /private/path/baseline-ip.txt
```

The verifier redacts addresses and counter values. Do not commit the baseline
IP file, VPN configs, credentials, private keys, raw route tables, or raw
provider logs.

## App-driven live proof

With an owner-authorized existing login account and an owner-only credential
file, run the real Flutter/native path:

```bash
python3 scripts/linux_app_vpn_tunnel_proof.py \
  --api-base https://api.securewaveapp.com/api \
  --allow-production \
  --auth-file /private/path/live-account.env \
  --protocol wireguard \
  --hold-seconds 60 \
  --evidence-timeout 240 \
  --json
```

This command does not register an account. It logs in, obtains a WireGuard
profile, exercises connect/hold/disconnect, verifies cleanup, and redacts
credentials, addresses, and counters from its report.

## Current certification boundary

An ARM64 package build and payload inspection can be performed on the current
ARM64 host. Helper install, socket, and live routing are blocked without root
access and authorized credentials. Linux x64 requires a clean x86_64 host and
must not be inferred from ARM64 evidence.
