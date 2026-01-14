#!/usr/bin/env python3
"""
SecureWave VPN - Database Initialization Script
Complete setup for production database including schema, migrations, and initial data
"""

import os
import sys
import subprocess
import logging
from typing import Dict, List
from datetime import datetime

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)


class DatabaseInitializer:
    """Handles complete database initialization for production"""

    def __init__(self, environment: str = "production"):
        self.environment = environment
        self.env_file = f".env.{environment}" if environment != "development" else ".env"

    def check_prerequisites(self) -> bool:
        """Check if all prerequisites are met"""
        logger.info("Checking prerequisites...")

        prerequisites = {
            "PostgreSQL installed": self._check_psql(),
            "Alembic installed": self._check_alembic(),
            "Environment file exists": os.path.exists(self.env_file),
            "Database URL configured": self._check_database_url(),
        }

        all_met = all(prerequisites.values())

        for check, result in prerequisites.items():
            status = "✓" if result else "✗"
            logger.info(f"{status} {check}")

        if not all_met:
            logger.error("Prerequisites not met. Please resolve issues above.")
            return False

        logger.info("✓ All prerequisites met")
        return True

    def initialize_schema(self) -> bool:
        """Initialize database schema using Alembic"""
        logger.info("Initializing database schema...")

        try:
            # Check current migration status
            result = subprocess.run(
                ["alembic", "current"],
                capture_output=True,
                text=True
            )

            if "head" in result.stdout:
                logger.info("✓ Database schema already at latest version")
                return True

            # Run migrations
            logger.info("Running database migrations...")
            subprocess.run(
                ["alembic", "upgrade", "head"],
                check=True
            )

            logger.info("✓ Database schema initialized successfully")
            return True

        except subprocess.CalledProcessError as e:
            logger.error(f"✗ Schema initialization failed: {e}")
            return False
        except Exception as e:
            logger.error(f"✗ Unexpected error during schema initialization: {e}")
            return False

    def create_initial_data(self) -> bool:
        """Create initial data (demo VPN servers, admin user, etc.)"""
        logger.info("Creating initial data...")

        try:
            from database.session import SessionLocal
            from models.user import User
            from models.vpn_server import VPNServer
            from datetime import datetime
            import bcrypt

            db = SessionLocal()

            # Check if admin user exists
            admin = db.query(User).filter_by(email="admin@securewave.app").first()

            if not admin:
                logger.info("Creating admin user...")
                password_hash = bcrypt.hashpw(
                    "SecureWave2026!".encode('utf-8'),
                    bcrypt.gensalt()
                ).decode('utf-8')

                admin = User(
                    username="admin",
                    email="admin@securewave.app",
                    full_name="System Administrator",
                    password_hash=password_hash,
                    email_verified=True,
                    is_admin=True,
                    created_at=datetime.utcnow()
                )
                db.add(admin)
                logger.info("✓ Admin user created (email: admin@securewave.app, password: SecureWave2026!)")
            else:
                logger.info("✓ Admin user already exists")

            # Check if demo servers exist
            server_count = db.query(VPNServer).count()

            if server_count == 0:
                logger.info("Creating demo VPN servers...")

                demo_servers = [
                    {
                        "server_id": "demo-us-east",
                        "location": "United States - East Coast",
                        "country": "United States",
                        "country_code": "US",
                        "city": "New York",
                        "region": "Americas",
                        "latitude": 40.7128,
                        "longitude": -74.0060,
                        "azure_region": "eastus",
                        "public_ip": "demo.us-east.securewave.app",
                        "endpoint": "demo.us-east.securewave.app:51820",
                        "status": "demo",
                        "health_status": "healthy",
                        "max_connections": 1000,
                        "priority": 100,
                    },
                    {
                        "server_id": "demo-eu-west",
                        "location": "Europe - Western",
                        "country": "Netherlands",
                        "country_code": "NL",
                        "city": "Amsterdam",
                        "region": "Europe",
                        "latitude": 52.3676,
                        "longitude": 4.9041,
                        "azure_region": "westeurope",
                        "public_ip": "demo.eu-west.securewave.app",
                        "endpoint": "demo.eu-west.securewave.app:51820",
                        "status": "demo",
                        "health_status": "healthy",
                        "max_connections": 1000,
                        "priority": 90,
                    },
                    {
                        "server_id": "demo-asia-se",
                        "location": "Asia - Southeast",
                        "country": "Singapore",
                        "country_code": "SG",
                        "city": "Singapore",
                        "region": "Asia",
                        "latitude": 1.3521,
                        "longitude": 103.8198,
                        "azure_region": "southeastasia",
                        "public_ip": "demo.asia-se.securewave.app",
                        "endpoint": "demo.asia-se.securewave.app:51820",
                        "status": "demo",
                        "health_status": "healthy",
                        "max_connections": 1000,
                        "priority": 85,
                    },
                ]

                for server_data in demo_servers:
                    server = VPNServer(**server_data)
                    db.add(server)

                logger.info(f"✓ Created {len(demo_servers)} demo VPN servers")
            else:
                logger.info(f"✓ Found {server_count} existing VPN servers")

            db.commit()
            db.close()

            logger.info("✓ Initial data created successfully")
            return True

        except Exception as e:
            logger.error(f"✗ Failed to create initial data: {e}")
            return False

    def verify_database_health(self) -> bool:
        """Verify database is healthy and accessible"""
        logger.info("Verifying database health...")

        try:
            from database.session import check_database_connection, get_database_info

            if not check_database_connection():
                logger.error("✗ Database connection failed")
                return False

            info = get_database_info()
            logger.info(f"✓ Database connection successful")
            logger.info(f"  Driver: {info['driver']}")
            logger.info(f"  Environment: {info['environment']}")

            if info.get('pool_stats'):
                logger.info(f"  Pool size: {info['pool_stats']['size']}")
                logger.info(f"  Active connections: {info['pool_stats']['checked_out']}")

            return True

        except Exception as e:
            logger.error(f"✗ Health verification failed: {e}")
            return False

    def run_full_initialization(self) -> bool:
        """Run complete database initialization process"""
        logger.info("="*70)
        logger.info("SecureWave VPN - Database Initialization")
        logger.info("="*70)
        logger.info(f"Environment: {self.environment}")
        logger.info(f"Started at: {datetime.utcnow().isoformat()}")
        logger.info("")

        steps = [
            ("Prerequisites Check", self.check_prerequisites),
            ("Schema Initialization", self.initialize_schema),
            ("Initial Data Creation", self.create_initial_data),
            ("Health Verification", self.verify_database_health),
        ]

        for step_name, step_func in steps:
            logger.info(f"\n[{step_name}]")
            if not step_func():
                logger.error(f"\n✗ Initialization failed at step: {step_name}")
                return False

        logger.info("\n" + "="*70)
        logger.info("✅ Database Initialization Complete!")
        logger.info("="*70)
        logger.info("\nNext steps:")
        logger.info("1. Test database connection: python3 -c 'from database.session import check_database_connection; check_database_connection()'")
        logger.info("2. Start health monitoring: python3 -m services.vpn_health_monitor")
        logger.info("3. Deploy application: ./deploy.sh")
        logger.info("")

        return True

    def _check_psql(self) -> bool:
        """Check if psql is installed"""
        try:
            subprocess.run(["psql", "--version"], capture_output=True, check=True)
            return True
        except (subprocess.CalledProcessError, FileNotFoundError):
            return False

    def _check_alembic(self) -> bool:
        """Check if alembic is installed"""
        try:
            subprocess.run(["alembic", "--version"], capture_output=True, check=True)
            return True
        except (subprocess.CalledProcessError, FileNotFoundError):
            return False

    def _check_database_url(self) -> bool:
        """Check if DATABASE_URL is configured"""
        from dotenv import load_dotenv
        load_dotenv(self.env_file)
        return bool(os.getenv("DATABASE_URL"))


def main():
    """CLI interface for database initialization"""
    import argparse

    parser = argparse.ArgumentParser(description="Initialize SecureWave VPN Database")
    parser.add_argument(
        "--environment",
        choices=["development", "production", "testing"],
        default="production",
        help="Target environment"
    )
    parser.add_argument(
        "--skip-initial-data",
        action="store_true",
        help="Skip creating initial data (admin user, demo servers)"
    )

    args = parser.parse_args()

    initializer = DatabaseInitializer(environment=args.environment)

    if args.skip_initial_data:
        # Run only prerequisites and schema
        logger.info("Skipping initial data creation (as requested)")
        success = (
            initializer.check_prerequisites() and
            initializer.initialize_schema() and
            initializer.verify_database_health()
        )
    else:
        # Run full initialization
        success = initializer.run_full_initialization()

    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
