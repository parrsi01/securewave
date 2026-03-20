#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_DIR="$ROOT_DIR/packaging/linux"
HELPER_DIR=/usr/local/libexec
HELPER="$HELPER_DIR/securewave-wg-quick"
HELPER_CONTRACT="$HELPER_DIR/securewave-wg-quick.contract"
POLKIT_RULES_DIR=/etc/polkit-1/rules.d
POLKIT_RULE="$POLKIT_RULES_DIR/50-securewave-wg.rules"

if [[ "${1:-}" == "--help" ]]; then
  echo "Usage: sudo bash $0"
  exit 0
fi

if [[ $EUID -ne 0 ]]; then
  echo "ERROR: run as root: sudo bash $0" >&2
  exit 1
fi

for path in \
  "$SRC_DIR/securewave-wg-quick" \
  "$SRC_DIR/securewave-wg-quick.contract" \
  "$SRC_DIR/50-securewave-wg.rules"; do
  if [[ ! -f "$path" ]]; then
    echo "ERROR: required helper asset missing: $path" >&2
    exit 1
  fi
done

install -d -m 0755 "$HELPER_DIR"
install -d -m 0755 "$POLKIT_RULES_DIR"
install -m 0755 "$SRC_DIR/securewave-wg-quick" "$HELPER"
install -m 0644 "$SRC_DIR/securewave-wg-quick.contract" "$HELPER_CONTRACT"
install -m 0644 "$SRC_DIR/50-securewave-wg.rules" "$POLKIT_RULE"

echo "Installed:"
ls -l "$HELPER" "$HELPER_CONTRACT" "$POLKIT_RULE"
