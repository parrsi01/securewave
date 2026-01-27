#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

assert_contains() {
  local file="$1"
  local pattern="$2"
  if ! grep -qE "$pattern" "$file"; then
    echo "Missing required copy in $file: $pattern" >&2
    exit 1
  fi
}

# Subscription page - verify Basic plan mentions 5 GB limit
assert_contains "$root_dir/static/subscription.html" "5 GB monthly data"
assert_contains "$root_dir/static/subscription.html" "5 GB of data per month"

# Services page - verify plan limit mention
assert_contains "$root_dir/static/services.html" "Basic includes a 5 GB monthly cap"

# Flutter app - verify plan copy when the target screens exist
dashboard_copy_file="$root_dir/securewave_app/lib/features/dashboard/dashboard_page.dart"
devices_copy_file="$root_dir/securewave_app/lib/features/settings/devices_page.dart"

if [ -f "$dashboard_copy_file" ]; then
  assert_contains "$dashboard_copy_file" "Plan and billing live in the SecureWave dashboard\\."
else
  echo "Skipping Flutter dashboard plan copy check (file not present): $dashboard_copy_file" >&2
fi

if [ -f "$devices_copy_file" ]; then
  assert_contains "$devices_copy_file" "Plan limits apply\\. Upgrade in the SecureWave dashboard to add more devices\\."
else
  echo "Skipping Flutter devices plan copy check (file not present): $devices_copy_file" >&2
fi

echo "Plan copy check passed."
