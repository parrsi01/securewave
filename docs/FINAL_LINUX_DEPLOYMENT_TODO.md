# Final Linux Deployment TODO

Status date: 2026-06-29

## Current Count

- Immediate Linux demo-testing blockers on this host: 0
- Final Linux deployment/release blockers: 1
- Non-blocking cleanup backlog: 1

## Verified Ready

- `scripts/devops_preflight.sh` passed.
- Full backend test suite passed: `321 passed`.
- Flutter app checks passed: `flutter analyze` clean and `flutter test` passed.
- Linux runtime verifier passed with helper contract `7`, prompt-free polkit helper authorization, and no stale tunnel state.
- Linux release build passed and produced `securewave_app/build/linux/arm64/release/bundle/securewave_app`.
- Debian package build passed and produced `securewave_app/build/packaging/securewave-vpn_4.0.0+2_arm64.deb`.
- Package contents include the desktop launcher, SecureWave helper, helper contract, and `50-securewave-wg.rules`.
- Open Dependabot alert count is `0`.
- The branch app package version is aligned with the live download manifest at
  `4.0.0+2`.
- `scripts/final_linux_demo_gate.sh` automates the repeatable Linux demo gate.
- A stable live certification account has been provisioned on this host and
  stored in the ignored local credential file. The default final Linux gate now
  passes with `0` blockers.
- Connected real-tunnel proof passed through the automated gate with SecureWave
  OpenVPN active on `tun0`, verified tunnel routing, live API reachability, DNS,
  and public egress.
- The Flutter Linux runner now exposes native runtime status so the UI can
  restore connected state when a real tunnel is already active.

## Remaining Blockers

1. Production release prerequisites are not configured locally.

   `scripts/release_preflight.sh` correctly blocks without production SMTP
   settings, `AUTH_ENCRYPTION_KEY`, `WG_ENCRYPTION_KEY`, and a `v*` release
   tag.

## Non-Blocking Cleanup Backlog

- Flutter dependency modernization remains after demo readiness. Current tests
  pass, but `flutter pub get` reports newer incompatible package versions.

## Commands For Final Linux Device Test

One-command default gate:

```bash
bash scripts/final_linux_demo_gate.sh
```

To create the ignored stable live credential file from environment variables:

```bash
DEMO_EMAIL="demo@example.com" DEMO_PASSWORD="..." \
  bash scripts/final_linux_demo_gate.sh --write-auth-file
```

To provision one stable live certification account automatically on a fresh
machine:

```bash
bash scripts/final_linux_demo_gate.sh --provision-live-account
```

After creating or provisioning the stable live credential file:

```bash
export SECUREWAVE_CERT_AUTH_FILE=securewave_private/live_certification_account.env
bash scripts/demo_preflight.sh --skip-build
```

After connecting in the Linux app:

```bash
bash scripts/demo_preflight.sh --live-go-no-go --skip-build
```

Or with the automated wrapper:

```bash
bash scripts/final_linux_demo_gate.sh --connected
```

For app-driven protocol proof:

```bash
python3 scripts/linux_app_vpn_tunnel_proof.py \
  --auth-file securewave_private/live_certification_account.env \
  --protocol wireguard \
  --protocol openvpn \
  --protocol ikev2 \
  --hold-seconds 20 \
  --evidence-timeout 180 \
  --pkexec-timeout 20 \
  --json
```

Or with the automated wrapper:

```bash
bash scripts/final_linux_demo_gate.sh --app-proof
```
