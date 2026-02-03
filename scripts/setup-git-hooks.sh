#!/usr/bin/env bash
# SecureWave VPN - Git hooks installer
# Run this script after cloning to set up local git hooks
#
# Usage: ./scripts/setup-git-hooks.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
HOOKS_DIR="$REPO_ROOT/.git/hooks"

echo "Setting up SecureWave git hooks..."

# Ensure hooks directory exists
mkdir -p "$HOOKS_DIR"

# Install pre-commit hook
if [ -f "$SCRIPT_DIR/pre-commit-hook.sh" ]; then
    cp "$SCRIPT_DIR/pre-commit-hook.sh" "$HOOKS_DIR/pre-commit"
    chmod +x "$HOOKS_DIR/pre-commit"
    echo "Installed pre-commit hook (secret detection)"
else
    echo "WARNING: pre-commit-hook.sh not found in scripts/"
fi

echo ""
echo "Git hooks installed successfully!"
echo ""
echo "Installed hooks:"
echo "  - pre-commit: Scans for secrets before allowing commits"
echo ""
echo "To bypass hooks in emergencies: git commit --no-verify"
echo "To uninstall: rm .git/hooks/pre-commit"
