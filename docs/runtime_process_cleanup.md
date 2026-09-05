# Runtime Process Cleanup

Use this when validating the Linux Flutter app before a manual QA run.

## Check App Processes

```bash
pgrep -af securewave_app || true
```

Expected result before launch: no `securewave_app` process.

Expected result after launch: one `securewave_app` process and one window. A
second launch should present the existing window, not start another app engine.

## Clean Stale Local Runtime Files

These files are generated during manual runs and should not be committed:

```bash
rm -f .uvicorn.pid
rm -f securewave_app/flutter-run.log securewave_app/flutter_01.log securewave_app/flutter_02.log
rm -f static/flutter-run.log static/flutter_01.log static/flutter_02.log static/custom_lint.log
```

## VPN Helper Checks

```bash
which wg-quick openvpn swanctl ipsec pkexec || true
ip link show securewave || true
pgrep -af 'securewave-openvpn|securewave.ovpn' || true
```

Do not kill a system OpenVPN or WireGuard server process unless it is clearly a
SecureWave client process from the current test run.

## Live Control-Plane Smoke

Before opening the app for a manual run, verify the live backend paths used by
the Flutter client:

```bash
python3 scripts/live_flutter_runtime_smoke.py --profile-repeats 3
```

The script registers or reuses a disposable account, logs in, fetches account
and usage state, lists servers, requests a WireGuard profile, and verifies that
OpenVPN remains unavailable. It never starts a local tunnel and does not print
bearer tokens. A non-200 WireGuard profile result is a release blocker; the
expected OpenVPN result in this baseline is a typed 400/503 rejection. IKEv2
may still return a typed non-200 until the Linux strongSwan path is implemented.
