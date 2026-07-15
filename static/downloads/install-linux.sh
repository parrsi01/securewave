#!/usr/bin/env bash
# install-linux.sh - Install the portable SecureWave Linux UI client.
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
  case "$(uname -m)" in
    x86_64) ARCH_LABEL="x64" ;;
    aarch64|arm64) ARCH_LABEL="arm64" ;;
    *) die "Unsupported Linux architecture: $(uname -m)" ;;
  esac
  TARBALL="$SCRIPT_DIR/securewave-linux-$ARCH_LABEL.tar.gz"
fi

if [[ ! -f "$TARBALL" ]]; then
  die "Tarball not found: $TARBALL
Place the architecture-matched SecureWave Linux tarball beside this script,
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

# The archive carries the architecture-matched contract-13 helper payload.
# Install it explicitly as root so a tarball install has the same runtime
# behavior as the .deb package. Connect-time elevation is never used.
if [[ -x "$INSTALL_DIR/scripts/install_linux_helper.sh" &&
      -d "$INSTALL_DIR/packaging/linux" ]]; then
  info "Installing the SecureWave contract-13 VPN helper service ..."
  "$INSTALL_DIR/scripts/install_linux_helper.sh" "$INSTALL_DIR/packaging/linux"
else
  die "The Linux archive is missing its VPN helper payload. Rebuild it from the canonical Linux runtime source."
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
info "SecureWave Linux app and helper service installed successfully."
info "The root-owned helper owns privileged VPN routing through contract 13."
info "After installation, pressing Connect should not ask for sudo, pkexec, or a password."
info ""
info "Launch options:"
info "  - From your application menu: search for 'SecureWave VPN'"
info "  - From terminal: securewave"
info "  - Direct path: $INSTALL_DIR/securewave_app"
info ""
info "To uninstall:"
info "  sudo rm -rf $INSTALL_DIR $BIN_LINK $DESKTOP_FILE"
