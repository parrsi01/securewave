#!/usr/bin/env bash
# verify_release_guards.sh - Validate release configuration before deployment
# Uses grep instead of ripgrep (rg) for portability across CI environments
set -euo pipefail

# Collect production env files
env_files=()
for file in .env.production.example .env.template; do
  if [[ -f "$file" ]]; then
    env_files+=("$file")
  fi
done

# Verify testing flags are not enabled in env files
if [[ ${#env_files[@]} -gt 0 ]]; then
  if grep -Eqn "TESTING\\s*=\\s*(true|1|yes)" "${env_files[@]}" 2>/dev/null; then
    echo "ERROR: TESTING enabled in release env files."
    exit 1
  fi
fi

# Verify Android VPN has WireGuard GoBackend integration
if ! grep -qn "GoBackend" securewave_app/android/app/src/main/kotlin/com/example/securewave_app/vpn/SecureWaveVpnService.kt; then
  echo "ERROR: Android VPN service missing WireGuard GoBackend."
  exit 1
fi

# Verify Windows VPN has wireguard.exe integration
if ! grep -qn "wireguard.exe" securewave_app/windows/runner/flutter_window.cpp; then
  echo "ERROR: Windows VPN bridge missing wireguard.exe integration."
  exit 1
fi

# Verify Linux VPN has wg-quick integration
if ! grep -qn "wg-quick" securewave_app/linux/runner/my_application.cc; then
  echo "ERROR: Linux VPN bridge missing wg-quick integration."
  exit 1
fi

echo "All release guards and VPN bridges verified successfully."
