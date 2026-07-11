# Windows VPN Setup (WireGuard)

SecureWave uses the official WireGuard for Windows tooling (`wireguard.exe`)
to install and start a tunnel service from a WireGuard config string.

## Integration Summary

- MethodChannel: `securewave/vpn` (`isAvailable`, `connect`, `disconnect`,
  `getStatus`, `getTrafficStats`)
- Backend: `wireguard.exe /installtunnelservice` and `/uninstalltunnelservice`
- Config file: `%APPDATA%\SecureWave\SecureWave.conf`
- Optional override: `SECUREWAVE_WIREGUARD_PATH` (full path to `wireguard.exe`)
- Protocol truth: WireGuard only. OpenVPN and IKEv2 fail with
  `protocol_unavailable`.
- Status is `connected` only while the SecureWave WireGuard tunnel service is
  running. Byte counters are explicitly unavailable in this build.

## Requirements

- WireGuard for Windows installed
- App running with privileges to install the tunnel service
- Tunnel profile from backend `POST /api/vpn/profile` (JSON; the app fetches this automatically after sign-in)

## WireGuard Detection Logic

SecureWave resolves `wireguard.exe` in this order:

1. `SECUREWAVE_WIREGUARD_PATH` override (full path to `wireguard.exe`)
2. `C:\Program Files\WireGuard\wireguard.exe`
3. `C:\Program Files (x86)\WireGuard\wireguard.exe`

Verify detection on a target machine:

```powershell
where.exe wireguard.exe
```

If the path is not on `PATH`, set `SECUREWAVE_WIREGUARD_PATH` explicitly.

## Installer Scaffolding (NSIS)

Installer scaffolding lives in `securewave_app/windows/installer/securewave_installer.nsi`.
Build on Windows with:

```powershell
cd securewave_app
./scripts/build_windows_installer.ps1 -Version 4.0.0
```

## Verification

1. Install WireGuard for Windows.
2. `flutter run -d windows` (or run the packaged build).
3. Tap Connect.
4. Verify the service:
   - PowerShell: `Get-Service -Name "WireGuardTunnel$SecureWave"`
   - Or check the WireGuard UI for the SecureWave tunnel.

If `wireguard.exe` is missing, Flutter receives `vpn_unavailable`. In demo mode
(`SECUREWAVE_USE_MOCK_API=true`) the app can simulate a tunnel; in live mode it
will not connect until WireGuard is installed.

This source path is not Windows release proof. A Windows x64 build, install,
service, route, DNS, public exit-IP, data-plane, disconnect, and uninstall run
is still required. Windows ARM64 is not certified.
