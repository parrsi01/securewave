# Windows VPN Setup (WireGuard / OpenVPN / IKEv2)

SecureWave Windows desktop supports:
- WireGuard via `wireguard.exe` tunnel service
- OpenVPN via elevated `openvpn.exe`
- IKEv2 via built-in Windows VPN (`Add-VpnConnection` + `rasdial`)

## Integration Summary

- MethodChannel: `securewave/vpn` (`isAvailable`, `getCapabilities`, `connect`, `disconnect`)
- WireGuard:
  - `%APPDATA%\SecureWave\SecureWave.conf`
  - `wireguard.exe /installtunnelservice` + `/uninstalltunnelservice`
- OpenVPN:
  - `%APPDATA%\SecureWave\SecureWave-openvpn.ovpn`
  - `%APPDATA%\SecureWave\SecureWave-openvpn.auth`
  - `%APPDATA%\SecureWave\SecureWave-openvpn.log`
  - elevated `openvpn.exe --config ...`
- IKEv2:
  - Connection profile name: `SecureWave-IKEv2`
  - Provisioned with PowerShell `Add-VpnConnection`
  - Connected/disconnected with `rasdial`

## Requirements

- WireGuard protocol: WireGuard for Windows installed
- OpenVPN protocol: OpenVPN for Windows installed
- IKEv2 protocol: Windows built-in VPN runtime (PowerShell + rasdial present)
- UAC approval for elevated protocol operations
- Tunnel profile from backend `POST /api/vpn/profile`

## Runtime Detection Logic

WireGuard path resolution:

1. `SECUREWAVE_WIREGUARD_PATH` override (full path to `wireguard.exe`)
2. `C:\Program Files\WireGuard\wireguard.exe`
3. `C:\Program Files (x86)\WireGuard\wireguard.exe`

OpenVPN path resolution:

1. `SECUREWAVE_OPENVPN_PATH` override (full path to `openvpn.exe`)
2. `C:\Program Files\OpenVPN\bin\openvpn.exe`
3. `C:\Program Files (x86)\OpenVPN\bin\openvpn.exe`

## IKEv2 Auth Mode

Current Windows automation path is `EAP-MSCHAPv2` for IKEv2 profiles.
If backend returns `auth_method=eap-tls`, client setup is intentionally blocked with an actionable error.

## Installer (Inno Setup)

Production installer lives in `windows_installer/securewave_installer.iss` (Inno Setup 6).
Build on Windows with:

```powershell
./windows_installer/build_windows_installer.ps1 -ApiBaseUrl "https://<your-domain>/api"
```

## Verification

1. Install WireGuard and OpenVPN for Windows.
2. `flutter run -d windows` (or run the packaged build).
3. Select protocol in Settings and tap Connect.
4. Verify:
   - WireGuard: `Get-Service -Name "WireGuardTunnel$SecureWave"`
   - OpenVPN: `Get-Process openvpn -ErrorAction SilentlyContinue`
   - IKEv2: `Get-VpnConnection -Name "SecureWave-IKEv2"`

If a protocol runtime is missing, SecureWave surfaces protocol-specific setup guidance and does not fake success.
