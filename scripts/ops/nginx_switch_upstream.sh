#!/usr/bin/env bash
set -euo pipefail

CONF="${NGINX_SITE_CONF:-/etc/nginx/sites-available/securewave_preview.conf}"
NEW_PORT=""
BACKUP_DIR="${BACKUP_DIR:-/var/backups/securewave-nginx}"

usage() {
  echo "Usage: $0 --port <new_upstream_port> [--conf <nginx_conf>]"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --port) NEW_PORT="$2"; shift 2 ;;
    --conf) CONF="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ -z "${NEW_PORT}" ]]; then
  usage
  exit 2
fi

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "ERROR: must run as root to modify ${CONF} and reload nginx" >&2
  exit 1
fi

if [[ ! -f "${CONF}" ]]; then
  echo "ERROR: nginx site conf not found: ${CONF}" >&2
  exit 1
fi

mkdir -p "${BACKUP_DIR}"
ts="$(date -u +%Y%m%d_%H%M%S)"
cp "${CONF}" "${BACKUP_DIR}/$(basename "${CONF}").${ts}.bak"

# Replace only the upstream "server host:port;" directive.
# This assumes a config like: `server 127.0.0.1:8080;`
old_line="$(grep -E \"^\\s*server\\s+[^;]+:[0-9]+;\\s*$\" \"${CONF}\" | head -n 1 || true)"
if [[ -z "${old_line}" ]]; then
  echo "ERROR: could not find upstream server line in ${CONF}" >&2
  exit 1
fi

host_part="$(echo "${old_line}" | sed -E 's/^\\s*server\\s+([^;]+):[0-9]+;\\s*$/\\1/')"
sed -i -E "s#^\\s*server\\s+${host_part}:[0-9]+;\\s*\$#    server ${host_part}:${NEW_PORT};#g" "${CONF}"

nginx -t
systemctl reload nginx >/dev/null 2>&1 || systemctl restart nginx >/dev/null 2>&1 || true

echo "nginx upstream switched to ${host_part}:${NEW_PORT}"

