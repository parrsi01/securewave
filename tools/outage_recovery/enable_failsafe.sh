#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <root@host> [delay_seconds]"
  exit 2
fi

TARGET="$1"
DELAY="${2:-120}"
SCRIPT_PATH="/root/securewave_failsafe.sh"
UNIT_TAG="securewave-failsafe-$(date -u +%Y%m%d%H%M%S)"

ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=8 "$TARGET" "bash -s" <<'REMOTE'
set -euo pipefail
cat > /root/securewave_failsafe.sh <<'SH'
#!/usr/bin/env bash
set -euo pipefail

STAMP="$(date -u +%Y%m%d_%H%M%S)"
OUTDIR="/root/securewave_failsafe_snapshots/${STAMP}"
mkdir -p "$OUTDIR"

(ip addr || true) > "$OUTDIR/ip_addr.txt"
(ip route || true) > "$OUTDIR/ip_route.txt"
(ip rule || true) > "$OUTDIR/ip_rule.txt"
(sysctl net.ipv4.ip_forward || true) > "$OUTDIR/ip_forward.txt"
(iptables -S || true) > "$OUTDIR/iptables_filter.txt"
(iptables -t nat -S || true) > "$OUTDIR/iptables_nat.txt"
(nft list ruleset || true) > "$OUTDIR/nft_ruleset.txt"
(ufw status verbose || true) > "$OUTDIR/ufw_status.txt"
(ss -lntup || true) > "$OUTDIR/ss_lntup.txt"

if ! ip route show default | grep -q .; then
  IFACE="$(ip -4 route | awk '/proto dhcp/ && /src/ {print $5; exit}')"
  GW="$(ip -4 route | awk '/default/ {print $3; exit}')"
  if [[ -z "$GW" && -n "$IFACE" ]]; then
    GW="$(ip -4 route | awk -v dev="$IFACE" '$0 ~ dev && /proto dhcp/ {print $3; exit}')"
  fi
  if [[ -n "$IFACE" && -n "$GW" ]]; then
    ip route replace default via "$GW" dev "$IFACE" || true
  fi
fi

ufw allow 22/tcp >/dev/null 2>&1 || true
iptables -C INPUT -p tcp --dport 22 -j ACCEPT >/dev/null 2>&1 || iptables -I INPUT 1 -p tcp --dport 22 -j ACCEPT
systemctl restart ssh >/dev/null 2>&1 || systemctl restart sshd >/dev/null 2>&1 || true

echo "failsafe_ran_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "snapshot_dir=$OUTDIR"
SH
chmod 700 /root/securewave_failsafe.sh
REMOTE

ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=8 "$TARGET" "bash -s" <<REMOTE
set -euo pipefail
UNIT_TAG="$UNIT_TAG"
DELAY="$DELAY"
if command -v systemd-run >/dev/null 2>&1; then
  systemd-run --unit "\${UNIT_TAG}" --on-active="\${DELAY}s" /bin/bash "$SCRIPT_PATH" >/dev/null
  echo "\${UNIT_TAG}" > /root/securewave_failsafe.unit
  echo "scheduled_with=systemd-run"
  echo "unit=\${UNIT_TAG}"
  echo "delay_seconds=\${DELAY}"
elif command -v at >/dev/null 2>&1; then
  echo "/bin/bash $SCRIPT_PATH" | at now + 2 minutes >/dev/null
  echo "at-job" > /root/securewave_failsafe.unit
  echo "scheduled_with=at"
  echo "delay_seconds=120"
else
  echo "no_scheduler_available"
  exit 1
fi
REMOTE

echo "Failsafe installed and scheduled on $TARGET"
