#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SERVER_NAME="${PREVIEW_HOST:-}"
UPSTREAM_HOST="${PREVIEW_UPSTREAM_HOST:-127.0.0.1}"
UPSTREAM_PORT="${PREVIEW_UPSTREAM_PORT:-8080}"
SSL_MODE="${PREVIEW_SSL_MODE:-auto}"  # auto|letsencrypt|selfsigned|none
LE_EMAIL="${LETSENCRYPT_EMAIL:-}"

NGINX_AVAILABLE="/etc/nginx/sites-available/securewave_preview.conf"
NGINX_ENABLED="/etc/nginx/sites-enabled/securewave_preview.conf"
ACME_ROOT="/var/www/securewave_acme"
SELF_SIGNED_DIR="/etc/ssl/securewave_preview"

usage() {
  cat <<'TXT'
setup_preview.sh

One-step preview setup for SecureWave website+API behind Nginx with nip.io.

Environment variables:
  PREVIEW_HOST            Optional. If unset, uses <PUBLIC_IP>.nip.io when possible.
  PREVIEW_UPSTREAM_HOST   Default: 127.0.0.1
  PREVIEW_UPSTREAM_PORT   Default: 8080
  PREVIEW_SSL_MODE        auto|letsencrypt|selfsigned|none (default: auto)
  LETSENCRYPT_EMAIL       Required for letsencrypt (auto will attempt only if set)

Examples:
  sudo LETSENCRYPT_EMAIL=ops@example.com ./setup_preview.sh
  sudo PREVIEW_SSL_MODE=selfsigned ./setup_preview.sh
TXT
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "setup_preview.sh must be run as root (use sudo)"
  exit 1
fi

detect_public_ip() {
  local ip=""
  if command -v ip >/dev/null 2>&1; then
    ip="$(ip route get 1.1.1.1 2>/dev/null | awk '/src/ {for (i=1;i<=NF;i++) if ($i==\"src\") print $(i+1)}' | head -n1)"
  fi
  if [[ -z "$ip" ]] && command -v curl >/dev/null 2>&1; then
    ip="$(curl -fsS --max-time 3 https://api.ipify.org || true)"
  fi
  echo "$ip"
}

is_private_ip() {
  local ip="$1"
  [[ "$ip" =~ ^10\\. ]] && return 0
  [[ "$ip" =~ ^192\\.168\\. ]] && return 0
  [[ "$ip" =~ ^172\\.(1[6-9]|2[0-9]|3[0-1])\\. ]] && return 0
  [[ "$ip" =~ ^127\\. ]] && return 0
  return 1
}

PUBLIC_IP="$(detect_public_ip)"
if [[ -z "$SERVER_NAME" ]]; then
  if [[ -n "$PUBLIC_IP" ]] && ! is_private_ip "$PUBLIC_IP"; then
    SERVER_NAME="${PUBLIC_IP}.nip.io"
  else
    SERVER_NAME="localhost"
  fi
fi

echo "Preview host: $SERVER_NAME"
echo "Upstream: ${UPSTREAM_HOST}:${UPSTREAM_PORT}"

apt_install() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y nginx openssl ca-certificates
  # certbot is optional unless letsencrypt is requested.
  if [[ "$SSL_MODE" == "letsencrypt" || "$SSL_MODE" == "auto" ]]; then
    apt-get install -y certbot
  fi
}

render_nginx_conf() {
  local enable_ssl="$1"  # true/false
  local ssl_cert="$2"
  local ssl_key="$3"

  local template="$ROOT_DIR/nginx/securewave_preview.conf"
  if [[ ! -f "$template" ]]; then
    echo "missing template: $template"
    exit 1
  fi

  local content
  content="$(cat "$template")"
  content="${content//__SERVER_NAME__/$SERVER_NAME}"
  content="${content//__UPSTREAM_HOST__/$UPSTREAM_HOST}"
  content="${content//__UPSTREAM_PORT__/$UPSTREAM_PORT}"
  content="${content//__SSL_CERT__/$ssl_cert}"
  content="${content//__SSL_KEY__/$ssl_key}"

  if [[ "$enable_ssl" != "true" ]]; then
    # Drop SSL block.
    content="$(printf '%s\n' "$content" | awk '
      /# SSL_BLOCK_BEGIN/ {inssl=1; next}
      /# SSL_BLOCK_END/ {inssl=0; next}
      inssl==1 {next}
      {print}
    ')"
  fi

  printf '%s\n' "$content" >"$NGINX_AVAILABLE"
}

