#!/usr/bin/env bash
set -euo pipefail

TARGET_IP=""
OUT=""

usage() {
  echo "Usage: $0 [--ip <public_ipv4>] --out <path>"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ip) TARGET_IP="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ -z "${OUT}" ]]; then
  usage
  exit 2
fi

ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

domain_nip=""
domain_sslip=""
if [[ -n "${TARGET_IP}" ]]; then
  domain_nip="${TARGET_IP}.nip.io"
  domain_sslip="${TARGET_IP}.sslip.io"
fi

python3 - <<PY >"${OUT}"
import json
payload = {
  "generated_at": "${ts}",
  "ip": "${TARGET_IP}",
  "nip_io": "${domain_nip}",
  "sslip_io": "${domain_sslip}",
  "recommended": "nip.io" if "${domain_nip}" else "n/a",
  "remote_instructions": [
    "Option A (Let's Encrypt via certbot):",
    "1. Ensure port 80 and 443 are reachable on the Hetzner host.",
    "2. Point a preview hostname at the server IP using nip.io or sslip.io (e.g. <ip>.nip.io).",
    "3. On the server: certbot certonly --standalone -d <ip>.nip.io --agree-tos -m <email>",
    "",
    "Option B (Self-signed for preview only):",
    "1. On the server: openssl req -x509 -newkey rsa:2048 -nodes -keyout preview.key -out preview.crt -days 30 -subj \"/CN=<ip>.nip.io\"",
    "2. Configure your reverse proxy to use preview.crt/preview.key.",
    "",
    "Attach a real domain later:",
    "- Update DNS A record to the Hetzner IP, then re-run certbot with the real domain."
  ],
  "notes": [
    "certbot does not generate self-signed certs; use openssl for self-signed preview if Let's Encrypt is unavailable.",
    "If your HTTPS listener uses SNI, use SSL_SNI=<hostname> in ssl_probe.sh for accurate verification."
  ]
}
print(json.dumps(payload, indent=2))
PY

