#!/usr/bin/env python3
"""Run a local beta backend demo for the app VPN runtime path.

This script uses an isolated SQLite database and FastAPI TestClient. It proves
the backend path the Flutter app depends on can execute successfully for:
register -> login -> account -> plan/usage -> Linux protocol catalog ->
server inventory -> WireGuard/OpenVPN/IKEv2 profile issuance.

It does not start a tunnel and does not use production data.
"""

from __future__ import annotations

import argparse
import contextlib
import json
import os
import secrets
import sys
import tempfile
import time
from pathlib import Path
from typing import Any


PROTOCOLS = ("wireguard", "openvpn", "ikev2")
REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))


def _prefer_repo_venv() -> None:
    venv_python = REPO_ROOT / ".venv/bin/python"
    active_venv = Path(os.environ.get("VIRTUAL_ENV", "")).resolve() if os.environ.get("VIRTUAL_ENV") else None
    repo_venv = (REPO_ROOT / ".venv").resolve()
    if venv_python.exists() and active_venv != repo_venv:
        os.environ["VIRTUAL_ENV"] = str(repo_venv)
        os.execv(str(venv_python), [str(venv_python), *sys.argv])


def _set_demo_env(db_path: Path) -> None:
    os.environ.update(
        {
            "TESTING": "true",
            "DATABASE_URL": f"sqlite:///{db_path}",
            "SECRET_KEY": "beta-demo-secret-key-do-not-use-in-prod",
            "ACCESS_TOKEN_SECRET": "beta-demo-access-secret",
            "REFRESH_TOKEN_SECRET": "beta-demo-refresh-secret",
            "DEMO_MODE": "true",
            "WG_MOCK_MODE": "true",
            "ENVIRONMENT": "development",
            "ENABLE_SENTRY": "false",
            "EMAIL_VALIDATOR_CHECK_DELIVERABILITY": "false",
            "BCRYPT_ROUNDS": "4",
            "AUTO_CREATE_TABLES": "false",
            "WG_DATA_DIR": str(db_path.parent / "wg"),
            "SECUREWAVE_IKEV2_EAP_SECRET": "securewave-beta-ikev2-secret",
        }
    )


