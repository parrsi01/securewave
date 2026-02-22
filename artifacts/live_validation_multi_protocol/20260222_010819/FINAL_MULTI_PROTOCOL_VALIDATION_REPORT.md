# FINAL_MULTI_PROTOCOL_VALIDATION_REPORT

- Generated (UTC): `2026-02-22T01:08:19.312659+00:00`
- Host platform: `linux`
- Output directory: `/home/sp/cyber-course/projects/securewave/artifacts/live_validation_multi_protocol/20260222_010819`
- Live API mode: `disabled`
- Overall status: **PARTIAL**

## Executive Summary
- Protocol matrix rows: **15**
- Supported claims: **10**
- Unsupported claims: **5**
- DNS validation failures: **0**
- Kill-switch validation failures: **0**
- Error UX/API validation failures: **0**
- Handshake latency rows passing: **0/5**
- Throughput rows passing: **0/2**

## Evidence Scope
- Control-plane checks: `/api/vpn/protocols`, `/api/vpn/profile`
- UI source-of-truth checks: `securewave_app/lib/core/vpn/protocol_capabilities.dart`
- Runtime checks (host-only): command presence for WireGuard/OpenVPN/IKEv2 tools
- Mock/demo scan: runtime paths plus workflow/config scan

## Mock/Demo Scan
- Runtime path hits: **0**
- Workflow/config hits: **0**
- Runtime scan passed: no mock/demo flags detected in runtime code paths.

## Protocol Claims
See `protocol_matrix.csv` for platform x protocol support state and reasons.

## DNS and Kill-Switch Honesty
- DNS claim checks: `dns_leak_results.csv`
- Kill-switch claim checks: `kill_switch_results.csv`
- Data-plane kill-switch drop tests require manual execution on target OS (commands below).

## Error UX Validation
- Protocol-specific error API checks captured in `raw_logs/error_ux_checks.csv`.
- For UI wording/state transitions, run Flutter protocol/state tests listed in the checklist below.

## Performance Baseline (Barbados and Europe)
- Handshake/latency baseline rows are in `handshake_latency.csv`.
- Throughput baseline rows are in `throughput_summary.csv`.
- Where live tunnel execution is unavailable, rows are marked `manual_required` or `skipped` with reasons.

## Manual Validation Checklist
### Linux
1. WireGuard (data-plane):
   - `sudo cp artifacts/live_validation_multi_protocol/20260222_010819/raw_logs/wireguard_linux.conf /etc/wireguard/sw-live.conf`
   - `sudo chmod 600 /etc/wireguard/sw-live.conf`
   - `sudo wg-quick up sw-live`
   - `sudo wg show sw-live latest-handshakes`
   - `curl --interface sw-live https://api.ipify.org`
   - `dig +short whoami.cloudflare @1.1.1.1`
   - `sudo wg-quick down sw-live`
2. OpenVPN (data-plane):
   - `sudo openvpn --config artifacts/live_validation_multi_protocol/20260222_010819/raw_logs/openvpn_linux.ovpn --daemon --writepid /tmp/sw-ovpn.pid --log /tmp/sw-ovpn.log`
   - `ip addr show tun0`
   - `curl --interface tun0 https://api.ipify.org`
   - `sudo kill $(cat /tmp/sw-ovpn.pid)`
3. IKEv2/IPsec (data-plane, strongSwan):
   - `sudo ipsec statusall`
   - `sudo swanctl --list-conns`
   - `sudo swanctl --initiate --child <child-name>`
   - `ip xfrm state`
   - `curl https://api.ipify.org`

### Windows (PowerShell as Administrator)
1. WireGuard:
   - `wireguard.exe /installtunnelservice C:\path\sw-live.conf`
   - `wg.exe show`
   - `curl.exe https://api.ipify.org`
   - `wireguard.exe /uninstalltunnelservice sw-live`
2. OpenVPN:
   - `& "C:\Program Files\OpenVPN\bin\openvpn.exe" --config C:\path\sw-live.ovpn --log C:\Temp\sw-ovpn.log`
   - `Get-NetIPConfiguration`
3. IKEv2:
   - `Add-VpnConnection -Name "SecureWave IKEv2" -ServerAddress <server> -TunnelType IKEv2 -AuthenticationMethod Eap -EncryptionLevel Required -RememberCredential`
   - `rasdial "SecureWave IKEv2" <username> <password>`
   - `Get-VpnConnection -Name "SecureWave IKEv2"`

### macOS
1. WireGuard:
   - `sudo wg-quick up ~/Library/Application\ Support/SecureWave/sw-live.conf`
   - `wg show`
2. OpenVPN:
   - `sudo /usr/local/sbin/openvpn --config ~/Downloads/sw-live.ovpn --log /tmp/sw-ovpn.log`
3. IKEv2 (NetworkExtension/System profile):
   - `networksetup -listallnetworkservices`
   - `scutil --nc list`
   - `scutil --nc start "SecureWave IKEv2"`

### DNS Leak and Kill-Switch Checks
1. Record pre-VPN IP: `curl -s https://api.ipify.org`
2. Connect tunnel and record post-VPN IP: `curl -s https://api.ipify.org`
3. DNS resolvers:
   - Linux: `cat /etc/resolv.conf`
   - Windows: `Get-DnsClientServerAddress -AddressFamily IPv4`
   - macOS: `scutil --dns`
4. Kill-switch behavior:
   - Force tunnel drop (stop VPN process) and verify outbound traffic is blocked where policy says enforced.


## Required Local Test Commands
- Backend tests: `bash scripts/run_backend_tests.sh`
- Flutter tests: `cd securewave_app && flutter test`
- Flutter protocol/state focus: `cd securewave_app && flutter test test/protocol_capability_matrix_test.dart test/state_machine/protocol_transition_test.dart`
- Mock/demo scan: `rg -n "DEMO_MODE|WG_MOCK_MODE|WG_SIMULATE" main.py routes services securewave_app/lib scripts`

## Verdict
- This report does not mark unvalidated scenarios as pass.
- Any skipped/non-live checks remain explicitly marked for manual execution.
