# SecureWave Single-Host Hetzner Validation Matrix

## Purpose
This validation system is now single-host and server-side only.

Operator flow:

1. SSH directly into the Hetzner VPN server
2. Run the validation scripts locally as `root`
3. Generate and test temporary client connections on the same host
4. Tear everything down cleanly before exit

There is no external client machine and no remote SSH hop.

It is part of the VPS-native operational toolchain:

- `tools/provisioning/`
- `tools/validation/`
- `tools/monitoring/`
- `tools/maintenance/`
- `tools/diagnostics/`

## Execution Model
The validation stack runs entirely on the Hetzner server:

- `run_all_validation_tools.sh`
- `tools/validation/validate_vps_protocols.sh`
- `tools/validation/validate_vpn_wireguard.sh`
- `tools/validation/validate_vpn_openvpn.sh`
- `tools/validation/validate_vpn_ikev2.sh`

WireGuard and OpenVPN use a temporary local network namespace to simulate an isolated client without touching the server’s primary routing table.

IKEv2 uses a temporary local strongSwan client configuration in safe mode:

- It establishes a local client connection against the server daemon
- It uses `installpolicy=no`
- It validates IKE and CHILD SA establishment without hijacking the server’s default route

This design reduces false negatives caused by external machines while keeping operational risk low.

## Required Environment
Required:
- `API_BASE_URL`
- `AUTH_TOKEN`
- `PROFILE_OUTPUT_DIR`

Optional:
- `WIREGUARD_SERVER_ID`
- `OPENVPN_SERVER_ID`
- `IKEV2_SERVER_ID`

The server public IP is auto-detected from `hostname -I`.

## Safety Model
All scripts:

- Require `root`
- Refuse to run unless the host appears to be the Hetzner VPN server
- Log to `/var/log/securewave/`
- Exit non-zero on the first failed step
- Restore temporary interfaces, namespaces, and config files during cleanup

Per-protocol validation logs:

- `/var/log/securewave/securewave_validate_wireguard.log`
- `/var/log/securewave/securewave_validate_openvpn.log`
- `/var/log/securewave/securewave_validate_ikev2.log`
- `/var/log/securewave/validate_vps_protocols.log`

The stability test no longer flaps `eth0` or the server uplink. It now uses the temporary VPN client interface:

- WireGuard: temporary `wg` interface inside the namespace
- OpenVPN: temporary `tun` interface inside the namespace
- IKEv2: safe connection bounce (`ipsec down` then `ipsec up`) because policy-based IKEv2 does not expose a dedicated interface by default

## 9-Step Validation Matrix

### Step 1 - Daemon Presence
Checks:
- WireGuard: local `ss -ulnp | grep 51820`, `systemctl status wg-quick@wg0`, `wg show`
- OpenVPN: local `systemctl status openvpn-server@server`
- IKEv2: local `systemctl status strongswan-starter` or equivalent

PASS:
- The expected daemon is active on the Hetzner host.

FAIL:
- Service inactive, failed, missing, or not listening.

Common failure causes:
- Service crash
- Missing unit
- Partial provisioning

Remediation:
- Inspect `journalctl`
- Repair the daemon configuration
- Restart the service after fixing its config

### Step 2 - Port Listening
Checks:
- WireGuard: UDP `51820`
- OpenVPN: `1194`
- IKEv2: UDP `500` and `4500`

PASS:
- The protocol port is bound locally on the server.

FAIL:
- Port is not listening or bound on the wrong transport.

Common failure causes:
- Wrong daemon config
- Port collision
- Failed restart after config changes

Remediation:
- Inspect daemon config
- Verify the port in the unit or config file
- Restart after resolving conflicts

### Step 3 - Firewall / NAT Rules
Checks:
- Local `iptables -t nat -L -n`
- Local `iptables -L FORWARD -n`
- WireGuard also verifies `ip rule show | grep 51820`

PASS:
- MASQUERADE exists
- FORWARD rules are present
- WireGuard policy routing exists

FAIL:
- NAT missing
- FORWARD rules missing or too restrictive
- WireGuard policy routing missing

Common failure causes:
- Firewall drift
- UFW overwrites
- Manual cleanup leaving incomplete state

Remediation:
- Reapply NAT / FORWARD rules
- Reconcile UFW or firewall service state
- Rebuild WireGuard routing rules

