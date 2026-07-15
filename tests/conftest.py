"""
SecureWave Test Configuration and Shared Fixtures
==================================================
Provides:
- In-memory SQLite test database
- FastAPI TestClient with dependency overrides
- Authenticated user and admin fixtures
- VPN server seed data
- Environment variable overrides for safe testing
"""

import os
import secrets

# ---------------------------------------------------------------------------
# Environment overrides -- MUST happen before any app imports
# ---------------------------------------------------------------------------
os.environ["TESTING"] = "true"
os.environ["DATABASE_URL"] = "sqlite:///:memory:"
os.environ["SECRET_KEY"] = "test-secret-key-do-not-use-in-prod"
os.environ["ACCESS_TOKEN_SECRET"] = "test-access-secret-stable-across-restarts"
os.environ["REFRESH_TOKEN_SECRET"] = "test-refresh-secret-stable-across-restarts"
os.environ["DEMO_MODE"] = "true"
os.environ["WG_MOCK_MODE"] = "true"
os.environ["ENVIRONMENT"] = "development"
os.environ["ENABLE_SENTRY"] = "false"
os.environ["EMAIL_VALIDATOR_CHECK_DELIVERABILITY"] = "false"
os.environ["BCRYPT_ROUNDS"] = "4"  # Fast hashing in tests
os.environ["WG_DATA_DIR"] = "/tmp/securewave_test_wg"
os.environ["AUTO_CREATE_TABLES"] = "false"  # Prevent auto-create on import

import pytest
from datetime import datetime, timedelta
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from database.base import Base
from database.session import get_db

# ---------------------------------------------------------------------------
# Test database engine (single shared in-memory SQLite)
# ---------------------------------------------------------------------------
TEST_ENGINE = create_engine(
    "sqlite:///:memory:",
    connect_args={"check_same_thread": False},
    poolclass=StaticPool,
    echo=False,
)
TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=TEST_ENGINE)


def _ensure_tables():
    """Import all models so SQLAlchemy registers them, then create tables."""
    from models import (  # noqa: F401
        user,
        subscription,
        audit_log,
        vpn_server,
        vpn_connection,
        vpn_demo_session,
        vpn_usage_event,
        wireguard_peer,
        gdpr,
        support_ticket,
        usage_analytics,
        invoice,
        ikev2_credential,
        openvpn_credential,
        email_log,
    )
    Base.metadata.create_all(bind=TEST_ENGINE)

    # Redirect the production SessionLocal to use TEST_ENGINE so services
    # that call next(get_db()) directly (outside FastAPI DI) share the
    # same in-memory database as the test fixtures.
    import database.session as db_session
    db_session.SessionLocal.configure(bind=TEST_ENGINE)


# ---------------------------------------------------------------------------
# Core fixtures
# ---------------------------------------------------------------------------

@pytest.fixture(scope="function")
def db():
    """Provide a clean database session for each test function."""
    _ensure_tables()
    session = TestingSessionLocal()
    try:
        yield session
    finally:
        session.close()
        Base.metadata.drop_all(bind=TEST_ENGINE)


@pytest.fixture(scope="function")
def client(db):
    """FastAPI TestClient with DB dependency override."""
    from main import app

    def _override_get_db():
        # Reuse the same session so fixtures share state with the client
        try:
            yield db
        finally:
            pass  # Session cleanup handled by the db fixture

    app.dependency_overrides[get_db] = _override_get_db
    with TestClient(app, raise_server_exceptions=False) as c:
        yield c
    app.dependency_overrides.clear()


# ---------------------------------------------------------------------------
# User fixtures
# ---------------------------------------------------------------------------

