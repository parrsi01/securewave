"""Alembic-first database and request-boundary integration coverage."""

from pathlib import Path

import pytest
from alembic import command
from alembic.config import Config
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, inspect, text
from sqlalchemy.orm import sessionmaker


ROOT = Path(__file__).resolve().parents[2]


def _alembic_config(database_url: str) -> Config:
    config = Config(str(ROOT / "alembic.ini"))
    config.set_main_option("script_location", str(ROOT / "alembic"))
    config.set_main_option("sqlalchemy.url", database_url)
    return config


def test_fresh_migration_head_is_repeatable_and_covers_runtime_models(monkeypatch, tmp_path):
    database_url = f"sqlite:///{tmp_path / 'fresh.sqlite3'}"
    monkeypatch.setenv("DATABASE_URL", database_url)
    monkeypatch.setenv("AUTO_CREATE_TABLES", "false")
    config = _alembic_config(database_url)

    command.upgrade(config, "head")
    command.upgrade(config, "head")
    command.check(config)

    engine = create_engine(database_url)
    inspector = inspect(engine)
    tables = set(inspector.get_table_names())
    assert {"users", "vpn_servers", "vpn_connections", "vpn_usage_events", "invoices", "openvpn_credentials"} <= tables
    user_columns = {
        column["name"]: column for column in inspector.get_columns("users")
    }
    assert {"auth_token_version", "wg_peer_registered"} <= set(user_columns)
    assert user_columns["auth_token_version"]["nullable"] is False
    assert user_columns["auth_token_version"]["default"] is not None
    assert "connection_count" in {column["name"] for column in inspector.get_columns("wireguard_peers")}


def test_legacy_nullable_subscription_timestamp_is_backfilled(monkeypatch, tmp_path):
    database_url = f"sqlite:///{tmp_path / 'legacy-subscription.sqlite3'}"
    monkeypatch.setenv("DATABASE_URL", database_url)
    monkeypatch.setenv("AUTO_CREATE_TABLES", "false")
    config = _alembic_config(database_url)
    command.upgrade(config, "0001_init")

    engine = create_engine(database_url)
    with engine.begin() as connection:
        connection.execute(
            text(
                "INSERT INTO users (id, email, hashed_password) "
                "VALUES (1, 'legacy-subscription@example.com', 'not-a-real-hash')"
            )
        )
        connection.execute(
            text(
                "INSERT INTO subscriptions (id, user_id, provider, status, created_at) "
                "VALUES (1, 1, 'legacy', 'inactive', NULL)"
            )
        )

    command.upgrade(config, "head")

    with engine.connect() as connection:
        created_at = connection.execute(
            text("SELECT created_at FROM subscriptions WHERE id = 1")
        ).scalar_one()
    assert created_at is not None
    columns = {
        column["name"]: column for column in inspect(engine).get_columns("subscriptions")
    }
    assert columns["created_at"]["nullable"] is False


def test_legacy_orm_audit_shape_upgrades_without_duplicate_columns(monkeypatch, tmp_path):
    database_url = f"sqlite:///{tmp_path / 'legacy.sqlite3'}"
    monkeypatch.setenv("DATABASE_URL", database_url)
    monkeypatch.setenv("AUTO_CREATE_TABLES", "false")
    config = _alembic_config(database_url)
    command.upgrade(config, "0004")

    # Simulate the former runtime create_all path that pre-created the current
    # audit table before revision 0005 ran.
    from database.base import Base
    from models import audit_log, email_log, gdpr, invoice, openvpn_credential, subscription, support_ticket, usage_analytics, user, vpn_connection, vpn_demo_session, vpn_server, vpn_usage_event, wireguard_peer  # noqa: F401

    engine = create_engine(database_url)
    Base.metadata.tables["audit_logs"].create(bind=engine, checkfirst=False)
    command.upgrade(config, "head")

    columns = {column["name"] for column in inspect(engine).get_columns("audit_logs")}
    assert {"event_type", "event_category", "success", "created_at"} <= columns


def test_offline_sql_is_explicitly_rejected_for_adaptive_reconciliation(monkeypatch, tmp_path):
    database_url = f"sqlite:///{tmp_path / 'offline.sqlite3'}"
    monkeypatch.setenv("DATABASE_URL", database_url)
    monkeypatch.setenv("AUTO_CREATE_TABLES", "false")
    config = _alembic_config(database_url)

    with pytest.raises(RuntimeError, match="requires an online database inspection"):
        command.upgrade(config, "head", sql=True)


def test_migrated_database_serves_auth_at_real_request_boundary(monkeypatch, tmp_path):
    database_url = f"sqlite:///{tmp_path / 'api.sqlite3'}"
    monkeypatch.setenv("DATABASE_URL", database_url)
    monkeypatch.setenv("AUTO_CREATE_TABLES", "false")
    command.upgrade(_alembic_config(database_url), "head")

    from database.session import get_db
    from main import app
    from models.user import User
    from services.hashing_service import hash_password

    engine = create_engine(database_url, connect_args={"check_same_thread": False})
    session_factory = sessionmaker(autocommit=False, autoflush=False, bind=engine)
    seed = session_factory()
    seed.add(
        User(
            email="migrated-boundary@example.com",
            hashed_password=hash_password("MigratedPass123"),
            email_verified=True,
            is_active=True,
        )
    )
    seed.commit()
    seed.close()

    def override_get_db():
        db = session_factory()
        try:
            yield db
        finally:
            db.close()

    app.dependency_overrides[get_db] = override_get_db
    try:
        with TestClient(app, raise_server_exceptions=False) as client:
            response = client.post(
                "/api/auth/login",
                json={"email": "MIGRATED-BOUNDARY@example.com", "password": "MigratedPass123"},
            )
        assert response.status_code == 200, response.text
        assert response.json()["access_token"]
    finally:
        app.dependency_overrides.clear()
