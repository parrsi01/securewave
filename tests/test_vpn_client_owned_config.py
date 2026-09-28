import asyncio
import os

os.environ["TESTING"] = "true"
os.environ["DATABASE_URL"] = "sqlite:///:memory:"
os.environ["ACCESS_TOKEN_SECRET"] = "test-only-access-token-secret"
os.environ["WG_MOCK_MODE"] = "true"
os.environ["WG_AUTO_REGISTER_PEERS"] = "true"
os.environ["SECUREWAVE_WG_KEEPALIVE"] = "25"
os.environ["ENVIRONMENT"] = "development"

import base64

import pytest
from fastapi import HTTPException
from fastapi.routing import APIRoute
from pydantic import ValidationError
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

import routes.auth as auth_routes
import routes.vpn as vpn_routes
from database.base import Base
from models.user import User
from models.vpn_server import VPNServer
from models.wireguard_peer import WireGuardPeer
from services.jwt_service import get_current_user


def _public_key(fill_byte: int) -> str:
    return base64.b64encode(bytes([fill_byte]) * 32).decode("ascii")


@pytest.fixture
def provisioning(monkeypatch):
    engine = create_engine(
        "sqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(engine)
    session_factory = sessionmaker(bind=engine, autoflush=False, autocommit=False)
    db = session_factory()

    user = User(email="client-key-owner@example.test", hashed_password="not-used")
    other_user = User(email="other-key-owner@example.test", hashed_password="not-used")
    server = VPNServer(
        server_id="test-wireguard-1",
        location="Test Region",
        country="Test Country",
        country_code="TC",
        city="Test City",
        public_ip="203.0.113.10",
        endpoint="vpn.example.test:51820",
        wg_listen_port=51820,
        wg_public_key=_public_key(2),
        wg_private_key_encrypted="server-private-key-is-not-used-in-this-test",
        dns_servers="94.140.14.14,94.140.15.15",
        allowed_ips="0.0.0.0/0, ::/0",
        supports_wireguard=True,
        status="active",
        health_status="healthy",
        current_connections=0,
        max_connections=100,
    )
    db.add_all([user, other_user, server])
    db.commit()
    db.refresh(user)
    db.refresh(other_user)
    db.refresh(server)

    def select_server(_db, _user, _server_id):
        return server

    registered = []
    registration_results = [True]
    live_peers = {}

    async def register_peer(_server, peer):
        registered.append((peer.public_key, peer.ipv4_address))
        return registration_results.pop(0) if registration_results else True

    async def inspect_live_state():
        return {
            "server_public_key": server.wg_public_key,
            "listen_port": server.wg_listen_port,
            "peers": {key: list(prefixes) for key, prefixes in live_peers.items()},
        }

    monkeypatch.setattr(vpn_routes, "_select_server", select_server)
    monkeypatch.setattr(vpn_routes, "_register_client_owned_peer", register_peer)
    monkeypatch.setattr(
        vpn_routes.wireguard_helper_client, "inspect_state", inspect_live_state
    )
    monkeypatch.setattr(vpn_routes, "get_effective_device_limit", lambda *_: 1)

    async def allow_subscription(_db, _user):
        return None

    monkeypatch.setattr(vpn_routes, "require_active_subscription", allow_subscription)

    yield {
        "db": db,
        "user": user,
        "other_user": other_user,
        "server": server,
        "registered": registered,
        "registration_results": registration_results,
        "live_peers": live_peers,
    }

    db.close()
    Base.metadata.drop_all(engine)
    engine.dispose()


def _post_config(provisioning, body, user=None):
    payload = vpn_routes.ClientWireGuardConfigRequest.model_validate(body)
    return asyncio.run(
        vpn_routes.provision_client_wireguard_config(
            None,
            payload,
            user or provisioning["user"],
            provisioning["db"],
        )
    )


def test_post_config_registers_client_public_key_without_private_key(provisioning):
    key = _public_key(7)

    response = _post_config(provisioning, {"public_key": key})

    payload = response.model_dump()
    config = payload["wireguard_config"]
    assert payload["server_location"] == "Test City, Test Country"
    assert "Address = 10.8.0.10/32" in config
    assert f"PublicKey = {_public_key(2)}" in config
    assert "Endpoint = vpn.example.test:51820" in config
    assert "AllowedIPs = 0.0.0.0/0, ::/0" in config
    assert "DNS = 94.140.14.14,94.140.15.15" in config
    assert "PersistentKeepalive = 25" in config
    assert "PrivateKey" not in config
    assert provisioning["server"].wg_private_key_encrypted not in repr(payload)
    assert provisioning["registered"] == [(key, "10.8.0.10/32")]

    peer = provisioning["db"].query(WireGuardPeer).filter_by(public_key=key).one()
    assert peer.user_id == provisioning["user"].id
    assert peer.is_active is True
    assert peer.private_key_encrypted == ""
    assert provisioning["user"].wg_private_key_encrypted is None


def test_post_config_reuses_public_key_and_client_address(provisioning):
    key = _public_key(8)

    first = _post_config(provisioning, {"public_key": key})
    second = _post_config(provisioning, {"public_key": key})

    assert first.wireguard_config == second.wireguard_config
    assert [address for _, address in provisioning["registered"]] == [
        "10.8.0.10/32",
        "10.8.0.10/32",
    ]
    assert provisioning["db"].query(WireGuardPeer).filter_by(public_key=key).count() == 1


def test_post_config_skips_address_already_used_by_live_wireguard_peer(provisioning):
    provisioning["live_peers"][_public_key(18)] = ["10.8.0.10/32"]

    response = _post_config(provisioning, {"public_key": _public_key(19)})

    assert "Address = 10.8.0.11/32" in response.wireguard_config
    assert provisioning["registered"] == [(_public_key(19), "10.8.0.11/32")]


def test_post_config_fails_closed_when_live_wireguard_state_is_unavailable(
    provisioning, monkeypatch
):
    async def unavailable():
        raise vpn_routes.wireguard_helper_client.WireGuardHelperError("unavailable")

    monkeypatch.setattr(
        vpn_routes.wireguard_helper_client, "inspect_state", unavailable
    )

    with pytest.raises(HTTPException) as failed:
        _post_config(provisioning, {"public_key": _public_key(20)})

    assert failed.value.status_code == 503
    assert provisioning["registered"] == []
    assert provisioning["db"].query(WireGuardPeer).count() == 0


def test_post_config_rejects_invalid_key_and_private_key_field(provisioning):
    with pytest.raises(HTTPException) as invalid:
        _post_config(provisioning, {"public_key": "!" * 44})
    with pytest.raises(ValidationError):
        _post_config(
            provisioning,
            {"public_key": _public_key(9), "private_key": _public_key(10)},
        )

    assert invalid.value.status_code == 422
    assert provisioning["registered"] == []
    assert provisioning["db"].query(WireGuardPeer).count() == 0


def test_post_config_refuses_key_assigned_to_another_user(provisioning):
    key = _public_key(11)
    _post_config(provisioning, {"public_key": key})

    with pytest.raises(HTTPException) as second:
        _post_config(provisioning, {"public_key": key}, provisioning["other_user"])

    assert second.value.status_code == 409
    assert len(provisioning["registered"]) == 1


def test_post_config_enforces_existing_device_limit(provisioning):
    existing = WireGuardPeer(
        user_id=provisioning["user"].id,
        server_id=provisioning["server"].id,
        public_key=_public_key(14),
        private_key_encrypted="existing-server-owned-peer",
        ipv4_address="10.8.0.14/32",
        is_active=True,
        is_revoked=False,
    )
    provisioning["db"].add(existing)
    provisioning["db"].commit()

    with pytest.raises(HTTPException) as rejected:
        _post_config(provisioning, {"public_key": _public_key(15)})

    assert rejected.value.status_code == 403
    assert provisioning["registered"] == []


def test_post_config_does_not_claim_success_without_remote_peer_registration(provisioning):
    provisioning["registration_results"][:] = [False, True]
    key = _public_key(12)

    with pytest.raises(HTTPException) as failed:
        _post_config(provisioning, {"public_key": key})
    retry = _post_config(provisioning, {"public_key": key})

    assert failed.value.status_code == 503
    assert retry.wireguard_config
    peer = provisioning["db"].query(WireGuardPeer).filter_by(public_key=key).one()
    assert peer.is_active is True
    assert peer.private_key_encrypted == ""


def _install_local_wireguard_mock(
    monkeypatch, *, peers=None, fail_save=False, local_public_key=None
):
    state = {key: set(networks) for key, networks in (peers or {}).items()}
    calls = []
    helper_calls = []

    async def run(command):
        calls.append(command)
        if command == ("/usr/sbin/ip", "-4", "route", "get", "1.1.1.1"):
            return True, "1.1.1.1 via 203.0.113.1 dev eth0 src 203.0.113.10 uid 1000"
        if command == ("/usr/sbin/ip", "-4", "address", "show", "dev", "wg0"):
            return True, "2: wg0: <POINTOPOINT,UP> mtu 1420\n    inet 10.8.0.1/24 scope global wg0"
        return False, ""

    async def inspect_state():
        helper_calls.append(("inspect",))
        return {
            "server_public_key": local_public_key or _public_key(2),
            "listen_port": 51820,
            "peers": {key: sorted(networks) for key, networks in state.items()},
        }

    async def ensure_peer(public_key, address):
        helper_calls.append(("ensure", public_key, address))
        if fail_save:
            raise vpn_routes.wireguard_helper_client.WireGuardHelperError(
                "peer persistence failed"
            )
        if public_key in state and state[public_key] != {address}:
            raise vpn_routes.wireguard_helper_client.WireGuardHelperError(
                "peer assignment conflicts"
            )
        state[public_key] = {address}

    async def remove_peer(public_key, address):
        helper_calls.append(("remove", public_key, address))
        if state.get(public_key) != {address}:
            raise vpn_routes.wireguard_helper_client.WireGuardHelperError(
                "peer assignment conflicts"
            )
        state.pop(public_key)

    monkeypatch.setattr(vpn_routes, "_run_local_command", run)
    monkeypatch.setattr(vpn_routes.wireguard_helper_client, "inspect_state", inspect_state)
    monkeypatch.setattr(vpn_routes.wireguard_helper_client, "ensure_peer", ensure_peer)
    monkeypatch.setattr(vpn_routes.wireguard_helper_client, "remove_peer", remove_peer)
    return state, calls, helper_calls


def _registration_targets():
    server = VPNServer(
        public_ip="203.0.113.10",
        wg_listen_port=51820,
        wg_public_key=_public_key(2),
    )
    peer = WireGuardPeer(public_key=_public_key(16), ipv4_address="10.8.0.16/32")
    return server, peer


def test_peer_registration_uses_local_wireguard_and_saves_exact_client_prefix(monkeypatch):
    server, peer = _registration_targets()
    state, commands, helper_calls = _install_local_wireguard_mock(monkeypatch)

    assert asyncio.run(vpn_routes._register_client_owned_peer(server, peer)) is True

    assert state[peer.public_key] == {"10.8.0.16/32"}
    assert ("ensure", peer.public_key, "10.8.0.16/32") in helper_calls
    assert helper_calls.count(("inspect",)) == 2
    assert all(command[0] == "/usr/sbin/ip" for command in commands)


def test_peer_registration_reuses_only_exact_existing_assignment(monkeypatch):
    server, peer = _registration_targets()
    state, commands, helper_calls = _install_local_wireguard_mock(
        monkeypatch, peers={peer.public_key: {"10.8.0.16/32"}}
    )

    assert asyncio.run(vpn_routes._register_client_owned_peer(server, peer)) is True

    assert state[peer.public_key] == {"10.8.0.16/32"}
    assert ("ensure", peer.public_key, "10.8.0.16/32") in helper_calls
    assert all(command[0] == "/usr/sbin/ip" for command in commands)


@pytest.mark.parametrize(
    "existing_prefixes",
    [
        {"10.8.0.0/24"},
        {"10.8.0.16/32", "10.8.0.17/32"},
    ],
)
def test_peer_registration_rejects_wrong_or_extra_assigned_prefixes(
    monkeypatch, existing_prefixes
):
    server, peer = _registration_targets()
    state, commands, helper_calls = _install_local_wireguard_mock(
        monkeypatch, peers={peer.public_key: existing_prefixes}
    )

    assert asyncio.run(vpn_routes._register_client_owned_peer(server, peer)) is False
    assert state[peer.public_key] == existing_prefixes
    assert not any(item[0] == "ensure" for item in helper_calls)
    assert all(command[0] == "/usr/sbin/ip" for command in commands)


def test_peer_registration_rejects_address_claimed_by_another_peer(monkeypatch):
    server, peer = _registration_targets()
    other_key = _public_key(17)
    state, commands, helper_calls = _install_local_wireguard_mock(
        monkeypatch, peers={other_key: {"10.8.0.0/24"}}
    )

    assert asyncio.run(vpn_routes._register_client_owned_peer(server, peer)) is False
    assert other_key in state
    assert peer.public_key not in state
    assert not any(item[0] == "ensure" for item in helper_calls)
    assert all(command[0] == "/usr/sbin/ip" for command in commands)


def test_peer_registration_fails_closed_on_local_server_identity_mismatch(monkeypatch):
    server, peer = _registration_targets()
    _install_local_wireguard_mock(monkeypatch, local_public_key=_public_key(3))
    assert asyncio.run(vpn_routes._register_client_owned_peer(server, peer)) is False


def test_peer_registration_rolls_back_runtime_peer_when_persistence_fails(monkeypatch):
    server, peer = _registration_targets()
    state, _, _ = _install_local_wireguard_mock(monkeypatch, fail_save=True)

    assert asyncio.run(vpn_routes._register_client_owned_peer(server, peer)) is False
    assert peer.public_key not in state


def test_registration_accepts_email_and_password_without_confirmation():
    payload = auth_routes.RegisterRequest.model_validate(
        {"email": "new-user@example.com", "password": "correct-horse-battery"}
    )

    assert payload.password_confirm is None
    auth_routes._validate_password(payload.password)


def test_registration_keeps_optional_confirmation_and_minimum_password_validation():
    payload = auth_routes.RegisterRequest.model_validate(
        {
            "email": "new-user@example.com",
            "password": "correct-horse-battery",
            "password_confirm": "different-password",
        }
    )

    with pytest.raises(HTTPException, match="Passwords do not match"):
        auth_routes._validate_password(payload.password, payload.password_confirm)
    with pytest.raises(HTTPException, match="at least 8 characters"):
        auth_routes._validate_password("short")


def test_post_config_route_uses_existing_auth_dependency():
    route = next(
        route
        for route in vpn_routes.router.routes
        if isinstance(route, APIRoute)
        and route.path == "/api/vpn/config"
        and "POST" in route.methods
    )

    assert any(dependency.call is get_current_user for dependency in route.dependant.dependencies)