@pytest.fixture
def test_user(db):
    """Create a verified, active test user."""
    from models.user import User
    from services.hashing_service import hash_password

    user = User(
        email="testuser@example.com",
        hashed_password=hash_password("TestPass123"),
        email_verified=True,
        is_active=True,
        is_admin=False,
        subscription_status="basic",
        created_at=datetime.utcnow(),
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


@pytest.fixture
def test_admin(db):
    """Create a verified admin user."""
    from models.user import User
    from services.hashing_service import hash_password

    admin = User(
        email="admin@example.com",
        hashed_password=hash_password("AdminPass123"),
        email_verified=True,
        is_active=True,
        is_admin=True,
        subscription_status="active",
        created_at=datetime.utcnow(),
    )
    db.add(admin)
    db.commit()
    db.refresh(admin)
    return admin


@pytest.fixture
def unverified_user(db):
    """Create an unverified user (email not confirmed)."""
    from models.user import User
    from services.hashing_service import hash_password

    user = User(
        email="unverified@example.com",
        hashed_password=hash_password("TestPass123"),
        email_verified=False,
        is_active=True,
        is_admin=False,
        created_at=datetime.utcnow(),
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


# ---------------------------------------------------------------------------
# Auth token fixtures
# ---------------------------------------------------------------------------

@pytest.fixture
def auth_headers(test_user):
    """Bearer token headers for the standard test user."""
    from services.jwt_service import create_access_token

    token = create_access_token(test_user)
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture
def admin_auth_headers(test_admin):
    """Bearer token headers for the admin user."""
    from services.jwt_service import create_access_token

    token = create_access_token(test_admin)
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture
def auth_token(test_user):
    """Raw access token string for the test user."""
    from services.jwt_service import create_access_token
    return create_access_token(test_user)


@pytest.fixture
def refresh_token(test_user):
    """Raw refresh token string for the test user."""
    from services.jwt_service import create_refresh_token
    return create_refresh_token(test_user)


# ---------------------------------------------------------------------------
# VPN server fixtures
# ---------------------------------------------------------------------------

@pytest.fixture
def test_vpn_server(db):
    """Seed a single demo VPN server."""
    from models.vpn_server import VPNServer

    observed_at = datetime.utcnow()
    server = VPNServer(
        server_id="us-east-1-001",
        location="New York",
        country="United States",
        country_code="US",
        city="New York",
        region="Americas",
        hcloud_location="ash",
        public_ip="203.0.113.10",
        endpoint="203.0.113.10:51820",
        wg_public_key="dGVzdC1zZXJ2ZXItcHVibGljLWtleS1iYXNlNjQ=",
        wg_private_key_encrypted="encrypted-test-key",
        status="active",
        health_status="healthy",
        last_health_check=observed_at,
        protocol_runtime_evidence={
            "wireguard": {"healthy": True, "authenticated": True, "observed_at": observed_at.isoformat()}
        },
        hcloud_server_state="running",
        max_connections=1000,
        current_connections=0,
        performance_score=95.0,
        latency_ms=25.0,
    )
    db.add(server)
    db.commit()
    db.refresh(server)
    return server


@pytest.fixture
def test_vpn_servers(db):
    """Seed multiple VPN servers across regions."""
    from models.vpn_server import VPNServer

    observed_at = datetime.utcnow()
    runtime_evidence = {
        "wireguard": {"healthy": True, "authenticated": True, "observed_at": observed_at.isoformat()}
    }
    servers_data = [
        {
            "server_id": "us-east-1-001",
            "location": "New York",
            "country": "United States",
            "country_code": "US",
            "city": "New York",
            "region": "Americas",
            "hcloud_location": "ash",
            "public_ip": "203.0.113.10",
            "endpoint": "203.0.113.10:51820",
            "wg_public_key": "dGVzdHNlcnZlcjFwdWJsaWNrZXliYXNlNjQ=",
            "wg_private_key_encrypted": "encrypted-key-1",
            "status": "active",
            "health_status": "healthy",
            "last_health_check": observed_at,
            "protocol_runtime_evidence": runtime_evidence,
            "hcloud_server_state": "running",
            "max_connections": 1000,
            "current_connections": 50,
            "performance_score": 95.0,
            "latency_ms": 25.0,
        },
        {
            "server_id": "eu-west-1-001",
            "location": "London",
            "country": "United Kingdom",
            "country_code": "GB",
            "city": "London",
            "region": "Europe",
            "hcloud_location": "fsn1",
            "public_ip": "203.0.113.20",
            "endpoint": "203.0.113.20:51820",
            "wg_public_key": "dGVzdHNlcnZlcjJwdWJsaWNrZXliYXNlNjQ=",
            "wg_private_key_encrypted": "encrypted-key-2",
            "status": "active",
            "health_status": "healthy",
            "last_health_check": observed_at,
            "protocol_runtime_evidence": runtime_evidence,
            "hcloud_server_state": "running",
            "max_connections": 1000,
            "current_connections": 200,
            "performance_score": 88.0,
            "latency_ms": 40.0,
        },
        {
            "server_id": "ap-east-1-001",
            "location": "Tokyo",
            "country": "Japan",
            "country_code": "JP",
            "city": "Tokyo",
            "region": "Asia",
            "hcloud_location": "nrt1",
            "public_ip": "203.0.113.30",
            "endpoint": "203.0.113.30:51820",
            "wg_public_key": "dGVzdHNlcnZlcjNwdWJsaWNrZXliYXNlNjQ=",
            "wg_private_key_encrypted": "encrypted-key-3",
            "status": "active",
            "health_status": "healthy",
            "last_health_check": observed_at,
            "protocol_runtime_evidence": runtime_evidence,
            "hcloud_server_state": "running",
            "max_connections": 500,
            "current_connections": 10,
            "performance_score": 92.0,
            "latency_ms": 120.0,
            "tier_restriction": "premium",
        },
    ]

    servers = []
    for data in servers_data:
        server = VPNServer(**data)
        db.add(server)
        servers.append(server)
    db.commit()
    for s in servers:
        db.refresh(s)
    return servers


# ---------------------------------------------------------------------------
# Subscription fixtures
# ---------------------------------------------------------------------------

@pytest.fixture
def test_subscription(db, test_user):
    """Create an active subscription for the test user."""
    from models.subscription import Subscription

    sub = Subscription(
        user_id=test_user.id,
        plan_id="premium",
        plan_name="Premium",
        provider="stripe",
        status="active",
        amount=9.99,
        currency="USD",
        billing_cycle="monthly",
        activated_at=datetime.utcnow(),
        current_period_start=datetime.utcnow(),
        current_period_end=datetime.utcnow() + timedelta(days=30),
        next_billing_date=datetime.utcnow() + timedelta(days=30),
        auto_renew=True,
    )
    db.add(sub)
    db.commit()
    db.refresh(sub)
    return sub


# ---------------------------------------------------------------------------
# Ensure __init__.py files exist for test packages
# ---------------------------------------------------------------------------

def _ensure_init_files():
    """Create __init__.py files in test directories if missing."""
    import pathlib
    tests_dir = pathlib.Path(__file__).parent
    for subdir in ["unit", "integration", "security", "e2e", "smoke"]:
        pkg_dir = tests_dir / subdir
        pkg_dir.mkdir(exist_ok=True)
        init_file = pkg_dir / "__init__.py"
        if not init_file.exists():
            init_file.write_text("")


_ensure_init_files()
