import asyncio

from services.vpn_server_key_lifecycle import VPNServerKeyLifecycleService


def test_seed_add_node_creates_or_updates_server(db):
    service = VPNServerKeyLifecycleService(db)
    created = service.seed_add_node(
        server_id="seed-hel1-01",
        location="Helsinki",
        country="Finland",
        country_code="FI",
        city="Helsinki",
        hcloud_location="hel1",
        public_ip="198.51.100.90",
        wg_public_key="dGVzdC1zZWVkLXNlcnZlci1rZXktYmFzZTY0LTEyMzQ1Njc4OTA=",
        allowed_ips="0.0.0.0/0, ::/0",
    )
    assert created.server_id == "seed-hel1-01"
    assert created.allowed_ips == "0.0.0.0/0, ::/0"
    assert created.endpoint == "198.51.100.90:51820"

    updated = service.seed_add_node(
        server_id="seed-hel1-01",
        location="Helsinki-2",
        country="Finland",
        country_code="FI",
        city="Espoo",
        hcloud_location="hel1",
        public_ip="198.51.100.91",
        wg_public_key="dGVzdC1zZWVkLXNlcnZlci1rZXktYmFzZTY0LXVwZGF0ZWQtMTIz",
        allowed_ips="10.0.0.0/8, ::/0",
    )
    assert updated.id == created.id
    assert updated.city == "Espoo"
    assert updated.endpoint == "198.51.100.91:51820"
    assert updated.allowed_ips == "10.0.0.0/8, ::/0"


def test_rotate_server_key_updates_version_and_timestamps(db):
    service = VPNServerKeyLifecycleService(db)
    server = service.seed_add_node(
        server_id="rotate-hel1-01",
        location="Helsinki",
        country="Finland",
        country_code="FI",
        city="Helsinki",
        hcloud_location="hel1",
        public_ip="198.51.100.92",
        wg_public_key="dGVzdC1yb3RhdGUtc2VydmVyLWtleS1iYXNlNjQtb3JpZ2luYWw=",
        allowed_ips="0.0.0.0/0, ::/0",
    )
    previous_version = server.wg_key_version
    previous_public_key = server.wg_public_key

    result = asyncio.run(service.rotate_server_key(server_id=server.server_id, apply_remote=False))
    assert result["server_id"] == server.server_id
    assert result["remote_applied"] is False
    assert result["wg_key_version"] == previous_version + 1

    db.refresh(server)
    assert server.wg_key_version == previous_version + 1
    assert server.wg_last_rotated_at is not None
    assert server.wg_next_rotation_at is not None
    assert server.wg_public_key != previous_public_key
    assert bool(server.wg_private_key_encrypted)