### Step 4 - Profile Generation
Checks:
- Local `curl` against `POST /api/vpn/profile`
- Saves profile artifacts under `PROFILE_OUTPUT_DIR`
- Validates endpoint host resolves to the local server public IP

PASS:
- HTTP `200`
- Required config fields present
- Endpoint and port match the live Hetzner server
- WireGuard profile includes Linux policy-routing lines

FAIL:
- Non-200 response
- Missing profile fields
- Wrong endpoint or malformed profile

Common failure causes:
- Invalid `AUTH_TOKEN`
- Wrong server selection
- Server health or provisioning drift

Remediation:
- Refresh `AUTH_TOKEN`
- Set the correct optional server ID
- Recheck backend server mapping and health

### Step 5 - Client Connect
Checks:
- WireGuard: start client in a local network namespace with `wg-quick up`
- OpenVPN: start a local namespace-scoped `openvpn` client
- IKEv2: load a temporary local strongSwan client config and run `ipsec up`

PASS:
- Client path starts successfully
- Expected interface or SA appears
- No fatal client error

FAIL:
- Non-zero start
- Interface or SA missing
- Client exits immediately

Common failure causes:
- Broken profile
- Missing client package
- Local strongSwan include mismatch

Remediation:
- Verify the generated profile
- Install or repair the local client package
- Fix the local include or secrets handling

### Step 6 - Reachability Test
Checks:
- WireGuard/OpenVPN:
  - Route table inside the temporary namespace
  - Ping `8.8.8.8`
  - `curl ifconfig.me`
  - Confirm public IP equals the local server public IP
- IKEv2 safe mode:
  - Confirm the SA remains established
  - Confirm host route lookup is still healthy
  - Confirm public IP remains the server public IP

PASS:
- WireGuard/OpenVPN egress through the server
- IKEv2 safe-mode negotiation remains healthy without destabilizing the host

FAIL:
- Namespace cannot reach the internet
- Public IP does not match the server
- IKEv2 SA drops immediately

Common failure causes:
- NAT failure
- Broken tunnel routing
- IKE rekey or auth mismatch

Remediation:
- Inspect NAT and tunnel routes
- Recheck server daemon config
- Review strongSwan logs and auth mode

### Step 7 - Traffic Validation
Checks:
- Short HTTP request to `https://example.com`
- Confirms non-zero bytes transferred
- Confirms the tunnel or SA remains healthy during the request

PASS:
- Transfer succeeds and remains stable

FAIL:
- Timeout
- Zero-byte transfer
- Tunnel or SA instability during the request

Common failure causes:
- MTU mismatch
- Fragmentation
- Route instability

Remediation:
- Lower MTU
- Recheck MSS handling
- Inspect daemon logs for retransmit or restart loops

### Step 8 - Stability Test
Checks:
- WireGuard: local `ip link set <wg-if> down/up` inside the namespace
- OpenVPN: local `ip link set <tun-if> down/up` inside the namespace
- IKEv2: `ipsec down` then `ipsec up` for the temporary validation connection

PASS:
- The validation path remains healthy after the controlled disruption

FAIL:
- Interface or SA does not recover
- Validation path cannot resume traffic or status checks

Common failure causes:
- Fragile reconnect logic
- Interface-state handling bugs
- Stale client state

Remediation:
- Review reconnect behavior
- Inspect client runtime logs
- Verify teardown and re-init logic

### Step 9 - Cleanup
Checks:
- Tear down the temporary client path
- Remove temporary interface, namespace, or config drop-ins
- Confirm no residual validation state remains

PASS:
- Temporary validation artifacts are removed
- No namespace, tunnel interface, or validation connection remains

FAIL:
- Residual namespace
- Residual interface
- Residual strongSwan config or active validation connection

Common failure causes:
- Interrupted run
- Client crash mid-cleanup
- Temporary config not restored

Remediation:
- Re-run cleanup manually
- Remove temporary namespace or files
- Restore strongSwan secrets from the saved backup

## Why This Model Is Better
- No second machine
- No SSH fan-out
- Lower operational complexity
- Fewer false negatives caused by external network drift
- Safer stability testing because the uplink is never flapped

## Recommended Invocation
```bash
ssh root@your-hetzner-host
cd /path/to/securewave
export API_BASE_URL="https://vpn.example.com/api"
export AUTH_TOKEN="..."
export PROFILE_OUTPUT_DIR="/tmp/securewave_vps_validation"
./run_securewave_ops.sh --with-validation
```
