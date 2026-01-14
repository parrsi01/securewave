#!/usr/bin/env bash
set -euo pipefail

export PYTHONPATH=.

SERVER_ID="${SERVER_ID:-us-east-1}"
LOCATION="${LOCATION:-US East}"
REGION="${REGION:-us-east}"
ENDPOINT="${ENDPOINT:-vpn.example.com:51820}"
WG_PUBLIC_KEY="${WG_PUBLIC_KEY:-}"
DNS="${DNS:-1.1.1.1}"
ALLOWED_IPS="${ALLOWED_IPS:-0.0.0.0/0, ::/0}"
PERSISTENT_KEEPALIVE="${PERSISTENT_KEEPALIVE:-25}"

python - <<PY
from app.db.session import SessionLocal
from app.models.vpn_server import VPNServer

db = SessionLocal()
existing = db.query(VPNServer).filter(VPNServer.server_id == "${SERVER_ID}").first()
if existing:
    print("VPN server already exists:", existing.server_id)
else:
    if not "${WG_PUBLIC_KEY}":
        raise SystemExit("WG_PUBLIC_KEY is required to seed a VPN server.")
    server = VPNServer(
        server_id="${SERVER_ID}",
        location="${LOCATION}",
        region="${REGION}",
        endpoint="${ENDPOINT}",
        wg_public_key="${WG_PUBLIC_KEY}",
        dns="${DNS}",
        allowed_ips="${ALLOWED_IPS}",
        persistent_keepalive="${PERSISTENT_KEEPALIVE}",
        status="active",
        is_active=True,
    )
    db.add(server)
    db.commit()
    print("Seeded VPN server:", server.server_id)
db.close()
PY
