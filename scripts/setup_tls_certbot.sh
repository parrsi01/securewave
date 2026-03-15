#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="${ROOT_DIR}/infra/nginx/securewave_prod.conf"

LETSENCRYPT_EMAIL="${LETSENCRYPT_EMAIL:-}"
UPSTREAM_HOST="${UPSTREAM_HOST:-127.0.0.1}"
UPSTREAM_PORT="${UPSTREAM_PORT:-8080}"
NGINX_CONF="${NGINX_CONF:-/etc/nginx/sites-available/securewave_prod.conf}"
NGINX_LINK="${NGINX_LINK:-/etc/nginx/sites-enabled/securewave_prod.conf}"
ACME_ROOT="${ACME_ROOT:-/var/www/securewave_acme}"
DOMAINS=()

usage() {
  cat <<'TXT'
setup_tls_certbot.sh

Provision production TLS (HTTPS-only) for SecureWave using certbot + nginx.

Required:
  --domain <fqdn>     Public hostname; repeat for apex + www
  --email <email>     Let's Encrypt account email

Optional:
  --upstream-host     Backend upstream host (default: 127.0.0.1)
  --upstream-port     Backend upstream port (default: 8080)
  --nginx-conf        Destination site conf path (default: /etc/nginx/sites-available/securewave_prod.conf)
  --acme-root         ACME webroot path (default: /var/www/securewave_acme)

Example:
  sudo bash scripts/setup_tls_certbot.sh \
    --domain securewave.app \
    --domain www.securewave.app \
    --email ops@securewave.app \
    --upstream-host 127.0.0.1 \
    --upstream-port 8080
TXT
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --domain) DOMAINS+=("$2"); shift 2 ;;
    --email) LETSENCRYPT_EMAIL="$2"; shift 2 ;;
    --upstream-host) UPSTREAM_HOST="$2"; shift 2 ;;
    --upstream-port) UPSTREAM_PORT="$2"; shift 2 ;;
    --nginx-conf) NGINX_CONF="$2"; shift 2 ;;
    --acme-root) ACME_ROOT="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "ERROR: must run as root (use sudo)." >&2
  exit 1
fi

[[ "${#DOMAINS[@]}" -gt 0 ]] || { echo "ERROR: at least one --domain is required" >&2; exit 1; }
[[ -n "$LETSENCRYPT_EMAIL" ]] || { echo "ERROR: --email is required" >&2; exit 1; }
[[ -f "$TEMPLATE" ]] || { echo "ERROR: missing template: $TEMPLATE" >&2; exit 1; }
[[ "$UPSTREAM_PORT" =~ ^[0-9]+$ ]] || { echo "ERROR: upstream port must be numeric" >&2; exit 1; }

PRIMARY_DOMAIN="${DOMAINS[0]}"
SERVER_NAMES="$(printf '%s ' "${DOMAINS[@]}")"
SERVER_NAMES="${SERVER_NAMES% }"

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y nginx certbot python3-certbot-nginx ca-certificates openssl

mkdir -p "$ACME_ROOT"
chmod 0755 "$ACME_ROOT"

bootstrap_http_only() {
  cat >"$NGINX_CONF" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${SERVER_NAMES};
    server_tokens off;

    location ^~ /.well-known/acme-challenge/ {
        root ${ACME_ROOT};
        default_type "text/plain";
        try_files \$uri =404;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}
EOF
}

render_full_https_conf() {
  local cert_path="/etc/letsencrypt/live/${PRIMARY_DOMAIN}/fullchain.pem"
  local key_path="/etc/letsencrypt/live/${PRIMARY_DOMAIN}/privkey.pem"
  local rendered
  rendered="$(cat "$TEMPLATE")"
  rendered="${rendered//__SERVER_NAMES__/$SERVER_NAMES}"
  rendered="${rendered//__UPSTREAM_HOST__/$UPSTREAM_HOST}"
  rendered="${rendered//__UPSTREAM_PORT__/$UPSTREAM_PORT}"
  rendered="${rendered//__SSL_CERT__/$cert_path}"
  rendered="${rendered//__SSL_KEY__/$key_path}"
  printf '%s\n' "$rendered" >"$NGINX_CONF"
}

activate_nginx_site() {
  ln -sf "$NGINX_CONF" "$NGINX_LINK"
  rm -f /etc/nginx/sites-enabled/default || true
  nginx -t
  systemctl enable nginx >/dev/null 2>&1 || true
  systemctl reload nginx >/dev/null 2>&1 || systemctl restart nginx
}

bootstrap_http_only
activate_nginx_site

CERTBOT_ARGS=()
for domain in "${DOMAINS[@]}"; do
  CERTBOT_ARGS+=(--domain "$domain")
done

certbot certonly \
  --nginx \
  --email "$LETSENCRYPT_EMAIL" \
  --agree-tos \
  --non-interactive \
  --keep-until-expiring \
  "${CERTBOT_ARGS[@]}"

render_full_https_conf
activate_nginx_site

mkdir -p /etc/letsencrypt/renewal-hooks/deploy
cat >/etc/letsencrypt/renewal-hooks/deploy/securewave_nginx_reload.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
nginx -t
systemctl reload nginx
EOF
chmod 0755 /etc/letsencrypt/renewal-hooks/deploy/securewave_nginx_reload.sh

if systemctl list-unit-files | grep -q '^certbot.timer'; then
  systemctl enable --now certbot.timer >/dev/null 2>&1 || true
fi

certbot renew --dry-run

echo "TLS setup complete for ${SERVER_NAMES}"
echo "Nginx conf: ${NGINX_CONF}"
echo "Certificate: /etc/letsencrypt/live/${PRIMARY_DOMAIN}/fullchain.pem"
