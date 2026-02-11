#!/usr/bin/env python3
"""
Register a VPN server in the database
Used after deploying a real VPN server to Hetzner Cloud.
"""
import sys
import argparse
from pathlib import Path
from typing import Optional

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from database.session import SessionLocal
from models.vpn_server import VPNServer
from services.wireguard_service import WireGuardService


def register_server(
    server_id: str,
    location: str,
    country: str,
    country_code: str,
    city: str,
    public_ip: str,
    endpoint: str,
    hcloud_location: str,
    wg_public_key: str,
    wg_private_key: Optional[str] = None,
    region: str = "Americas",
    hcloud_server_name: str = None,
    hcloud_server_id: str = None,
    hcloud_server_type: str = "cx33",
):
    """Register a VPN server in the database"""
    db = SessionLocal()
    wg = WireGuardService()

    # Check if server already exists
    existing = db.query(VPNServer).filter(VPNServer.server_id == server_id).first()

    if existing:
        print(f"⚠️  Server {server_id} already exists in database")
        print(f"   Updating endpoint: {endpoint}")
        existing.endpoint = endpoint
        existing.public_ip = public_ip
        existing.wg_public_key = wg_public_key
        existing.status = "active"
        db.commit()
        print(f"✅ Server {server_id} updated successfully")
        db.close()
        return

    # Server private keys should remain on the VPN server. Optionally store encrypted
    # private key only if you explicitly provide it (not recommended).
    encrypted_private_key = ""
    if wg_private_key:
        encrypted_private_key = wg.encrypt_private_key(wg_private_key)

    print(f"📝 Creating database record...")
    server = VPNServer(
        server_id=server_id,
        location=location,
        country=country,
        country_code=country_code,
        city=city,
        region=region,
        hcloud_location=hcloud_location,
        hcloud_server_name=hcloud_server_name,
        hcloud_server_id=hcloud_server_id,
        hcloud_server_type=hcloud_server_type,
        public_ip=public_ip,
        endpoint=endpoint,
        wg_public_key=wg_public_key,
        wg_private_key_encrypted=encrypted_private_key,
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

    print(f"\n✅ Server registered successfully!")
    print(f"   Server ID: {server_id}")
    print(f"   Location: {location}")
    print(f"   Endpoint: {endpoint}")
    print(f"   Public Key: {wg_public_key[:20]}...")
    print(f"\n💡 Server will be picked up by health monitor within 30 seconds")


def main():
    parser = argparse.ArgumentParser(description="Register VPN server in database")
    parser.add_argument("--server-id", required=True, help="Server identifier (e.g., us-east-1)")
    parser.add_argument("--location", required=True, help="Server location (e.g., New York)")
    parser.add_argument("--country", required=True, help="Country name (e.g., United States)")
    parser.add_argument("--country-code", required=True, help="Country code (e.g., US)")
    parser.add_argument("--city", required=True, help="City (e.g., Ashburn)")
    parser.add_argument("--public-ip", required=True, help="Server public IP address")
    parser.add_argument(
        "--endpoint",
        default="",
        help="WireGuard endpoint (IP:port). Default: <public-ip>:51820",
    )
    parser.add_argument("--hcloud-location", required=True, help="Hetzner location (e.g., ash, nbg1)")
    parser.add_argument("--wg-public-key", required=True, help="WireGuard server public key (from the server)")
    parser.add_argument(
        "--wg-private-key",
        default="",
        help="(Not recommended) WireGuard server private key to store encrypted in DB",
    )
    parser.add_argument("--hcloud-server-name", help="Hetzner server name")
    parser.add_argument("--hcloud-server-id", help="Hetzner server ID")
    parser.add_argument("--hcloud-server-type", default="cx33", help="Hetzner server type")
    parser.add_argument("--region", default="Americas", help="Server region")

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
        endpoint=args.endpoint or f"{args.public_ip}:51820",
        hcloud_location=args.hcloud_location,
        wg_public_key=args.wg_public_key,
        wg_private_key=args.wg_private_key or None,
        hcloud_server_name=args.hcloud_server_name,
        hcloud_server_id=args.hcloud_server_id,
        hcloud_server_type=args.hcloud_server_type,
        region=args.region,
    )


if __name__ == "__main__":
    main()
