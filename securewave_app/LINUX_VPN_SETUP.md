# Linux VPN Setup

SecureWave Linux support must be described by package type.

- `.deb` install path: intended full-routing path after the privileged helper
  and host VPN tools are installed and verified.
- Portable tar/AppImage/zip path: UI-only by default. Archive extraction does
  not install system services, helper policy, VPN tools, tmpfiles, or any
  no-connect-prompt integration.

Do not claim full Linux VPN routing from a portable archive alone.

## Integration Summary

- MethodChannel: `securewave/vpn` (`isAvailable`, `connect`, `disconnect`)
- WireGuard backend: `wg-quick`
- OpenVPN backend: `openvpn`
- IKEv2 backend: unavailable in the current Linux runner
- Config files: `~/.config/securewave/`

## Requirements

- `.deb` path: one-time admin authorization to install the package, helper, and
  system integration.
- Portable path: a separate privileged setup must already exist before routing
  can be claimed.
- WireGuard tools installed (`wg-quick` on PATH) for WireGuard.
- OpenVPN installed (`openvpn` on PATH) for OpenVPN.
- Tunnel profile from backend `POST /api/vpn/profile` (JSON; the app fetches this automatically after sign-in)

## Privilege Model

The release target is no connect-time authorization prompt after the `.deb`
helper install has completed. If a build still requires `pkexec` or another
prompt at Connect/Disconnect time, treat that build as not release-proven for
the no-prompt helper model.

The current portable packages do not prove that model. They can launch the UI,
but routing requires manually installed privileged components and separate
runtime verification.

## Verification

1. Install WireGuard tools:
   - Ubuntu/Debian: `sudo apt-get install wireguard`
2. Install the `.deb` package or complete an equivalent privileged helper setup.
3. Verify helper/service readiness before tapping Connect.
4. `flutter run -d linux` or launch the packaged app.
5. Tap Connect.
6. Verify the interface:
   - `sudo wg show securewave`
   - `ip addr show securewave`

If `wg-quick`, `openvpn`, or the privileged helper path is missing, Flutter
must receive `vpn_unavailable` or `protocol_unavailable` and stay disconnected.
In demo mode (`SECUREWAVE_USE_MOCK_API=true`) the app can simulate a tunnel; in
live or release mode it must not silently fall back to a mock tunnel.
