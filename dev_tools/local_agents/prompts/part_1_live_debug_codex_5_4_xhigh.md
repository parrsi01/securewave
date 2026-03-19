MODE: CODEX 5.4 XHIGH

OBJECTIVE:
Diagnose Linux VM VPN connectivity failures live, classify the fault into stable buckets, propose targeted fixes, and leave behind unit-tested patch coverage before any production code change is considered done.

REPO CONTEXT:
- Workspace root: `/home/sp/cyber-course/projects/securewave`
- Existing local agent tooling: `dev_tools/local_agents/`
- Preplanned failure playbook: `dev_tools/local_agents/vpn_failure_playbook.py`
- Unit-test scaffold for common VPN failure classes: `tests/test_vpn_connectivity.py`
- Linux VM upstream interface: `enp0s1`
- VPN interfaces to check: `wg0`, `tun0`, `sw-wg`

RULES:
- Log every command and every observed failure.
- Prefer reproducible changes over manual one-off recovery.
- Do not weaken tests.
- Do not treat a fix as valid unless it is backed by a deterministic test or a clear simulation harness.

STEP 1 — COLLECT SYSTEM STATE
Run and capture:
- `ip route`
- `ip a`
- `ping -c 3 8.8.8.8`
- `ping -c 3 google.com`
- `traceroute 8.8.8.8`
- `cat /etc/resolv.conf`
- `sudo wg show` if WireGuard is present
- `sudo systemctl status NetworkManager`
- `sudo iptables -L -v -n`
- `sudo iptables -t nat -L -v -n`
- `journalctl -xe --no-pager | tail -n 50`

STEP 2 — CLASSIFY ERROR
Classify into one or more strict buckets:
1. `ROUTING_ERROR`
2. `DNS_FAILURE`
3. `INTERFACE_DOWN`
4. `FIREWALL_BLOCK`
5. `NAT_FAILURE`
6. `HANDSHAKE_FAILURE`
7. `MTU_ISSUE`
8. `DHCP_FAILURE`
9. `VM_NETWORK_MODE_CONFLICT`
10. `SERVICE_FAILURE`

Use `dev_tools/local_agents/vpn_failure_playbook.py` as the baseline command playbook. If live data proves the failure is different, extend that playbook and its tests in the same change.

STEP 3 — APPLY TARGETED FIXES
Apply only the fixes that match the classified buckets. Minimum command set:

`ROUTING_ERROR`
- `ip route replace default dev wg0`
- `ip route delete default via 192.168.64.1`

`DNS_FAILURE`
- `echo "nameserver 1.1.1.1" > /etc/resolv.conf`

`INTERFACE_DOWN`
- `ip link set enp0s1 up`
- `dhclient enp0s1`

`FIREWALL_BLOCK`
- `iptables -P FORWARD ACCEPT`
- `iptables -F`

`NAT_FAILURE`
- `iptables -t nat -A POSTROUTING -o enp0s1 -j MASQUERADE`

`HANDSHAKE_FAILURE`
- verify keys and config
- restart the VPN service

`MTU_ISSUE`
- `ip link set dev wg0 mtu 1380`

`DHCP_FAILURE`
- `dhclient -v enp0s1`

`SERVICE_FAILURE`
- `systemctl restart NetworkManager`

STEP 4 — VALIDATE FIXES
Re-run:
- `ping -c 3 8.8.8.8`
- `ping -c 3 google.com`
- `curl ifconfig.me`

STEP 5 — LEAVE TEST-BACKED COVERAGE
Update or extend `tests/test_vpn_connectivity.py` so it covers:
- broken routing
- DNS failure
- interface down
- firewall block
- NAT missing
- handshake failure
- MTU mismatch

Each test must:
- inject a failure condition in the playbook model
- run the fix function
- assert the simulated system returns to a healthy state

STEP 6 — OUTPUT
Return:
1. root cause classification
2. commands executed
3. final working config
4. exact tests added or updated
5. any remaining failure class that is still unproven
