#!/usr/bin/env python3
"""
Initialize demo VPN servers in database
This script seeds the database with 5 demo servers for the hybrid deployment
"""
import sys
from pathlib import Path

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from database.session import SessionLocal
from models.vpn_server import VPNServer
from services.wireguard_service import WireGuardService

def init_demo_servers():
    """Initialize demo VPN servers in database"""
    db = SessionLocal()
    wg = WireGuardService()

    demo_servers = [
        {
            "server_id": "us-west-1",
            "location": "San Francisco",
            "region": "Americas",
            "public_ip": "demo-us-west.securewave.app",
            "endpoint": "demo-us-west.securewave.app:51820",
            "latency_ms": 30.0,
        },
        {
            "server_id": "eu-west-1",
            "location": "London",
            "region": "Europe",
            "public_ip": "demo-eu-west.securewave.app",
            "endpoint": "demo-eu-west.securewave.app:51820",
            "latency_ms": 40.0,
        },
        {
            "server_id": "eu-central-1",
            "location": "Frankfurt",
            "region": "Europe",
            "public_ip": "demo-eu-central.securewave.app",
            "endpoint": "demo-eu-central.securewave.app:51820",
            "latency_ms": 45.0,
        },
        {
            "server_id": "ap-southeast-1",
            "location": "Singapore",
            "region": "Asia",
            "public_ip": "demo-ap-southeast.securewave.app",
            "endpoint": "demo-ap-southeast.securewave.app:51820",
            "latency_ms": 80.0,
        },
        {
            "server_id": "ap-northeast-1",
            "location": "Tokyo",
            "region": "Asia",
            "public_ip": "demo-ap-northeast.securewave.app",
            "endpoint": "demo-ap-northeast.securewave.app:51820",
            "latency_ms": 85.0,
        },
    ]

    created_count = 0

    for server_data in demo_servers:
        # Check if server already exists
        existing = db.query(VPNServer).filter(
            VPNServer.server_id == server_data["server_id"]
        ).first()

        if existing:
            print(f"⏭️  Server {server_data['server_id']} already exists, skipping...")
            continue

        # Generate keys for demo server
        private_key, public_key = wg.generate_keypair()

        server = VPNServer(
            server_id=server_data["server_id"],
            location=server_data["location"],
            region=server_data["region"],
            public_ip=server_data["public_ip"],
            endpoint=server_data["endpoint"],
            wg_public_key=public_key,
            wg_private_key_encrypted=wg.encrypt_private_key(private_key),
            status="demo",  # Mark as demo server
            health_status="healthy",
            max_connections=1000,
            latency_ms=server_data["latency_ms"],
            bandwidth_in_mbps=800.0,
            cpu_load=0.3,
            packet_loss=0.01,
            jitter_ms=2.0,
        )

        db.add(server)
        created_count += 1
        print(f"✅ Created demo server: {server_data['server_id']} ({server_data['location']})")

    db.commit()
    db.close()

    print(f"\n🎉 Demo server initialization complete! Created {created_count} servers")
    print(f"📊 Total servers in database: {created_count}")


if __name__ == "__main__":
    print("=" * 60)
    print("SecureWave VPN - Demo Server Initialization")
    print("=" * 60)
    print()

    init_demo_servers()
