#!/usr/bin/env bash
set -euo pipefail

# verify_ios_store_compliance.sh - Guard against App Store blockers before iOS builds.

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "SKIP: iOS store compliance checks require macOS." >&2
  exit 0
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IOS_DIR="$ROOT_DIR/securewave_app/ios"
PBXPROJ="$IOS_DIR/Runner.xcodeproj/project.pbxproj"
RUNNER_PRIVACY="$IOS_DIR/Runner/PrivacyInfo.xcprivacy"
PACKET_PRIVACY="$IOS_DIR/PacketTunnel/PrivacyInfo.xcprivacy"
INFO_PLIST="$IOS_DIR/Runner/Info.plist"

errors=0

fail_with_fix() {
  local message="$1"
  local fix="$2"
  echo "ERROR: $message" >&2
  echo "FIX:" >&2
  echo "$fix" >&2
  echo >&2
  errors=$((errors + 1))
}

# Guard against missing privacy manifests required by App Store.
if [[ ! -f "$RUNNER_PRIVACY" ]]; then
  fail_with_fix "Runner PrivacyInfo.xcprivacy is missing." "add $RUNNER_PRIVACY and include it in Runner resources"
fi
if [[ ! -f "$PACKET_PRIVACY" ]]; then
  fail_with_fix "PacketTunnel PrivacyInfo.xcprivacy is missing." "add $PACKET_PRIVACY and include it in PacketTunnel resources"
fi

if [[ ! -f "$PBXPROJ" ]]; then
  fail_with_fix "Xcode project file not found." "verify $PBXPROJ exists and is checked in"
else
  if command -v rg >/dev/null 2>&1; then
    privacy_refs="$(rg -c "PrivacyInfo\\.xcprivacy" "$PBXPROJ" || true)"
  else
    privacy_refs="$(grep -c "PrivacyInfo\\.xcprivacy" "$PBXPROJ" || true)"
  fi
  if [[ -z "$privacy_refs" || "$privacy_refs" -lt 2 ]]; then
    fail_with_fix "PrivacyInfo.xcprivacy is not referenced for both targets." "add PrivacyInfo.xcprivacy to Runner + PacketTunnel resources in $PBXPROJ"
  fi
fi

required_vpn_description="SecureWave uses VPN technology to encrypt your internet traffic and protect your privacy on untrusted networks."
if [[ ! -f "$INFO_PLIST" ]]; then
  fail_with_fix "Runner Info.plist not found." "verify $INFO_PLIST exists and contains NSVPNUsageDescription"
else
  # Guard against missing NSVPNUsageDescription, which is required for VPN apps on iOS.
  plist_value=""
  if [[ -x /usr/libexec/PlistBuddy ]]; then
    plist_value="$(/usr/libexec/PlistBuddy -c "Print :NSVPNUsageDescription" "$INFO_PLIST" 2>/dev/null || true)"
  fi
  if [[ -z "$plist_value" ]]; then
    plist_value="$(/usr/bin/plutil -extract NSVPNUsageDescription xml1 -o - "$INFO_PLIST" 2>/dev/null | sed -n 's:.*<string>\(.*\)</string>.*:\1:p' || true)"
  fi
  if [[ "$plist_value" != "$required_vpn_description" ]]; then
    fail_with_fix "NSVPNUsageDescription is missing or incorrect." "set NSVPNUsageDescription to: $required_vpn_description"
  fi
fi

if [[ $errors -gt 0 ]]; then
  exit 1
fi

echo "PASS: iOS store compliance checks passed."
