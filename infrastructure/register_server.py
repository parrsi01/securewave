#!/usr/bin/env python3
"""
Register a VPN server in the database
Used after deploying a real VPN server to Azure Container Instance
"""
import sys
import argparse
from pathlib import Path

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from database.session import SessionLocal
from models.vpn_server import VPNServer
from services.wireguard_service import WireGuardService


def register_server(server_id: str, location: str, public_ip: str, endpoint: str, region: str = "Americas"):
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
        existing.status = "active"
        db.commit()
        print(f"✅ Server {server_id} updated successfully")
        db.close()
        return

    # Generate server keypair
    print(f"🔑 Generating WireGuard keypair for {server_id}...")
    private_key, public_key = wg.generate_keypair()

    print(f"📝 Creating database record...")
    server = VPNServer(
        server_id=server_id,
        location=location,
        region=region,
        public_ip=public_ip,
        endpoint=endpoint,
        wg_public_key=public_key,
        wg_private_key_encrypted=wg.encrypt_private_key(private_key),
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
    print(f"   Public Key: {public_key[:20]}...")
    print(f"\n💡 Server will be picked up by health monitor within 30 seconds")


def main():
    parser = argparse.ArgumentParser(description="Register VPN server in database")
    parser.add_argument("--server-id", required=True, help="Server identifier (e.g., us-east-1)")
    parser.add_argument("--location", required=True, help="Server location (e.g., New York)")
    parser.add_argument("--public-ip", required=True, help="Server public IP address")
    parser.add_argument("--endpoint", required=True, help="WireGuard endpoint (IP:port)")
    parser.add_argument("--region", default="Americas", help="Server region")

    args = parser.parse_args()

    print("=" * 60)
    print("SecureWave VPN - Server Registration")
    print("=" * 60)
    print()

    register_server(
        server_id=args.server_id,
        location=args.location,
        public_ip=args.public_ip,
        endpoint=args.endpoint,
        region=args.region,
    )


if __name__ == "__main__":
    main()
