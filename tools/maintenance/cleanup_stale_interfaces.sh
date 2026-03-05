#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=tools/validation/_validation_common.sh
source "${ROOT_DIR}/tools/validation/_validation_common.sh"

require_cmds tee ip awk rm
require_root
require_hetzner_host
begin_script_log "cleanup_stale_interfaces"

log_line "Cleaning validation-only namespaces and interfaces"

for namespace_name in $(ip netns list 2>/dev/null | awk '{print $1}' | grep -E '^swv-' || true); do
  ip netns del "${namespace_name}" >/dev/null 2>&1 || true
  log_line "Removed namespace ${namespace_name}"
done

for iface_name in $(ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | grep -E '^(swvwg|swv-)' || true); do
  ip link del "${iface_name}" >/dev/null 2>&1 || true
  log_line "Removed interface ${iface_name}"
done

if [[ -f /etc/ipsec.d/swv-ikev2-local.conf ]]; then
  rm -f /etc/ipsec.d/swv-ikev2-local.conf
  log_line "Removed /etc/ipsec.d/swv-ikev2-local.conf"
fi

if [[ -f /etc/ipsec.d/cacerts/swv-ikev2-local-ca.pem ]]; then
  rm -f /etc/ipsec.d/cacerts/swv-ikev2-local-ca.pem
  log_line "Removed /etc/ipsec.d/cacerts/swv-ikev2-local-ca.pem"
fi

ipsec down swv-ikev2-local >/dev/null 2>&1 || true
ipsec rereadall >/dev/null 2>&1 || systemctl restart strongswan-starter >/dev/null 2>&1 || systemctl restart ipsec >/dev/null 2>&1 || true

rm -f /tmp/swvwg.conf /tmp/swvovpn.conf /tmp/swvovpn.pid /tmp/securewave_validate_openvpn_client_runtime.log
log_line "Removed temporary validation artifacts from /tmp"
