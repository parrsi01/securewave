# SecureWave Linux Demo Runbook

This runbook is for the Flutter Linux desktop demo against the live API:
`https://api.securewaveapp.com/api`.

## Primary Path: Real Tunnel

The demo path is the live product path: Flutter Linux app, live API, real
WireGuard tunnel, real egress, real usage, and real disconnect cleanup. Run it on
the local console, not over SSH or any control channel that would be lost if the
tunnel takes over default routing.

Start the app without simulation:

```bash
cd securewave_app
flutter run -d linux
```

Presentation Mode still exists, but only as a visibly labeled emergency fallback
when a machine cannot run the real tunnel. It must not hide a failed P0/P1
readiness check.

```bash
cd securewave_app
flutter run -d linux --dart-define=SECUREWAVE_SIMULATE_TUNNEL=true
```

The fallback banner says:

```text
Simulated tunnel — presentation mode. Not a real VPN.
```

The connected label reads `Simulated (not encrypted)`. This mode does not call
`pkexec`, does not create `sw-wg`, does not reroute traffic, and does not report
fake tunnel usage to the backend.

## Preflight

Run this before rehearsals and before the demo:

```bash
bash scripts/demo_preflight.sh
```

For a dedicated demo account:

```bash
DEMO_EMAIL="demo@example.com" DEMO_PASSWORD="..." bash scripts/demo_preflight.sh
```

To clear stale demo-account devices:

```bash
DEMO_EMAIL="demo@example.com" DEMO_PASSWORD="..." \
  bash scripts/demo_preflight.sh --revoke-devices
```

To clean leftover WireGuard interfaces or loaded `wg-quick@*.service` units:

```bash
bash scripts/demo_preflight.sh --cleanup
```

The preflight checks live API health, email health visibility, the downloads
manifest, live Linux server inventory, demo-account device capacity, host
WireGuard residue, SecureWave helper contract version, prompt-free helper
authorization through PolicyKit, optional active-tunnel egress, and a prebuilt
Linux release bundle.

For final go/no-go, connect the real tunnel first and then run:

```bash
bash scripts/demo_preflight.sh --live-go-no-go
```

That mode fails if the active `sw-wg` tunnel is missing, DNS does not resolve,
the live API is unreachable through the tunnel, public egress cannot be observed,
or `/api/health/email` is not healthy.

## Cold Machine Dependencies

Install the Linux Flutter desktop build prerequisites before demo day:

```bash
sudo apt update
sudo apt install -y clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev
```

Then warm the build:

```bash
cd securewave_app
flutter pub get
flutter build linux --release
```

## Rehearsal Gate

The rehearsal must pass twice in a row:

1. `bash scripts/demo_preflight.sh --revoke-devices`
2. Start the app without `SECUREWAVE_SIMULATE_TUNNEL`.
3. Log in with the demo account.
4. Confirm servers, account, and usage load from the live API.
5. Connect the real tunnel with no password prompt.
6. Run `bash scripts/demo_preflight.sh --live-go-no-go` while connected.
7. Disconnect and confirm no WireGuard interface exists:

```bash
ip -o link show type wireguard
```

Before connecting the real tunnel:

```bash
python3 scripts/linux_vpn_runtime_verifier.py --json --pkexec-timeout 60
```

After connect, verify the API remains reachable and egress moved through the
tunnel:

```bash
curl -fsS https://api.securewaveapp.com/api/health
curl -fsS https://api.ipify.org
ip route get 1.1.1.1
```

If real tunnel checks fail, stop the demo path and fix the product path. Use
Presentation Mode only as a labeled fallback for a machine-specific runtime
blocker.

## PolicyKit Install Check

The production `.deb` installs `50-securewave-wg.rules` into
`/etc/polkit-1/rules.d/` and reloads PolicyKit when systemd is present. On an
installed host, this command must return immediately without a password prompt:

```bash
pkexec --disable-internal-agent /usr/local/libexec/securewave-wg-quick probe wireguard
```

The rule is scoped to `/usr/local/libexec/securewave-wg-quick` plus `wg show`;
it does not authorize arbitrary `pkexec` commands.

## Recovery

If the app or tunnel path stalls:

```bash
pkexec --disable-internal-agent /usr/local/libexec/securewave-wg-quick policy-clear-link sw-wg
python3 scripts/linux_vpn_runtime_verifier.py --json --pkexec-timeout 60
```

If `wg-quick@*.service` is present:

```bash
systemctl list-units --type=service --all 'wg-quick@*.service'
sudo systemctl stop wg-quick@NAME.service
```

Keep the public demo on the real tunnel unless a machine-specific blocker forces
the labeled Presentation Mode fallback.
