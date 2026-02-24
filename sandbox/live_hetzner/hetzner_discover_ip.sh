#!/usr/bin/env bash
set -euo pipefail

OUT=""
SERVER_NAME="${HETZNER_SERVER_NAME:-}"
TOKEN="${HETZNER_API_TOKEN:-}"

usage() {
  echo "Usage: $0 --out <path> [--name <server_name>]"
  echo "Env: HETZNER_API_TOKEN (or pass via environment)."
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) OUT="$2"; shift 2 ;;
    --name) SERVER_NAME="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ -z "${OUT}" ]]; then
  usage
  exit 2
fi

ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

if [[ -z "${TOKEN}" ]]; then
  python3 - <<PY >"${OUT}"
import json
print(json.dumps({"generated_at":"${ts}","status":"skipped","reason":"HETZNER_API_TOKEN_missing"}, indent=2))
PY
  exit 0
fi

tmp="$(mktemp)"
trap 'rm -f "${tmp}"' EXIT

curl -sS -o "${tmp}" \
  -H "Authorization: Bearer ${TOKEN}" \
  --connect-timeout 6 --max-time 18 \
  "https://api.hetzner.cloud/v1/servers" 2>/dev/null || true

python3 - <<PY >"${OUT}"
import json
from pathlib import Path

raw = Path("${tmp}").read_text(encoding="utf-8", errors="ignore").strip()
try:
  data = json.loads(raw) if raw else {}
except Exception:
  data = {}

servers = data.get("servers") or []
name_filter = "${SERVER_NAME}".strip()
picked = None
for s in servers:
  if not isinstance(s, dict):
    continue
  if name_filter and str(s.get("name") or "") != name_filter:
    continue
  picked = s
  break

ip = ""
if isinstance(picked, dict):
  public_net = picked.get("public_net") or {}
  ipv4 = (public_net.get("ipv4") or {}) if isinstance(public_net, dict) else {}
  ip = str(ipv4.get("ip") or "")

out = {
  "generated_at": "${ts}",
  "status": "ok" if ip else "not_found",
  "server_name_filter": name_filter,
  "server_name": (picked or {}).get("name") if isinstance(picked, dict) else None,
  "ipv4": ip or None,
}
print(json.dumps(out, indent=2))
PY

