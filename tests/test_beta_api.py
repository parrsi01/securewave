import os

os.environ["ENVIRONMENT"] = "testing"
os.environ["TESTING"] = "true"
os.environ["DATABASE_URL"] = "sqlite:///:memory:"
os.environ["ACCESS_TOKEN_SECRET"] = "test-access-secret-stable"
os.environ["WG_ENCRYPTION_KEY"] = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
os.environ["WIREGUARD_SERVER_ID"] = "securewave-beta"

from fastapi.testclient import TestClient
from sqlalchemy import delete

from database.base import Base
from database.session import SessionLocal, engine
from main import app
from models.user import User
from models.vpn_server import VPNServer
from models.wireguard_peer import WireGuardPeer


def _seed_database() -> None:
    Base.metadata.drop_all(bind=engine)
    Base.metadata.create_all(bind=engine)
    with SessionLocal() as db:
        db.add(
            VPNServer(
                server_id="securewave-beta",
                city="Helsinki",
                country="Finland",
                public_ip="203.0.113.10",
                endpoint="203.0.113.10:51820",
                wg_public_key="A" * 43,
                wg_private_key_encrypted="encrypted-server-key",
                status="active",
                health_status="healthy",
                supports_wireguard=True,
            )
        )
        db.commit()


def test_beta_auth_target_and_profile_flow() -> None:
    _seed_database()
    with TestClient(app) as client:
        registered = client.post(
            "/api/auth/register",
            json={"email": "Beta.User@example.com", "password": "Secure123"},
        )
        assert registered.status_code == 201
        token = registered.json()["access_token"]
        assert set(registered.json()) == {"access_token", "token_type"}
        headers = {"Authorization": f"Bearer {token}"}

        assert client.get("/api/auth/me", headers=headers).json()["email"] == "beta.user@example.com"
        assert client.post(
            "/api/auth/login",
            json={"email": "beta.user@example.com", "password": "wrong-password"},
        ).status_code == 401

        target = client.get("/api/vpn/target", headers=headers)
        assert target.status_code == 200
        assert target.json()["protocol"] == "wireguard"
        assert target.json()["server_id"] == "securewave-beta"

        profile = client.post("/api/vpn/profile", headers=headers, json={})
        assert profile.status_code == 200
        assert "[Interface]" in profile.json()["wireguard_config"]
        assert "[Peer]" in profile.json()["wireguard_config"]

        assert client.post("/api/auth/logout", headers=headers).status_code == 200
        assert client.get("/api/auth/me", headers=headers).status_code == 401


def test_beta_does_not_expose_legacy_api_routes() -> None:
    _seed_database()
    with TestClient(app) as client:
        for path in ("/api/billing/subscriptions", "/api/servers", "/api/auth/verify-email"):
            assert client.get(path).status_code in {404, 405}


def test_beta_site_and_candidate_manifest_are_served() -> None:
    with TestClient(app) as client:
        assert client.get("/").status_code == 200
        assert client.get("/download").status_code == 200
        manifest = client.get("/downloads/manifest.json")
        assert manifest.status_code == 200
        assert manifest.json()["architecture"] == "arm64"
