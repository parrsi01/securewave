#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROD_NGINX_CONF="$ROOT_DIR/infra/nginx/securewave_prod.conf"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

check_exists() {
  [[ -f "$PROD_NGINX_CONF" ]] || fail "Missing production nginx config: $PROD_NGINX_CONF"
}

check_http_redirect_only() {
  grep -q 'listen 80;' "$PROD_NGINX_CONF" || fail "No port 80 listener found in production nginx config."
  grep -q 'return 301 https://\$host\$request_uri;' "$PROD_NGINX_CONF" || fail "HTTP->HTTPS redirect missing."

  # In this config layout, anything before TLS listener belongs to the HTTP block.
  if sed -n '1,/listen 443/p' "$PROD_NGINX_CONF" | grep -q 'proxy_pass'; then
    fail "HTTP section contains proxy_pass (HTTP endpoint exposure is not allowed)."
  fi
}

check_server_tokens() {
  grep -Eq '^\s*server_tokens\s+off;' "$PROD_NGINX_CONF" || fail "server_tokens off is required."
  if grep -Eq '^\s*server_tokens\s+on;' "$PROD_NGINX_CONF"; then
    fail "server_tokens on detected."
  fi
}

check_tls_version() {
  grep -Eq '^\s*ssl_protocols\s+TLSv1\.2\s+TLSv1\.3;' "$PROD_NGINX_CONF" \
    || fail "TLS protocol baseline must be exactly TLSv1.2/TLSv1.3."
  if grep -Eq 'TLSv1(\s|;)|TLSv1\.1' "$PROD_NGINX_CONF"; then
    fail "Legacy TLS version detected (< 1.2)."
  fi
}

check_legacy_cloud_references() {
  # Exclude vendored third-party sources from this project policy gate.
  local pattern='[Aa][Zz][Uu][Rr][Ee]|[Aa][Zz][Uu][Rr][Ee][Rr][Mm]|[Aa][Zz][Uu][Rr][Ee][Dd][Ee][Vv][Oo][Pp][Ss]'
  if git -C "$ROOT_DIR" grep -nEI "$pattern" -- . \
    ':(exclude)securewave_app/ios/ThirdParty/*' \
    ':(exclude)artifacts/*' >/tmp/securewave_legacy_cloud_refs.out; then
    cat /tmp/securewave_legacy_cloud_refs.out >&2
    fail "Disallowed legacy cloud reference detected in tracked repository files."
  fi
}

check_tracked_env_and_private() {
  if git -C "$ROOT_DIR" ls-files | grep -Eq '(^|/)\.env$'; then
    fail ".env file is tracked by git."
  fi
  if git -C "$ROOT_DIR" ls-files | grep -Eq '^securewave_private/'; then
    fail "securewave_private folder is tracked by git."
  fi
}

check_exists
check_http_redirect_only
check_server_tokens
check_tls_version
check_legacy_cloud_references
check_tracked_env_and_private

echo "Infrastructure hardening CI checks passed."
