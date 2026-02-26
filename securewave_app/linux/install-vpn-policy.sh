#!/usr/bin/env bash
# install-vpn-policy.sh
#
# Installs the SecureWave polkit rules file so pkexec can run wg-quick
# without an interactive password prompt for users in the 'sudo' group.
#
# Usage:
#   sudo ./install-vpn-policy.sh
#
# After running this script, the Flutter app can elevate privileges via
# pkexec without requiring a GUI polkit authentication agent.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RULES_SRC="${SCRIPT_DIR}/securewave-vpn-policy.rules"
RULES_DST="/etc/polkit-1/rules.d/50-securewave-vpn.rules"

if [ ! -f "$RULES_SRC" ]; then
    echo "Error: rules file not found at $RULES_SRC" >&2
    exit 1
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "Error: this script must be run as root (use sudo)." >&2
    exit 1
fi

install -m 644 "$RULES_SRC" "$RULES_DST"
echo "Installed polkit rules to $RULES_DST"

# Restart polkitd to pick up the new rules
if systemctl is-active --quiet polkitd.service 2>/dev/null || \
   systemctl is-active --quiet polkit.service 2>/dev/null; then
    systemctl restart polkitd.service 2>/dev/null || \
    systemctl restart polkit.service 2>/dev/null || true
    echo "Restarted polkitd."
fi

echo "Done. Users in the 'sudo' group can now use pkexec with wg-quick."
