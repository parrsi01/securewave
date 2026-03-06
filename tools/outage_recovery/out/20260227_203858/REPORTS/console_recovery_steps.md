# Console Recovery Checklist (Path B - SSH still down)

## 1) Hetzner panel checks
1. Open Hetzner Cloud Console for server `138.199.204.139`.
2. Confirm power state is `Running`.
3. If not running: start it.
4. If running but unreachable: reboot once.
5. If still unreachable: boot into Rescue Mode and open web console.

## 2) In-console host diagnostics
Run:
```bash
ip addr
ip route
ip rule
ufw status verbose
iptables -S
iptables -t nat -S
systemctl status ssh --no-pager
ss -lntup | grep ':22' || true
```

## 3) Minimal recovery commands (safe/additive)
Detect primary NIC + gateway from DHCP lease routes and restore default route:
```bash
DEF_IF=$(ip -4 route show default | awk '{print $5; exit}')
DEF_GW=$(ip -4 route show default | awk '{print $3; exit}')

# If default route is missing, infer from connected subnet gateway (common Hetzner: x.x.x.1)
if [ -z "$DEF_IF" ]; then
  DEF_IF=$(ip -4 route | awk '/proto dhcp/ && /src/ {print $5; exit}')
fi
if [ -z "$DEF_GW" ] && [ -n "$DEF_IF" ]; then
  CIDR=$(ip -4 -o addr show dev "$DEF_IF" scope global | awk '{print $4; exit}')
  SUBNET_BASE=$(python3 - <<'PY'
import ipaddress, os
cidr=os.environ.get('CIDR','')
if cidr:
  net=ipaddress.ip_interface(cidr).network
  print(str(next(net.hosts())))
PY
)
  DEF_GW="$SUBNET_BASE"
fi

if [ -n "$DEF_IF" ] && [ -n "$DEF_GW" ]; then
  ip route replace default via "$DEF_GW" dev "$DEF_IF"
fi
```

Allow SSH explicitly:
```bash
ufw allow 22/tcp || true
iptables -C INPUT -p tcp --dport 22 -j ACCEPT || iptables -I INPUT 1 -p tcp --dport 22 -j ACCEPT
systemctl restart ssh
```

Verify outbound + SSH listener:
```bash
ip route get 1.1.1.1
curl -4 --max-time 6 https://api.ipify.org
ss -lntup | grep ':22'
```

## 4) Remove risky temporary catch-all routing rules
List all rules and remove non-stable experimental ones (example tables/marks not part of known-good baseline):
```bash
ip rule show
# Remove only suspicious experiment rules, examples:
# ip rule del fwmark <mark> lookup <table>
# ip rule del from all lookup <table>
```
Do **not** remove known-good WireGuard production rules.

## 5) Exit rescue and re-test remotely
From local machine:
```bash
ping -c 3 138.199.204.139
nc -vz -w 3 138.199.204.139 22
ssh -o ConnectTimeout=6 root@138.199.204.139 'echo ok'
```
