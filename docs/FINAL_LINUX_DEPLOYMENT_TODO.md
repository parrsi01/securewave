# Final Linux Deployment TODO

Status date: 2026-06-29

## Current Count

- Immediate Linux demo-testing blockers: 1
- Final Linux deployment/release blockers: 4
- Non-blocking cleanup backlog: 1

## Verified Ready

- `scripts/devops_preflight.sh` passed.
- Full backend test suite passed: `321 passed`.
- Flutter app checks passed: `flutter analyze` clean and `flutter test` passed.
- Linux runtime verifier passed with helper contract `7`, prompt-free polkit helper authorization, and no stale tunnel state.
- Linux release build passed and produced `securewave_app/build/linux/arm64/release/bundle/securewave_app`.
- Debian package build passed and produced `securewave_app/build/packaging/securewave-vpn_4.0.0+1_arm64.deb`.
- Package contents include the desktop launcher, SecureWave helper, helper contract, and `50-securewave-wg.rules`.
- Open Dependabot alert count is `0`.

## Remaining Blockers

1. Stable live demo credentials are not configured on this machine.

   `scripts/demo_preflight.sh --skip-build` currently has one blocker: no
   `DEMO_EMAIL` / `DEMO_PASSWORD`, no `SECUREWAVE_TEST_EMAIL` /
   `SECUREWAVE_TEST_PASSWORD`, and no `SECUREWAVE_CERT_AUTH_FILE`.

2. Connected real-tunnel proof still needs to be run after credentials exist.

   The host is clean and helper authorization works, but `demo_preflight`
   warns that real tunnel egress was skipped because `sw-wg` is not active.
   Rerun the go/no-go check while the app is connected.

3. Production release prerequisites are not configured locally.

   `scripts/release_preflight.sh` correctly blocks without production SMTP
   settings, `AUTH_ENCRYPTION_KEY`, `WG_ENCRYPTION_KEY`, and a `v*` release
   tag.

4. Branch package version must be reconciled with the live download manifest.

   The public download manifest advertises `4.0.0+2`, but
   `securewave_app/pubspec.yaml` currently builds `4.0.0+1`. Before publishing
   another Linux artifact, decide whether this branch should be bumped to the
   current public version or whether the public artifact came from a different
   release source.

## Non-Blocking Cleanup Backlog

- Flutter dependency modernization remains after demo readiness. Current tests
  pass, but `flutter pub get` reports newer incompatible package versions.

## Commands For Final Linux Device Test

After creating the stable live credential file:

```bash
export SECUREWAVE_CERT_AUTH_FILE=securewave_private/live_certification_account.env
bash scripts/demo_preflight.sh --skip-build
```

After connecting in the Linux app:

```bash
bash scripts/demo_preflight.sh --live-go-no-go --skip-build
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
