"""HTTP authentication regression checks, including the upgraded JWT library."""
import secrets

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

# Registers all related models and establishes test-only environment defaults.
import test_vpn_client_owned_config  # noqa: F401
from database.base import Base
from database.session import get_db
from routes.auth import router
from services.jwt_service import create_access_token
from models.user import User


@pytest.fixture
def auth_client():
    engine = create_engine("sqlite:///:memory:",
                           connect_args={"check_same_thread": False}, poolclass=StaticPool)
    Base.metadata.create_all(engine)
    sessions = sessionmaker(bind=engine)
    app = FastAPI()
    app.include_router(router)

    def database():
        with sessions() as db:
            yield db

    app.dependency_overrides[get_db] = database
    with TestClient(app) as client:
        yield client, sessions
    Base.metadata.drop_all(engine)
    engine.dispose()


def test_register_login_and_logout_invalidates_old_token(auth_client):
    client, _ = auth_client
    password = secrets.token_urlsafe(24)
    credentials = {"email": "auth-review@example.com", "password": password}
    registration = client.post("/api/auth/register", json=credentials)
    assert registration.status_code == 201
    assert registration.headers["cache-control"] == "no-store"
    client.cookies.clear()
    headers = {"Authorization": "Bearer " + registration.json()["access_token"]}
    assert client.get("/api/auth/me", headers=headers).status_code == 200
    assert client.post("/api/auth/register", json=credentials).status_code == 400
    assert client.post("/api/auth/login", json={**credentials, "password": "incorrect"}).status_code == 401
    assert client.post("/api/auth/logout", headers=headers).status_code == 200
    client.cookies.clear()
    assert client.get("/api/auth/me", headers=headers).status_code == 401
    login = client.post("/api/auth/login", json=credentials)
    assert login.status_code == 200
    client.cookies.clear()
    assert client.get("/api/auth/me", headers={
        "Authorization": "Bearer " + login.json()["access_token"]}).status_code == 200


def test_refresh_token_and_inactive_account_cannot_access_me(auth_client):
    client, sessions = auth_client
    registration = client.post("/api/auth/register", json={
        "email": "inactive-review@example.com", "password": secrets.token_urlsafe(24)})
    assert registration.status_code == 201
    payload = registration.json()
    client.cookies.clear()
    assert client.get("/api/auth/me", headers={
        "Authorization": "Bearer " + payload["refresh_token"]}).status_code == 401
    with sessions() as db:
        user = db.query(User).filter_by(id=payload["user"]["id"]).one()
        token = create_access_token(user)
        user.is_active = False
        db.commit()
    assert client.get("/api/auth/me", headers={"Authorization": "Bearer " + token}).status_code == 401
