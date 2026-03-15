#!/usr/bin/env bash
set -euo pipefail

UPSTREAM_HEALTH_URL="${UPSTREAM_HEALTH_URL:-http://127.0.0.1:8080/api/health}"
EDGE_HTTP_URL="${EDGE_HTTP_URL:-http://127.0.0.1/api/health}"
EDGE_HTTPS_URL="${EDGE_HTTPS_URL:-https://127.0.0.1/api/health}"

require_cmd() {
  local name="$1"
  command -v "$name" >/dev/null 2>&1 || {
    echo "ERROR: missing required command: $name" >&2
    exit 1
  }
}

read_status() {
  local url="$1"
  curl -fsS ${2:-} "$url" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("status",""))'
}

require_cmd systemctl
require_cmd nginx
require_cmd curl
require_cmd python3

echo "==> Service status"
systemctl is-active nginx >/dev/null
echo "nginx: active"
systemctl is-active securewave-api >/dev/null
echo "securewave-api: active"

echo "==> Nginx config"
nginx -t >/dev/null
echo "nginx config: ok"

echo "==> Certbot timer"
if systemctl list-unit-files | grep -q '^certbot.timer'; then
  systemctl is-enabled certbot.timer >/dev/null
  systemctl is-active certbot.timer >/dev/null
  echo "certbot.timer: enabled and active"
else
  echo "certbot.timer: not installed"
fi

echo "==> Health checks"
upstream_status="$(read_status "$UPSTREAM_HEALTH_URL")"
[[ "$upstream_status" == "ok" ]] || {
  echo "ERROR: upstream health check failed for $UPSTREAM_HEALTH_URL (status=$upstream_status)" >&2
  exit 1
}
echo "upstream: ok"

edge_http_status="$(read_status "$EDGE_HTTP_URL")"
[[ "$edge_http_status" == "ok" ]] || {
  echo "ERROR: nginx HTTP edge check failed for $EDGE_HTTP_URL (status=$edge_http_status)" >&2
  exit 1
}
echo "edge http: ok"

edge_https_status="$(read_status "$EDGE_HTTPS_URL" "-k")"
[[ "$edge_https_status" == "ok" ]] || {
  echo "ERROR: nginx HTTPS edge check failed for $EDGE_HTTPS_URL (status=$edge_https_status)" >&2
  exit 1
}
echo "edge https: ok"

echo "HTTPS edge readiness: PASS"
