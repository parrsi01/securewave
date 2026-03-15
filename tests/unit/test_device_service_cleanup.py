import pytest

from models.wireguard_peer import WireGuardPeer
from services.device_service import DeviceService
from services.wireguard_service import WireGuardService


class _StubWireGuardManager:
    def __init__(self):
        self.remove_calls: list[dict[str, str]] = []

    async def remove_peer(self, conn, public_key: str):
        self.remove_calls.append(
            {
                "server_id": conn.server_id,
                "public_key": public_key,
            }
        )
        return True, "peer removed"


@pytest.mark.asyncio
async def test_delete_device_removes_remote_peer_and_deletes_row(
    db,
    test_user,
    test_vpn_server,
    monkeypatch,
):
    wg_service = WireGuardService()
    private_key, public_key = wg_service.generate_keypair()
    peer = WireGuardPeer(
        user_id=test_user.id,
        server_id=test_vpn_server.id,
        device_name="Delete Me",
        device_type="linux",
        public_key=public_key,
        private_key_encrypted=wg_service.encrypt_private_key(private_key),
        ipv4_address="10.250.0.10/32",
        is_active=True,
        is_revoked=False,
    )
    db.add(peer)
    db.commit()
    db.refresh(peer)

    manager = _StubWireGuardManager()
    monkeypatch.setattr("services.device_service.get_wireguard_server_manager", lambda: manager)

    await DeviceService(db).delete_device(peer)

    assert manager.remove_calls == [
        {
            "server_id": test_vpn_server.server_id,
            "public_key": public_key,
        }
    ]
    assert db.query(WireGuardPeer).filter(WireGuardPeer.id == peer.id).first() is None
