#!/usr/bin/env bash
# Renders infra/nginx/securewave_prod.conf placeholders and installs it.
# Run on the VPS as root after certbot has issued a certificate.
#
# Usage:
#   SERVER_NAMES="securewave.app www.securewave.app" \
#   SSL_CERT=/etc/letsencrypt/live/vpn.example.com/fullchain.pem \
#   SSL_KEY=/etc/letsencrypt/live/vpn.example.com/privkey.pem \
#   UPSTREAM_HOST=127.0.0.1 \
#   UPSTREAM_PORT=8080 \
#   bash scripts/ops/render_nginx_conf.sh
#
# Rollback: nginx -t && systemctl reload nginx
#           cp /etc/nginx/sites-available/securewave.conf.bak \
#              /etc/nginx/sites-available/securewave.conf
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEMPLATE="$REPO_ROOT/infra/nginx/securewave_prod.conf"
OUT="/etc/nginx/sites-available/securewave.conf"

: "${SERVER_NAME:?Set SERVER_NAME}"
: "${SERVER_NAMES:=${SERVER_NAME}}"
: "${SSL_CERT:?Set SSL_CERT}"
: "${SSL_KEY:?Set SSL_KEY}"
: "${UPSTREAM_HOST:=127.0.0.1}"
: "${UPSTREAM_PORT:=8080}"

[[ -f "$TEMPLATE" ]] || { echo "ERROR: template not found: $TEMPLATE"; exit 1; }

if [[ -f "$OUT" ]]; then
    cp "$OUT" "${OUT}.bak"
    echo "Backup saved: ${OUT}.bak"
fi

sed \
    -e "s|__SERVER_NAMES__|${SERVER_NAMES}|g" \
    -e "s|__UPSTREAM_HOST__|${UPSTREAM_HOST}|g" \
    -e "s|__UPSTREAM_PORT__|${UPSTREAM_PORT}|g" \
    -e "s|__SSL_CERT__|${SSL_CERT}|g" \
    -e "s|__SSL_KEY__|${SSL_KEY}|g" \
    "$TEMPLATE" > "$OUT"

ln -sf "$OUT" /etc/nginx/sites-enabled/securewave.conf 2>/dev/null || true

nginx -t
systemctl reload nginx
echo "Nginx config rendered and reloaded."
echo "Rollback: cp ${OUT}.bak $OUT && nginx -t && systemctl reload nginx"