def _load_app(db_path: Path):
    _set_demo_env(db_path)

    from fastapi.testclient import TestClient
    from sqlalchemy import create_engine
    from sqlalchemy.orm import sessionmaker

    from database.base import Base
    from database.session import get_db

    from models import (  # noqa: F401
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
    from main import app

    engine = create_engine(
        f"sqlite:///{db_path}",
        connect_args={"check_same_thread": False},
        echo=False,
    )
    SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
    Base.metadata.create_all(bind=engine)
    session = SessionLocal()

    def _override_get_db():
        try:
            yield session
        finally:
            pass

    app.dependency_overrides[get_db] = _override_get_db
    return app, TestClient, session


def _seed_all_protocol_server(db) -> str:
    from models.vpn_server import VPNServer

    server_id = "beta-all-protocol-linux-1"
    server = VPNServer(
        server_id=server_id,
        location="Beta Runtime Node",
        country="United States",
        country_code="US",
        city="Ashburn",
        region="Americas",
        hcloud_location="ash",
        public_ip="10.77.0.10",
        endpoint="10.77.0.10:51820",
        wg_public_key="YmV0YS13Zy1wdWJsaWMta2V5",
        wg_private_key_encrypted="encrypted-beta-private-key",
        supports_wireguard=True,
        supports_openvpn=True,
        openvpn_endpoint="10.77.0.10",
        openvpn_port=1194,
        openvpn_transport="udp",
        openvpn_ca_cert_pem="-----BEGIN CERTIFICATE-----\nBETAOPENVPN\n-----END CERTIFICATE-----",
        supports_ikev2=True,
        ikev2_remote_id="vpn.beta.securewave.test",
        ikev2_ca_cert_pem="-----BEGIN CERTIFICATE-----\nBETAIKEV2\n-----END CERTIFICATE-----",
        status="active",
        health_status="healthy",
        max_connections=1000,
        current_connections=0,
        tier_restriction=None,
        performance_score=99.0,
        hcloud_server_state="running",
    )
    db.add(server)
    db.commit()
    return server_id


def _require(status_code: int, expected: set[int], label: str, body: Any) -> None:
    if status_code not in expected:
        raise RuntimeError(f"{label} failed: HTTP {status_code} {body}")


def run_demo(*, email: str | None = None, password: str | None = None) -> dict[str, Any]:
    original_env = os.environ.copy()
    with tempfile.TemporaryDirectory(prefix="securewave-beta-demo-") as tmp:
        db_path = Path(tmp) / "beta.sqlite3"
        try:
            app, test_client_cls, db = _load_app(db_path)
            server_id = _seed_all_protocol_server(db)
            email = email or f"beta.qa.{int(time.time())}.{secrets.token_hex(3)}@gmail.com"
            password = password or f"BetaSmoke{secrets.token_hex(4)}!A1"

            with test_client_cls(app, raise_server_exceptions=False) as client:
                registration = client.post(
                    "/api/auth/register",
                    json={
                        "email": email,
                        "password": password,
                        "password_confirm": password,
                    },
                )
                _require(registration.status_code, {200, 201}, "registration", registration.text)

                login = client.post(
                    "/api/auth/login",
                    json={"email": email, "password": password},
                )
                _require(login.status_code, {200}, "login", login.text)
                token = login.json().get("access_token")
                if not token:
                    raise RuntimeError("login returned no access_token")
                headers = {"Authorization": f"Bearer {token}"}

                account = client.get("/api/auth/me", headers=headers)
                _require(account.status_code, {200}, "account", account.text)

                plan = client.get("/api/user/plan", headers=headers)
                _require(plan.status_code, {200}, "plan", plan.text)

                protocols = client.get("/api/vpn/protocols?device_type=linux", headers=headers)
                _require(protocols.status_code, {200}, "protocols", protocols.text)
                protocol_map = {
                    item.get("protocol"): item for item in protocols.json().get("protocols", [])
                }
                unavailable = [
                    {
                        "protocol": protocol,
                        "reason": protocol_map.get(protocol, {}).get("reason"),
                        "platform_supported": protocol_map.get(protocol, {}).get("platform_supported"),
                        "server_enabled": protocol_map.get(protocol, {}).get("server_enabled"),
                    }
                    for protocol in PROTOCOLS
                    if protocol_map.get(protocol, {}).get("enabled") is not True
                ]
                if unavailable:
                    raise RuntimeError(f"protocols unavailable: {unavailable}")

                servers = client.get("/api/vpn/servers?device_type=linux", headers=headers)
                _require(servers.status_code, {200}, "servers", servers.text)
                server_items = servers.json().get("servers", [])
                if not server_items:
                    raise RuntimeError("server inventory returned no servers")
                supported = server_items[0].get("supported_protocols") or []
                missing = [protocol for protocol in PROTOCOLS if protocol not in supported]
                if missing:
                    raise RuntimeError(f"server missing supported_protocols: {missing}")

                profile_shapes: dict[str, dict[str, bool]] = {}
                profile_statuses: dict[str, int] = {}
                for protocol in PROTOCOLS:
                    profile = client.post(
                        "/api/vpn/profile",
                        json={
                            "device_name": "Beta Linux App Runtime",
                            "device_type": "linux",
                            "protocol": protocol,
                            "server_id": server_id,
                        },
                        headers=headers,
                    )
                    profile_statuses[protocol] = profile.status_code
                    _require(profile.status_code, {200}, f"{protocol} profile", profile.text)
                    body = profile.json()
                    config_key = {
                        "wireguard": "wireguard_config",
                        "openvpn": "openvpn_config",
                        "ikev2": "ikev2_config",
                    }[protocol]
                    if not body.get(config_key):
                        raise RuntimeError(f"{protocol} profile missing {config_key}")
                    profile_shapes[protocol] = {
                        "wireguard_config": bool(body.get("wireguard_config")),
                        "openvpn_config": bool(body.get("openvpn_config")),
                        "ikev2_config": bool(body.get("ikev2_config")),
                        "runnable_config": bool(body.get(config_key)),
                    }

                return {
                    "ok": True,
                    "email": email,
                    "account_email": account.json().get("email"),
                    "plan": plan.json().get("plan_name"),
                    "usage": {
                        "used_gb": plan.json().get("used_gb"),
                        "limit_gb": plan.json().get("data_cap_gb"),
                    },
                    "server_id": server_id,
                    "protocols_enabled": sorted(protocol_map),
                    "profile_statuses": profile_statuses,
                    "profile_shapes": profile_shapes,
                }
        finally:
            if "db" in locals():
                db.close()
            if "app" in locals():
                app.dependency_overrides.clear()
            os.environ.clear()
            os.environ.update(original_env)


def main() -> int:
    _prefer_repo_venv()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--email")
    parser.add_argument("--password")
    args = parser.parse_args()

    if args.json:
        with contextlib.redirect_stdout(sys.stderr):
            summary = run_demo(email=args.email, password=args.password)
    else:
        summary = run_demo(email=args.email, password=args.password)
    if args.json:
        print(json.dumps(summary, indent=2, sort_keys=True))
    else:
        print("OK beta backend app runtime demo")
        print(json.dumps(summary, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
