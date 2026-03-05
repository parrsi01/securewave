#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <root@host>"
  exit 2
fi

TARGET="$1"

ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=8 "$TARGET" 'bash -s' <<'REMOTE'
set -euo pipefail
UNIT="$(cat /root/securewave_failsafe.unit 2>/dev/null || true)"
if [[ -n "$UNIT" && "$UNIT" != "at-job" ]]; then
  systemctl stop "${UNIT}.timer" "${UNIT}.service" >/dev/null 2>&1 || true
  systemctl disable "${UNIT}.timer" >/dev/null 2>&1 || true
  systemctl reset-failed "${UNIT}.service" >/dev/null 2>&1 || true
fi
rm -f /root/securewave_failsafe.unit
rm -f /root/securewave_failsafe.sh
echo "failsafe_disabled"
REMOTE

echo "Failsafe disabled on $TARGET"
