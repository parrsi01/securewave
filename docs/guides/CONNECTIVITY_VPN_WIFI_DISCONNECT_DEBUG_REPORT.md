# Connectivity Debugging Report: VPN Active, Wi-Fi Disconnected

Date: 2026-02-26

## Incident Summary

During repository push/sync operations, connectivity failed while a VPN session was active. The underlying system Wi-Fi connection dropped, which disconnected the transport required by the VPN tunnel and caused internet/DNS failures.

## User-Observed Behavior

- VPN was enabled for a use case/session
- System Wi-Fi stopped working / disconnected
- VPN traffic stopped working
- Git/GitHub operations failed

## Technical Symptoms Observed

Shell Git commands failed with DNS/network errors, including:

- `ssh: Could not resolve hostname github.com: Temporary failure in name resolution`

This indicates a connectivity/DNS outage, not a Git authentication or repository permissions issue.

## Root Cause Analysis

Most likely sequence:

1. Wi-Fi (base network interface) disconnected.
2. VPN tunnel remained configured/enabled but lost its transport path.
3. DNS resolution and outbound routing failed (often VPN-routed DNS fails first).
4. SSH Git operations to GitHub failed because `github.com` could not be resolved/reached.

## Why the VPN Also Failed

A VPN depends on the underlying network interface (Wi-Fi/Ethernet/mobile hotspot) to carry encrypted traffic. If Wi-Fi drops:

- the VPN tunnel cannot send/receive packets
- DNS may fail if DNS is routed through the VPN
- "everything on the VPN" appears down even if the VPN client UI still shows enabled/reconnecting

## Impact

- Operations requiring GitHub/network access were interrupted
- Local changes and commits remained intact (no code/data loss from the repo actions themselves)
- Recovery required restoring base connectivity first, then retrying VPN-dependent actions

## Recovery Procedure (Recommended)

1. Restore base connectivity
   - Reconnect Wi-Fi or switch to a known-good network
2. Verify general internet access
   - `ping 1.1.1.1`
   - `ping github.com`
3. Check DNS if hostname resolution still fails
   - `resolvectl status`
   - `nslookup github.com`
4. Reconnect/restart VPN session if needed
5. Verify route/path
   - `ip route`
   - `nmcli device status`
6. Retry failed Git operations

## Fast Triage Checklist (Securewave Ops Context)

- Is the base interface up (`wlan0`/Wi-Fi connected)?
- Is DNS working without the VPN?
- Did the VPN client enter reconnect/killswitch mode?
- Is all traffic forced through VPN (full tunnel)?
- Are local firewall rules or policy routes blocking recovery after interface flap?

## Preventive Notes

- If VPN killswitch/full-tunnel is enabled, a Wi-Fi flap can look like a total outage.
- Keep a fallback path available for ops work (Ethernet/mobile hotspot).
- Before important deployments/pushes, run a quick pre-check:
  - `git ls-remote origin`
  - `ping github.com`

## Conclusion

This incident matches a connectivity-layer failure: Wi-Fi disconnect caused VPN transport loss, which caused DNS/network failures for Git/GitHub operations. The failure was environmental/network-related, not a Securewave application code issue.