enable_site() {
  mkdir -p "$ACME_ROOT"
  chmod 0755 "$ACME_ROOT"

  ln -sf "$NGINX_AVAILABLE" "$NGINX_ENABLED"
  rm -f /etc/nginx/sites-enabled/default || true

  nginx -t
  systemctl enable nginx >/dev/null 2>&1 || true
  systemctl restart nginx
}

setup_firewall() {
  if command -v ufw >/dev/null 2>&1; then
    ufw allow 80/tcp >/dev/null 2>&1 || true
    ufw allow 443/tcp >/dev/null 2>&1 || true
  fi
}

make_self_signed() {
  local host="$1"
  local out_dir="$SELF_SIGNED_DIR/$host"
  mkdir -p "$out_dir"
  chmod 0700 "$out_dir"

  local cert="$out_dir/fullchain.pem"
  local key="$out_dir/privkey.pem"

  if [[ -f "$cert" && -f "$key" ]]; then
    echo "self-signed cert already exists: $out_dir"
    echo "$cert|$key"
    return 0
  fi

  openssl req -x509 -nodes -newkey rsa:2048 \
    -keyout "$key" \
    -out "$cert" \
    -days 30 \
    -subj "/CN=$host" \
    >/dev/null 2>&1

  echo "$cert|$key"
}

obtain_letsencrypt() {
  if [[ -z "$LE_EMAIL" ]]; then
    echo "LETSENCRYPT_EMAIL not set; cannot request Let's Encrypt cert"
    return 1
  fi

  # Render HTTP-only config first so ACME challenge works.
  render_nginx_conf "false" "/dev/null" "/dev/null"
  enable_site

  mkdir -p "$ACME_ROOT"
  chmod 0755 "$ACME_ROOT"

  echo "requesting Let's Encrypt cert for $SERVER_NAME (webroot=$ACME_ROOT)"
  if certbot certonly \
    --webroot -w "$ACME_ROOT" \
    -d "$SERVER_NAME" \
    -m "$LE_EMAIL" \
    --agree-tos \
    --non-interactive \
    --keep-until-expiring; then
    return 0
  fi
  return 1
}

apt_install
setup_firewall

ENABLE_SSL="false"
SSL_CERT="/dev/null"
SSL_KEY="/dev/null"

if [[ "$SSL_MODE" == "none" ]]; then
  ENABLE_SSL="false"
elif [[ "$SSL_MODE" == "selfsigned" ]]; then
  pair="$(make_self_signed "$SERVER_NAME")"
  SSL_CERT="${pair%%|*}"
  SSL_KEY="${pair##*|}"
  ENABLE_SSL="true"
elif [[ "$SSL_MODE" == "letsencrypt" ]]; then
  if obtain_letsencrypt; then
    SSL_CERT="/etc/letsencrypt/live/$SERVER_NAME/fullchain.pem"
    SSL_KEY="/etc/letsencrypt/live/$SERVER_NAME/privkey.pem"
    ENABLE_SSL="true"
  else
    echo "Let's Encrypt failed; continuing with HTTP only"
    ENABLE_SSL="false"
  fi
elif [[ "$SSL_MODE" == "auto" ]]; then
  # Auto: attempt Let's Encrypt only when a public IP host and email provided.
  if [[ -n "$PUBLIC_IP" ]] && ! is_private_ip "$PUBLIC_IP" && [[ -n "$LE_EMAIL" ]]; then
    if obtain_letsencrypt; then
      SSL_CERT="/etc/letsencrypt/live/$SERVER_NAME/fullchain.pem"
      SSL_KEY="/etc/letsencrypt/live/$SERVER_NAME/privkey.pem"
      ENABLE_SSL="true"
    else
      ENABLE_SSL="false"
    fi
  else
    ENABLE_SSL="false"
  fi
else
  echo "invalid PREVIEW_SSL_MODE=$SSL_MODE"
  exit 1
fi

render_nginx_conf "$ENABLE_SSL" "$SSL_CERT" "$SSL_KEY"
enable_site

echo ""
echo "Nginx preview configured."
echo "Next:"
echo "  1) Start app: ./start_site.sh"
echo "  2) View: http://${SERVER_NAME}/"
if [[ "$ENABLE_SSL" == "true" ]]; then
  echo "     SSL: https://${SERVER_NAME}/"
else
  echo "     SSL: disabled (set PREVIEW_SSL_MODE=selfsigned or LETSENCRYPT_EMAIL + PREVIEW_SSL_MODE=letsencrypt)"
fi

