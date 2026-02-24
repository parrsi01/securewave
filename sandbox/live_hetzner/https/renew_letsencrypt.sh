#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "ERROR: must run as root (use sudo)" >&2
  exit 1
fi

if ! command -v certbot >/dev/null 2>&1; then
  echo "ERROR: certbot not installed" >&2
  exit 1
fi

certbot renew --quiet

if command -v systemctl >/dev/null 2>&1; then
  systemctl reload nginx >/dev/null 2>&1 || systemctl restart nginx >/dev/null 2>&1 || true
else
  nginx -s reload >/dev/null 2>&1 || true
fi

echo "certbot renew complete"

