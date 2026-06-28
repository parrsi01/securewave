# SecureWave Linux Demo Runbook

This runbook is for the Flutter Linux desktop demo against the live API:
`https://api.securewaveapp.com/api`.

## Recommended Demo Mode

Use Presentation Mode for the audience-facing connect/disconnect flow:

```bash
cd securewave_app
flutter run -d linux --dart-define=SECUREWAVE_SIMULATE_TUNNEL=true
```

Presentation Mode keeps login, server catalog, account, and usage on the live
API. Only the tunnel is simulated. The app shows:

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

The preflight checks live API health, the downloads manifest, live Linux server
inventory, demo-account device capacity, host WireGuard residue, SecureWave
helper contract version, and a prebuilt Linux release bundle.

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
2. Start the app with `--dart-define=SECUREWAVE_SIMULATE_TUNNEL=true`.
3. Log in with the demo account.
4. Confirm servers, account, and usage load from the live API.
5. Connect and verify the simulated warning remains visible.
6. Disconnect and confirm no WireGuard interface exists:

```bash
ip -o link show type wireguard
```

## Real Tunnel Segment

Show a real WireGuard tunnel only as a deliberate local-console segment. Do not
run this segment over SSH or while relying on the same network path for screen
share control.

Before showing the real tunnel:

```bash
python3 scripts/linux_vpn_runtime_verifier.py --json --pkexec-timeout 60
```

Run the app without Presentation Mode:

```bash
cd securewave_app
flutter run -d linux
```

After connect, verify the API remains reachable and egress moved through the
tunnel:

```bash
curl -fsS https://api.securewaveapp.com/api/health
curl -fsS https://ifconfig.me
ip route get 1.1.1.1
```

If API reachability fails through the tunnel, stop the real-tunnel segment and
use Presentation Mode.

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

Keep the public demo in Presentation Mode unless the real-tunnel checks pass on
the local console immediately before the segment.
