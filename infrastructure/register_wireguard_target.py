#!/usr/bin/env python3
"""Register the one runtime-verified WireGuard target in the beta database."""

from __future__ import annotations

import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from dotenv import load_dotenv

load_dotenv(ROOT / ".env")

from database.session import SessionLocal
from models.vpn_server import VPNServer


def main() -> int:
    values = {
        "server_id": os.getenv("WIREGUARD_SERVER_ID", "securewave-beta"),
        "city": os.getenv("WIREGUARD_SERVER_CITY", "Ashburn"),
        "country": os.getenv("WIREGUARD_SERVER_COUNTRY", "United States"),
        "public_ip": os.getenv("WIREGUARD_SERVER_PUBLIC_IP", ""),
        "endpoint": os.getenv("WIREGUARD_SERVER_ENDPOINT", ""),
        "wg_listen_port": int(os.getenv("WIREGUARD_SERVER_PORT", "51820")),
        "wg_public_key": os.getenv("WIREGUARD_SERVER_PUBLIC_KEY", ""),
        "wg_private_key_encrypted": os.getenv("WIREGUARD_SERVER_PRIVATE_KEY_ENCRYPTED", ""),
        "dns_servers": os.getenv("WIREGUARD_SERVER_DNS", "1.1.1.1,1.0.0.1"),
        "allowed_ips": os.getenv("WIREGUARD_SERVER_ALLOWED_IPS", "0.0.0.0/0, ::/0"),
    }
    if not values["public_ip"] or not values["endpoint"] or not values["wg_public_key"]:
        raise SystemExit(
            "WIREGUARD_SERVER_PUBLIC_IP, WIREGUARD_SERVER_ENDPOINT, and "
            "WIREGUARD_SERVER_PUBLIC_KEY are required"
        )

    db = SessionLocal()
    try:
        target = db.query(VPNServer).filter(VPNServer.server_id == values["server_id"]).first()
        if target is None:
            target = VPNServer(**values, status="active", health_status="unknown")
            db.add(target)
        else:
            for key, value in values.items():
                setattr(target, key, value)
            target.status = "active"
        db.commit()
        print(f"registered WireGuard target {target.server_id}")
        return 0
    finally:
        db.close()


if __name__ == "__main__":
    raise SystemExit(main())
