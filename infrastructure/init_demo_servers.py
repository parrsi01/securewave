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
# Import all models to resolve SQLAlchemy relationships
from models.user import User
from models.subscription import Subscription
from models.vpn_server import VPNServer
from models.vpn_connection import VPNConnection
from models.audit_log import AuditLog
from services.wireguard_service import WireGuardService

def init_demo_servers():
    """Initialize demo VPN servers in database"""
    db = SessionLocal()
    wg = WireGuardService()

    demo_servers = [
        {
            "server_id": "us-west-1",
            "location": "San Francisco",
            "country": "United States",
            "country_code": "US",
            "city": "San Francisco",
            "region": "Americas",
            "azure_region": "westus",
            "public_ip": "demo-us-west.securewave.app",
            "endpoint": "demo-us-west.securewave.app:51820",
            "latency_ms": 30.0,
            "latitude": 37.7749,
            "longitude": -122.4194,
        },
        {
            "server_id": "eu-west-1",
            "location": "London",
            "country": "United Kingdom",
            "country_code": "GB",
            "city": "London",
            "region": "Europe",
            "azure_region": "uksouth",
            "public_ip": "demo-eu-west.securewave.app",
            "endpoint": "demo-eu-west.securewave.app:51820",
            "latency_ms": 40.0,
            "latitude": 51.5074,
            "longitude": -0.1278,
        },
        {
            "server_id": "eu-central-1",
            "location": "Frankfurt",
            "country": "Germany",
            "country_code": "DE",
            "city": "Frankfurt",
            "region": "Europe",
            "azure_region": "germanywestcentral",
            "public_ip": "demo-eu-central.securewave.app",
            "endpoint": "demo-eu-central.securewave.app:51820",
            "latency_ms": 45.0,
            "latitude": 50.1109,
            "longitude": 8.6821,
        },
        {
            "server_id": "ap-southeast-1",
            "location": "Singapore",
            "country": "Singapore",
            "country_code": "SG",
            "city": "Singapore",
            "region": "Asia",
            "azure_region": "southeastasia",
            "public_ip": "demo-ap-southeast.securewave.app",
            "endpoint": "demo-ap-southeast.securewave.app:51820",
            "latency_ms": 80.0,
            "latitude": 1.3521,
            "longitude": 103.8198,
        },
        {
            "server_id": "ap-northeast-1",
            "location": "Tokyo",
            "country": "Japan",
            "country_code": "JP",
            "city": "Tokyo",
            "region": "Asia",
            "azure_region": "japaneast",
            "public_ip": "demo-ap-northeast.securewave.app",
            "endpoint": "demo-ap-northeast.securewave.app:51820",
            "latency_ms": 85.0,
            "latitude": 35.6762,
            "longitude": 139.6503,
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
            country=server_data["country"],
            country_code=server_data["country_code"],
            city=server_data["city"],
            region=server_data["region"],
            latitude=server_data.get("latitude"),
            longitude=server_data.get("longitude"),
            azure_region=server_data["azure_region"],
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
