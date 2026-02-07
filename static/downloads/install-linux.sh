#!/usr/bin/env bash
# install-linux.sh - Install SecureWave VPN client on Linux.
#
# Usage:
#   sudo ./install-linux.sh                          (auto-detect tarball)
#   sudo ./install-linux.sh /path/to/tarball.tar.gz  (explicit path)
#
# This script must be run as root or with sudo.
set -euo pipefail

INSTALL_DIR="/opt/securewave"
BIN_LINK="/usr/local/bin/securewave"
DESKTOP_FILE="/usr/share/applications/securewave.desktop"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

info()  { echo "[INFO]  $*"; }
error() { echo "[ERROR] $*" >&2; }
die()   { error "$*"; exit 1; }

# ---------------------------------------------------------------------------
# Root check
# ---------------------------------------------------------------------------

if [[ $EUID -ne 0 ]]; then
  die "This installer must be run as root. Use: sudo $0"
fi

# ---------------------------------------------------------------------------
# Locate the tarball
# ---------------------------------------------------------------------------

TARBALL="${1:-}"

if [[ -z "$TARBALL" ]]; then
  # Auto-detect: look in the same directory as this script
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  TARBALL="$SCRIPT_DIR/securewave-linux-x64.tar.gz"
fi

if [[ ! -f "$TARBALL" ]]; then
  die "Tarball not found: $TARBALL
Place securewave-linux-x64.tar.gz in the same directory as this script,
or pass the path explicitly: sudo $0 /path/to/tarball.tar.gz"
fi

info "Using tarball: $TARBALL"

# ---------------------------------------------------------------------------
# Install
# ---------------------------------------------------------------------------

info "Installing SecureWave to $INSTALL_DIR ..."

# Remove previous installation if present
if [[ -d "$INSTALL_DIR" ]]; then
  info "Removing previous installation at $INSTALL_DIR"
  rm -rf "$INSTALL_DIR"
fi

mkdir -p "$INSTALL_DIR"
tar -xzf "$TARBALL" -C "$INSTALL_DIR"

# Ensure the main binary is executable
if [[ -f "$INSTALL_DIR/securewave_app" ]]; then
  chmod +x "$INSTALL_DIR/securewave_app"
else
  error "Warning: securewave_app binary not found in tarball."
  error "The application may not launch correctly."
fi

# ---------------------------------------------------------------------------
# Symlink to PATH
# ---------------------------------------------------------------------------

info "Creating symlink: $BIN_LINK -> $INSTALL_DIR/securewave_app"
ln -sf "$INSTALL_DIR/securewave_app" "$BIN_LINK"

# ---------------------------------------------------------------------------
# Desktop entry
# ---------------------------------------------------------------------------

info "Creating desktop entry at $DESKTOP_FILE ..."

cat > "$DESKTOP_FILE" << DESKTOP_EOF
[Desktop Entry]
Type=Application
Name=SecureWave VPN
GenericName=VPN Client
Comment=Secure your internet connection with SecureWave VPN
Exec=$INSTALL_DIR/securewave_app
Icon=$INSTALL_DIR/data/flutter_assets/assets/icon.png
Terminal=false
Categories=Network;Security;
Keywords=vpn;security;privacy;wireguard;
StartupWMClass=securewave_app
DESKTOP_EOF

chmod 644 "$DESKTOP_FILE"
update-desktop-database /usr/share/applications 2>/dev/null || true

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------

info ""
info "SecureWave VPN installed successfully."
info ""
info "Launch options:"
info "  - From your application menu: search for 'SecureWave VPN'"
info "  - From terminal: securewave"
info "  - Direct path: $INSTALL_DIR/securewave_app"
info ""
info "To uninstall:"
info "  sudo rm -rf $INSTALL_DIR $BIN_LINK $DESKTOP_FILE"
