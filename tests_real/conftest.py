"""
Real-mode integration test configuration.

This suite validates the "real WireGuard profile" code path without requiring
live infrastructure or any network traffic to a VPN server.
"""

import os

# ---------------------------------------------------------------------------
# Environment overrides -- MUST happen before any app imports
# ---------------------------------------------------------------------------
os.environ["TESTING"] = "true"
os.environ["DATABASE_URL"] = "sqlite:///:memory:"
os.environ["SECRET_KEY"] = "test-secret-key-do-not-use-in-prod"
os.environ["ACCESS_TOKEN_SECRET"] = "test-access-secret-stable-across-restarts"
os.environ["REFRESH_TOKEN_SECRET"] = "test-refresh-secret-stable-across-restarts"
os.environ["ENVIRONMENT"] = "staging"
os.environ["DEMO_MODE"] = "false"
os.environ["WG_MOCK_MODE"] = "false"
os.environ["WG_AUTO_REGISTER_PEERS"] = "false"
os.environ["ENABLE_APP_INSIGHTS"] = "false"
os.environ["ENABLE_SENTRY"] = "false"
os.environ["EMAIL_VALIDATOR_CHECK_DELIVERABILITY"] = "false"
os.environ["BCRYPT_ROUNDS"] = "4"  # Fast hashing in tests
os.environ["WG_DATA_DIR"] = "/tmp/securewave_test_wg_real"
os.environ["AUTO_CREATE_TABLES"] = "false"  # Prevent auto-create on import

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from database.base import Base
from database.session import get_db
from utils.inprocess_testclient import InProcessTestClient


TEST_ENGINE = create_engine(
    "sqlite:///:memory:",
    connect_args={"check_same_thread": False},
    poolclass=StaticPool,
    echo=False,
)
TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=TEST_ENGINE)


def _ensure_tables() -> None:
    """Import all models so SQLAlchemy registers them, then create tables."""
    from models import (  # noqa: F401
        user,
        subscription,
        audit_log,
        vpn_server,
        vpn_server_rtt_sample,
        vpn_connection,
        vpn_demo_session,
        wireguard_peer,
        gdpr,
        support_ticket,
        usage_analytics,
        invoice,
        email_log,
        auth_refresh_token,
    )
    Base.metadata.create_all(bind=TEST_ENGINE)

    # Ensure code that imports the "production" SessionLocal sees TEST_ENGINE.
    import database.session as db_session
    db_session.SessionLocal.configure(bind=TEST_ENGINE)


@pytest.fixture(scope="function")
def db():
    _ensure_tables()
    session = TestingSessionLocal()
    try:
        yield session
    finally:
        session.close()
        Base.metadata.drop_all(bind=TEST_ENGINE)


@pytest.fixture(scope="function")
def client(db):
    from main import app

    def _override_get_db():
        try:
            yield db
        finally:
            pass

    app.dependency_overrides[get_db] = _override_get_db
    with InProcessTestClient(app, raise_server_exceptions=False) as c:
        yield c
    app.dependency_overrides.clear()


@pytest.fixture(scope="function")
def auth_headers(client):
    email = "realmode@example.com"
    password = "RealModePass!234"

    reg = client.post(
        "/api/auth/register",
        json={"email": email, "password": password, "password_confirm": password},
    )
    assert reg.status_code in (200, 201), reg.text

    login = client.post("/api/auth/login", json={"email": email, "password": password})
    assert login.status_code == 200, login.text
    token = login.json().get("access_token")
    assert token
    return {"Authorization": f"Bearer {token}"}
