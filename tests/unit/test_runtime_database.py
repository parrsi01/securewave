"""Regression coverage for runtime database initialization and error handling."""

import logging
import os
import subprocess
import sys
from pathlib import Path

import pytest
from fastapi import HTTPException


ROOT = Path(__file__).resolve().parents[2]


def test_development_auto_create_registers_route_models(tmp_path):
    """Import-time table creation must include models loaded by API routes."""
    database_url = f"sqlite:///{tmp_path / 'runtime.db'}"
    script = """
from sqlalchemy import inspect
from database.session import engine

tables = set(inspect(engine).get_table_names())
assert 'wireguard_peers' in tables, sorted(tables)
assert 'support_tickets' in tables, sorted(tables)
"""
    env = os.environ.copy()
    env.update(
        {
            "AUTO_CREATE_TABLES": "true",
            "DATABASE_URL": database_url,
            "ENVIRONMENT": "development",
            "PYTHONPATH": str(ROOT),
            "TESTING": "true",
        }
    )

    result = subprocess.run(
        [sys.executable, "-c", script],
        cwd=ROOT,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0, f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"


def test_check_database_connection_executes_probe():
    from database.session import check_database_connection

    assert check_database_connection() is True


def test_get_db_does_not_log_http_exception_as_database_failure(caplog):
    from database.session import get_db

    caplog.set_level(logging.ERROR, logger="database.session")
    dependency = get_db()
    next(dependency)

    with pytest.raises(HTTPException):
        dependency.throw(HTTPException(status_code=401, detail="not authenticated"))

    assert "Database session error" not in caplog.text


def test_api_remains_available_when_redis_rate_limit_backend_is_down(tmp_path):
    """A Redis outage must degrade rate-limit storage without taking down HTTP."""
    script = """
from fastapi.testclient import TestClient
from main import app

with TestClient(app, raise_server_exceptions=False) as client:
    response = client.get('/api/health')
    print(response.status_code, response.text)
    assert response.status_code == 200
"""
    env = os.environ.copy()
    env.update(
        {
            "AUTO_CREATE_TABLES": "true",
            "DATABASE_URL": f"sqlite:///{tmp_path / 'redis-outage.db'}",
            "DEMO_MODE": "true",
            "ENVIRONMENT": "development",
            "REDIS_URL": "redis://127.0.0.1:6399/0",
            "SECRET_KEY": "runtime-test-secret",
            "ACCESS_TOKEN_SECRET": "runtime-test-access-secret",
            "REFRESH_TOKEN_SECRET": "runtime-test-refresh-secret",
            "TESTING": "false",
            "WG_DATA_DIR": str(tmp_path / "wg"),
            "WG_MOCK_MODE": "true",
            "PYTHONPATH": str(ROOT),
        }
    )

    result = subprocess.run(
        [sys.executable, "-c", script],
        cwd=ROOT,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0, f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"


def test_static_mount_rejects_hidden_files(client):
    """Public asset mounts must not serve dotfiles from the workspace."""
    hidden = client.get("/static/.env")
    public = client.get("/static/index.html")

    assert hidden.status_code == 404
    assert public.status_code == 200


def test_readiness_returns_service_unavailable_when_database_fails(client, monkeypatch):
    """Readiness must fail at the HTTP layer without exposing DB details."""
    import main

    class FailingSession:
        def execute(self, statement):
            raise RuntimeError("postgres://internal-host:5432/securewave")

        def close(self):
            pass

    monkeypatch.setattr(main, "SessionLocal", lambda: FailingSession())

    response = client.get("/api/ready")

    assert response.status_code == 503
    assert response.json() == {"status": "not_ready", "error": "database unavailable"}
    assert "internal-host" not in response.text
