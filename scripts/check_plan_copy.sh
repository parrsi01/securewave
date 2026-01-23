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

assert_contains "$root_dir/static/subscription.html" "Starter plan with a 5 GB monthly cap"
assert_contains "$root_dir/static/subscription.html" "5 GB monthly data"
assert_contains "$root_dir/static/services.html" "Basic includes a 5 GB monthly cap"
assert_contains "$root_dir/static/js/payment.js" "5 GB bandwidth/month"
assert_contains "$root_dir/securewave_app/lib/features/dashboard/dashboard_page.dart" "Plan and billing live in the SecureWave dashboard\\."
assert_contains "$root_dir/securewave_app/lib/features/settings/devices_page.dart" "Plan limits apply\\. Upgrade in the SecureWave dashboard to add more devices\\."

echo "Plan copy check passed."
