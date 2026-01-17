#!/usr/bin/env python3
"""
Initialize the production WireGuard server in the database.

This script registers the live WireGuard VM (securewave-wg) so that
the VPN allocation flow can generate real, working configurations.

Run this once after the WG VM is provisioned:
    python infrastructure/init_production_server.py
"""

import os
import sys
from datetime import datetime
from pathlib import Path

# Add project root to path
project_root = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(project_root))

from dotenv import load_dotenv
load_dotenv(project_root / ".env")

from database.session import SessionLocal
from models.vpn_server import VPNServer


# Live WireGuard server configuration
PRODUCTION_SERVER = {
    "server_id": "eu-west-001",
    "location": "West Europe",
    "country": "Netherlands",
    "country_code": "NL",
    "city": "Amsterdam",
    "region": "Europe",
    "latitude": 52.3676,
    "longitude": 4.9041,
    "azure_region": "westeurope",
    "azure_resource_group": "SecureWaveRG",
    "azure_vm_name": "securewave-wg",
    "public_ip": "172.201.201.2",
    "wg_listen_port": 51820,
    "wg_public_key": "f/C/Zvq4r2FxUBwglIT65ozbX51oRi6+tOdVW4JI7lk=",
    "max_connections": 1000,
    "tier_restriction": None,  # Available to all users
    "priority": 100,
}


def init_production_server():
    """Register the production WireGuard server in the database."""
    db = SessionLocal()

    try:
        # Check if server already exists
        existing = db.query(VPNServer).filter(
            VPNServer.server_id == PRODUCTION_SERVER["server_id"]
        ).first()

        if existing:
            print(f"Server '{PRODUCTION_SERVER['server_id']}' already exists.")
            print(f"  Public IP: {existing.public_ip}")
            print(f"  Endpoint: {existing.endpoint}")
            print(f"  Status: {existing.status}")
            print(f"  Health: {existing.health_status}")

            # Update if the public key or IP changed
            if existing.public_ip != PRODUCTION_SERVER["public_ip"]:
                print(f"\nUpdating public IP: {existing.public_ip} -> {PRODUCTION_SERVER['public_ip']}")
                existing.public_ip = PRODUCTION_SERVER["public_ip"]
                existing.endpoint = f"{PRODUCTION_SERVER['public_ip']}:{PRODUCTION_SERVER['wg_listen_port']}"

            if existing.wg_public_key != PRODUCTION_SERVER["wg_public_key"]:
                print(f"\nUpdating WG public key")
                existing.wg_public_key = PRODUCTION_SERVER["wg_public_key"]

            # Ensure server is active
            if existing.status != "active":
                print(f"\nActivating server (was: {existing.status})")
                existing.status = "active"
                existing.azure_vm_state = "running"

            db.commit()
            print("\nServer updated successfully.")
            return existing

        # Create new server
        server = VPNServer(
            server_id=PRODUCTION_SERVER["server_id"],
            location=PRODUCTION_SERVER["location"],
            country=PRODUCTION_SERVER["country"],
            country_code=PRODUCTION_SERVER["country_code"],
            city=PRODUCTION_SERVER["city"],
            region=PRODUCTION_SERVER["region"],
            latitude=PRODUCTION_SERVER["latitude"],
            longitude=PRODUCTION_SERVER["longitude"],
            azure_region=PRODUCTION_SERVER["azure_region"],
            azure_resource_group=PRODUCTION_SERVER["azure_resource_group"],
            azure_vm_name=PRODUCTION_SERVER["azure_vm_name"],
            public_ip=PRODUCTION_SERVER["public_ip"],
            endpoint=f"{PRODUCTION_SERVER['public_ip']}:{PRODUCTION_SERVER['wg_listen_port']}",
            wg_listen_port=PRODUCTION_SERVER["wg_listen_port"],
            wg_public_key=PRODUCTION_SERVER["wg_public_key"],
            wg_private_key_encrypted="",  # Not stored in backend for security
            max_connections=PRODUCTION_SERVER["max_connections"],
            tier_restriction=PRODUCTION_SERVER["tier_restriction"],
            priority=PRODUCTION_SERVER["priority"],
            status="active",
            health_status="healthy",
            azure_vm_state="running",
            provisioned_at=datetime.utcnow(),
        )

        db.add(server)
        db.commit()
        db.refresh(server)

        print("=" * 60)
        print("Production WireGuard Server Registered")
        print("=" * 60)
        print(f"  Server ID:    {server.server_id}")
        print(f"  Location:     {server.city}, {server.country}")
        print(f"  Public IP:    {server.public_ip}")
        print(f"  Endpoint:     {server.endpoint}")
        print(f"  WG Port:      {server.wg_listen_port}/UDP")
        print(f"  Public Key:   {server.wg_public_key}")
        print(f"  Status:       {server.status}")
        print("=" * 60)
        print("\nThe VPN allocation flow will now use this server.")
        print("Users can generate configs from /vpn.html")

        return server

    except Exception as e:
        db.rollback()
        print(f"Error: {e}")
        raise
    finally:
        db.close()


def list_servers():
    """List all VPN servers in the database."""
    db = SessionLocal()
    try:
        servers = db.query(VPNServer).all()
        if not servers:
            print("No VPN servers in database.")
            return

        print(f"\nFound {len(servers)} VPN server(s):\n")
        for s in servers:
            print(f"  [{s.server_id}] {s.city}, {s.country}")
            print(f"    Endpoint: {s.endpoint}")
            print(f"    Status: {s.status} | Health: {s.health_status}")
            print(f"    Connections: {s.current_connections}/{s.max_connections}")
            print()
    finally:
        db.close()


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Initialize production VPN server")
    parser.add_argument("--list", action="store_true", help="List existing servers")
    args = parser.parse_args()

    if args.list:
        list_servers()
    else:
        init_production_server()
        print("\nCurrent servers:")
        list_servers()
