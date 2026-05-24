# SecureWave Linux Runtime QA

Use this checklist for release readiness runs on a real Linux desktop VM.
Do not mark any VPN protocol connected unless the app reports success after the
native helper has created the expected tunnel state.

## Environment

- Linux desktop VM with `DISPLAY` or `WAYLAND_DISPLAY` set.
- `wg-quick` installed for WireGuard.
- `openvpn` installed for OpenVPN.
- `pkexec` available, or run the app with the required privileges.
- `swanctl` and `ipsec` installed before testing IKEv2. The current Linux runner
  still blocks IKEv2 because profile import/start is not wired.
- Live API URL configured with `SECUREWAVE_API_BASE_URL`.
- Real test account available. Do not add credentials to the repo.

## Startup

1. Build or install the Linux app.
2. Launch the app once.
3. Launch it a second time from the same desktop session.
4. Confirm the existing window is presented and only one SecureWave app process
   is running.
5. Close and relaunch three times. The app should not crash, duplicate windows,
   or reset a valid session.

Useful command:

```sh
pgrep -af securewave_app
```

## Auth And Session

1. Register a new test account.
2. Confirm registration either signs in automatically or shows a visible error.
3. Sign out.
4. Sign in with the same account without restarting the app.
5. Close and relaunch the app.
6. Confirm the app restores the session and routes to the VPN screen.
7. Confirm the signed-in account email is visible in the side rail and VPN
   header.

## Servers And Usage

1. Open the VPN screen and Servers screen.
2. Confirm regions load from `/vpn/servers`.
3. Confirm an empty catalog shows a visible empty state, not a broken picker.
4. Select Auto, then a specific region, then Auto again.
5. Open Account and confirm the usage gauge renders for free, capped, and
   zero-cap plans without NaN, overflow, or stuck loading.

## Protocols

For each available protocol, trace:

UI action -> `vpnStateProvider` -> `ChannelVpnService` -> Linux method channel
-> helper command/config -> native result -> Dart state update.

### WireGuard

1. Select WireGuard.
2. Connect.
3. Confirm `wg-quick up` succeeds and interface `securewave` exists.
4. Browse in Chrome.
5. Disconnect.
6. Confirm interface `securewave` is gone.

Useful commands:

```sh
ip link show securewave
wg show
ip route
```

### OpenVPN

1. Select OpenVPN only when the backend returns `openvpn_config`.
2. Connect.
3. Confirm the OpenVPN process remains alive after startup.
4. Browse in Chrome.
5. Disconnect.
6. Confirm the OpenVPN pid file is removed and no SecureWave OpenVPN process is
   left running.

Useful commands:

```sh
pgrep -af 'securewave-openvpn|securewave.ovpn'
ip link
ip route
```

### IKEv2

IKEv2 is not release-ready in the Linux runner. The expected result today is a
visible `protocol_unavailable` error unless a future patch wires profile import,
strongSwan connection start, status verification, and cleanup.

## Repeatability

After any protocol test:

1. Sign out.
2. Sign back in without restarting.
3. Select a region.
4. Connect and disconnect again.
5. Repeat once after closing and relaunching the app.

## Failure Capture

Capture:

- App logs.
- Exact protocol selected.
- API profile response shape without secrets.
- Helper command availability: `which wg-quick openvpn swanctl ipsec pkexec`.
- Tunnel state: `ip link`, `ip route`, `wg show`, `pgrep -af openvpn`.
- Whether the app showed an explicit error or silently failed.
