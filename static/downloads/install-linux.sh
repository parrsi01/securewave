#!/usr/bin/env bash
# install-linux.sh - Install SecureWave VPN client on Linux.
#
# Usage:
#   sudo ./install-linux.sh                          (auto-detect x64 tarball)
#   sudo ./install-linux.sh /path/to/package.tar.gz  (explicit tarball)
#   sudo ./install-linux.sh /path/to/package.zip     (explicit ARM64 zip)
#
# This installs a portable UI-only build. It does not install the root-owned
# SecureWave helper service needed for full-device VPN routing.
#
# For full routing on Debian/Ubuntu, install the SecureWave .deb package once.
# After the .deb is installed, pressing Connect in the app should not trigger
# sudo, pkexec, password, terminal, or external privilege prompts.
#
# This portable installer must be run as root or with sudo.
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
# Locate the package
# ---------------------------------------------------------------------------

PACKAGE_FILE="${1:-}"

if [[ -z "$PACKAGE_FILE" ]]; then
  # Auto-detect: look in the same directory as this script
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  PACKAGE_FILE="$SCRIPT_DIR/securewave-linux-x64.tar.gz"
fi

if [[ ! -f "$PACKAGE_FILE" ]]; then
  die "Package not found: $PACKAGE_FILE
Place securewave-linux-x64.tar.gz in the same directory as this script,
or pass the path explicitly: sudo $0 /path/to/package.tar.gz"
fi

info "Using package: $PACKAGE_FILE"

extract_package() {
  local package_file="$1"
  local install_dir="$2"

  case "$package_file" in
    *.tar.gz|*.tgz)
      tar -xzf "$package_file" -C "$install_dir"
      ;;
    *.zip)
      if command -v unzip >/dev/null 2>&1; then
        unzip -q "$package_file" -d "$install_dir"
      elif command -v python3 >/dev/null 2>&1; then
        python3 - "$package_file" "$install_dir" <<'PY'
import sys
import zipfile

package_file, install_dir = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(package_file) as archive:
    archive.extractall(install_dir)
PY
      else
        die "Install unzip or python3 to extract zip packages."
      fi
      ;;
    *)
      die "Unsupported package type: $package_file"
      ;;
  esac
}

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
extract_package "$PACKAGE_FILE" "$INSTALL_DIR"

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
info ".deb package: full VPN routing with the root-owned SecureWave helper service."
info "Portable AppImage/tarball/zip: UI-only unless the .deb helper service is already installed."
info "After .deb installation, pressing Connect should not ask for sudo, pkexec, or a password."
info "Full routing install example: sudo apt install ./securewave-linux-arm64.deb"
info ""
info "Launch options:"
info "  - From your application menu: search for 'SecureWave VPN'"
info "  - From terminal: securewave"
info "  - Direct path: $INSTALL_DIR/securewave_app"
info ""
info "To uninstall:"
info "  sudo systemctl disable --now securewave-helper.service 2>/dev/null || true"
info "  sudo rm -rf $INSTALL_DIR $BIN_LINK $DESKTOP_FILE"
