import os
from pathlib import Path
import subprocess
import sys

from alembic import command
from alembic.config import Config
from sqlalchemy import create_engine, inspect


def test_clean_database_reaches_head_with_current_model_tables(tmp_path, monkeypatch):
    database_url = f"sqlite:///{tmp_path / 'migration.db'}"
    monkeypatch.setenv("DATABASE_URL", database_url)

    config = Config("alembic.ini")
    command.upgrade(config, "head")

    engine = create_engine(database_url)
    inspector = inspect(engine)
    tables = set(inspector.get_table_names())

    required_tables = {
        "audit_logs",
        "invoices",
        "subscriptions",
        "users",
        "vpn_connections",
        "vpn_demo_sessions",
        "vpn_servers",
    }
    assert required_tables <= tables
    assert "auth_token_version" in {
        column["name"] for column in inspector.get_columns("users")
    }
    assert "openvpn_credentials" in tables

    from database.base import Base
    from models import (
        audit_log,
        email_log,
        gdpr,
        invoice,
        subscription,
        support_ticket,
        usage_analytics,
        user,
        vpn_connection,
        vpn_demo_session,
        vpn_server,
        wireguard_peer,
    )

    for table in Base.metadata.tables.values():
        actual_columns = {column["name"] for column in inspector.get_columns(table.name)}
        assert {column.name for column in table.columns} <= actual_columns, table.name


def test_alembic_cli_suppresses_development_auto_create_side_effect(tmp_path):
    database_url = f"sqlite:///{tmp_path / 'fresh-cli-migration.db'}"
    environment = os.environ.copy()
    environment.update(
        {
            "DATABASE_URL": database_url,
            "ENVIRONMENT": "development",
            "AUTO_CREATE_TABLES": "true",
        }
    )
    result = subprocess.run(
        [sys.executable, "-m", "alembic", "upgrade", "head"],
        cwd=Path(__file__).resolve().parents[2],
        env=environment,
        check=False,
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, result.stdout + result.stderr
