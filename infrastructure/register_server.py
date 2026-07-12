#!/usr/bin/env python3
"""
Register a VPN server in the database
Used after provisioning a real Linux WireGuard server
"""
import sys
import argparse
from pathlib import Path

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from database.session import SessionLocal
from models.vpn_server import VPNServer


def register_server(
    server_id: str,
    location: str,
    country: str,
    country_code: str,
    city: str,
    public_ip: str,
    endpoint: str,
    wg_public_key: str,
    region: str = "Americas",
    hcloud_location: str = "",
    hcloud_server_id: str = "",
    hcloud_server_name: str = "",
    hcloud_server_type: str = "",
    hcloud_server_state: str = "running",
):
    """Register a VPN server in the database"""
    db = SessionLocal()

    # Check if server already exists
    existing = db.query(VPNServer).filter(VPNServer.server_id == server_id).first()

    if existing:
        print(f"⚠️  Server {server_id} already exists in database")
        print(f"   Updating endpoint: {endpoint}")
        existing.endpoint = endpoint
        existing.public_ip = public_ip
        existing.wg_public_key = wg_public_key
        existing.hcloud_location = hcloud_location or existing.hcloud_location
        existing.hcloud_server_state = hcloud_server_state
        existing.status = "active"
        db.commit()
        print(f"✅ Server {server_id} updated successfully")
        db.close()
        return

    print("📝 Creating database record...")
    server = VPNServer(
        server_id=server_id,
        location=location,
        country=country,
        country_code=country_code,
        city=city,
        region=region,
        hcloud_location=hcloud_location or None,
        hcloud_server_id=hcloud_server_id or None,
        hcloud_server_name=hcloud_server_name or server_id,
        hcloud_server_type=hcloud_server_type or None,
        hcloud_server_state=hcloud_server_state,
        public_ip=public_ip,
        endpoint=endpoint,
        wg_public_key=wg_public_key,
        wg_private_key_encrypted="",
        status="active",  # Real server, not demo
        health_status="unknown",  # Will be updated by health monitor
        max_connections=1000,
        latency_ms=50.0,  # Initial estimate
        bandwidth_in_mbps=1000.0,
        cpu_load=0.2,
        packet_loss=0.0,
        jitter_ms=2.0,
    )

    db.add(server)
    db.commit()
    db.refresh(server)
    db.close()

    print("\n✅ Server registered successfully!")
    print(f"   Server ID: {server_id}")
    print(f"   Location: {location}")
    print(f"   Endpoint: {endpoint}")
    print(f"   Public Key: {wg_public_key[:20]}...")
    print("\n💡 Server will be picked up by health monitor within 30 seconds")


def main():
    parser = argparse.ArgumentParser(description="Register VPN server in database")
    parser.add_argument("--server-id", required=True, help="Server identifier (e.g., us-east-1)")
    parser.add_argument("--location", required=True, help="Server location (e.g., New York)")
    parser.add_argument("--country", required=True, help="Country name")
    parser.add_argument("--country-code", required=True, help="ISO 3166-1 alpha-2 country code")
    parser.add_argument("--city", required=True, help="City name")
    parser.add_argument("--public-ip", required=True, help="Server public IP address")
    parser.add_argument("--endpoint", required=True, help="WireGuard endpoint (IP:port)")
    parser.add_argument("--wg-public-key", required=True, help="WireGuard server public key")
    parser.add_argument("--region", default="Americas", help="Server region")
    parser.add_argument("--hcloud-location", default="", help="Hetzner location code")
    parser.add_argument("--hcloud-server-id", default="", help="Hetzner server ID")
    parser.add_argument("--hcloud-server-name", default="", help="Hetzner server name")
    parser.add_argument("--hcloud-server-type", default="", help="Hetzner server type")
    parser.add_argument("--hcloud-server-state", default="running", help="Provider server state")

    args = parser.parse_args()

    print("=" * 60)
    print("SecureWave VPN - Server Registration")
    print("=" * 60)
    print()

    register_server(
        server_id=args.server_id,
        location=args.location,
        country=args.country,
        country_code=args.country_code,
        city=args.city,
        public_ip=args.public_ip,
        endpoint=args.endpoint,
        wg_public_key=args.wg_public_key,
        region=args.region,
        hcloud_location=args.hcloud_location,
        hcloud_server_id=args.hcloud_server_id,
        hcloud_server_name=args.hcloud_server_name,
        hcloud_server_type=args.hcloud_server_type,
        hcloud_server_state=args.hcloud_server_state,
    )


if __name__ == "__main__":
    main()
