# Linux VPN Setup (WireGuard / OpenVPN / IKEv2)

SecureWave Linux desktop uses live native runtimes only:
- WireGuard via `wg-quick`
- OpenVPN via `openvpn`
- IKEv2 via NetworkManager + strongSwan (`nmcli` + `vpn-type strongswan`)

## Integration Summary

- MethodChannel: `securewave/vpn` (`isAvailable`, `getCapabilities`, `connect`, `disconnect`)
- Runtime files:
  - WireGuard: `~/.config/securewave/securewave-wireguard.conf`
  - OpenVPN: `~/.config/securewave/securewave-openvpn.ovpn`
  - OpenVPN auth file: `~/.config/securewave/securewave-openvpn.auth`
  - OpenVPN pid file: `~/.config/securewave/securewave-openvpn.pid`
- IKEv2 profile name: `SecureWave-IKEv2` (NetworkManager connection)

## Requirements

- `pkexec` + PolicyKit (`policykit-1`)
- WireGuard protocol: `wireguard-tools` (`wg-quick`)
- OpenVPN protocol: `openvpn`
- IKEv2 protocol: `network-manager`, `network-manager-strongswan`, `strongswan` (`ipsec`)
- Tunnel profile from backend `POST /api/vpn/profile`

## Recommended elevation path (user-friendly)

Install the SecureWave `.deb` package so post-install hooks place:
- Scoped helper: `/usr/local/libexec/securewave-wg-quick`
- Polkit rule: `/etc/polkit-1/rules.d/50-securewave-wg.rules`

With this path, WireGuard connect/reset uses OS authorization without repeated
password prompts for users in the `sudo` group.

## Verification

1. Install protocol runtimes:
   - Ubuntu/Debian:
     - `sudo apt-get install wireguard-tools openvpn network-manager-strongswan strongswan`
2. `flutter run -d linux`
3. Select protocol in Settings.
4. Tap Connect.
   - If helper+polkit are installed, connect/reset should be non-interactive.
   - Otherwise approve the `pkexec` prompt.
5. Verify:
   - WireGuard: `sudo wg show`
   - Kill switch: `sudo securewave_app/scripts/verify_linux_kill_switch.sh`
   - OpenVPN: `ps -ef | grep openvpn`
   - IKEv2: `nmcli connection show --active | grep SecureWave-IKEv2`

If a runtime is missing, the app surfaces protocol-specific setup guidance and keeps the connection in terminal failure state.
