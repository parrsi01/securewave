# VPS Lockout Prevention Runbook

## Required Before Any VPN Egress Experiment
1. Confirm out-of-band access is available (Hetzner web console or rescue mode).
2. Confirm current SSH session is healthy.
3. Schedule failsafe rollback before any route/firewall change:
```bash
tools/outage_recovery/enable_failsafe.sh root@<vps_ip> 120
```
4. Keep one SSH session dedicated to rollback only.

## Safe Change Sequence
1. Capture baseline:
```bash
ip addr; ip route; ip rule
iptables -S; iptables -t nat -S
nft list ruleset
ufw status verbose
```
2. Apply one change at a time.
3. After each change, verify:
```bash
ip route get 1.1.1.1
curl -4 --max-time 6 https://api.ipify.org
```
4. From local machine, verify SSH remains reachable.

## Cleanup After Stable Verification
1. Wait at least 5 minutes with stable SSH + internet.
2. Disable failsafe:
```bash
tools/outage_recovery/disable_failsafe.sh root@<vps_ip>
```
3. Archive command transcript and snapshots.

## Emergency Recovery
If SSH drops, use Hetzner console and restore:
- default route via main NIC gateway
- `ufw allow 22/tcp`
- `iptables -I INPUT 1 -p tcp --dport 22 -j ACCEPT`
- restart sshd
