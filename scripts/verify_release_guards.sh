#!/usr/bin/env bash
# verify_release_guards.sh - Validate release configuration before deployment
# Uses grep instead of ripgrep (rg) for portability across CI environments
set -euo pipefail

# Check mock API guard exists in app config
if ! grep -qn "mock API disabled in release builds" securewave_app/lib/core/config/app_config.dart; then
  echo "ERROR: Release guard for mock API missing in app_config.dart"
  exit 1
fi

# Collect production env files
env_files=()
for file in .env.production.example .env.template; do
  if [[ -f "$file" ]]; then
    env_files+=("$file")
  fi
done

# Verify mock flags are not enabled in env files
if [[ ${#env_files[@]} -gt 0 ]]; then
  if grep -Eqn "SECUREWAVE_USE_MOCK_API\s*=\s*true" "${env_files[@]}" 2>/dev/null; then
    echo "ERROR: Mock API enabled in release env files."
    exit 1
  fi
  if grep -Eqn "WG_MOCK_MODE\s*=\s*true" "${env_files[@]}" 2>/dev/null; then
    echo "ERROR: WG_MOCK_MODE enabled in release env files."
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

# Verify Linux VPN uses the package-installed socket helper, never connect-time elevation.
if ! grep -qn 'kHelperSocketPath = "/run/securewave/helper.sock"' securewave_app/linux/runner/my_application.cc; then
  echo "ERROR: Linux VPN bridge missing helper socket integration."
  exit 1
fi
if grep -Eqn 'pkexec|/bin/sh.*-c' securewave_app/linux/runner/my_application.cc; then
  echo "ERROR: Linux VPN bridge contains a connect-time elevation or shell fallback."
  exit 1
fi
if [[ "$(tr -d '[:space:]' < securewave_app/packaging/linux/securewave-wg-quick.contract)" != "13" ]]; then
  echo "ERROR: Linux helper contract is not version 13."
  exit 1
fi
if ! grep -qn 'return g_strcmp0(protocol, "wireguard") == 0;' securewave_app/linux/runner/my_application.cc; then
  echo "ERROR: Linux v1 native protocol allowlist is not WireGuard-only."
  exit 1
fi
if ! grep -qn 'RELEASE_PROTOCOLS = ("wireguard",)' scripts/linux_app_vpn_tunnel_proof.py; then
  echo "ERROR: Linux live certification is not WireGuard-only."
  exit 1
fi
if grep -qn '/auth/register' scripts/live_flutter_runtime_smoke.py; then
  echo "ERROR: Live smoke script must never register accounts."
  exit 1
fi

echo "All release guards and VPN bridges verified successfully."
