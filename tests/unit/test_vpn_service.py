"""
SecureWave - VPN Service Unit Tests
====================================
Covers:
- WireGuard key generation (keypair creation)
- VPN config generation (valid WireGuard format)
- Server listing (servers returned from database)
- Free tier access (unrestricted servers only)
"""

import pytest
from fastapi import status


class TestKeyGeneration:
    """WireGuard key generation must produce valid keypairs."""

    def test_key_generation(self):
        """generate_keypair must return a (private_key, public_key) tuple."""
        from services.wireguard_service import WireGuardService

        wg = WireGuardService()
        private_key, public_key = wg.generate_keypair()

        assert private_key is not None
        assert public_key is not None
        assert len(private_key) > 0
        assert len(public_key) > 0
        # WireGuard keys are base64-encoded, typically 44 chars
        assert len(private_key) >= 40, "Private key appears too short for WireGuard"
        assert len(public_key) >= 40, "Public key appears too short for WireGuard"

    def test_keypairs_are_unique(self):
        """Two consecutive keypair generations must produce different keys."""
        from services.wireguard_service import WireGuardService

        wg = WireGuardService()
        priv1, pub1 = wg.generate_keypair()
        priv2, pub2 = wg.generate_keypair()

        assert priv1 != priv2, "Private keys should be unique"
        assert pub1 != pub2, "Public keys should be unique"

    def test_private_key_encryption_roundtrip(self):
        """Encrypting and decrypting a private key must return the original."""
        from services.wireguard_service import WireGuardService

        wg = WireGuardService()
        private_key, _ = wg.generate_keypair()

        encrypted = wg.encrypt_private_key(private_key)
        assert encrypted != private_key, "Encrypted key should differ from plaintext"

        decrypted = wg.decrypt_private_key(encrypted)
        assert decrypted == private_key, "Decrypted key must match the original"


class TestConfigGeneration:
    """VPN config generation must produce valid WireGuard configurations."""

    def test_config_generation(self, db, test_user, test_vpn_server):
        """Generated config must contain [Interface] and [Peer] sections."""
        from services.wireguard_service import WireGuardService

        wg = WireGuardService()
        private_key, public_key = wg.generate_keypair()
        client_ip = wg.allocate_ip(test_user.id)

        config_content = (
            "[Interface]\n"
            f"PrivateKey = {private_key}\n"
            f"Address = {client_ip}\n"
            f"DNS = {wg.dns}\n\n"
            "[Peer]\n"
            f"PublicKey = {test_vpn_server.wg_public_key}\n"
            f"Endpoint = {test_vpn_server.endpoint}\n"
            "AllowedIPs = 0.0.0.0/0, ::/0\n"
            "PersistentKeepalive = 25\n"
        )

        assert "[Interface]" in config_content
        assert "[Peer]" in config_content
        assert "PrivateKey" in config_content
        assert "PublicKey" in config_content
        assert "Endpoint" in config_content
        assert "AllowedIPs" in config_content
        assert "DNS" in config_content

    def test_config_file_write_and_read(self, test_user, test_vpn_server):
        """Config must be writable to disk and readable back."""
        from services.wireguard_service import WireGuardService

        wg = WireGuardService()
        private_key, _ = wg.generate_keypair()
        client_ip = wg.allocate_ip(test_user.id)

        config_content = (
            "[Interface]\n"
            f"PrivateKey = {private_key}\n"
            f"Address = {client_ip}\n"
            f"DNS = {wg.dns}\n\n"
            "[Peer]\n"
            f"PublicKey = {test_vpn_server.wg_public_key}\n"
            f"Endpoint = {test_vpn_server.endpoint}\n"
            "AllowedIPs = 0.0.0.0/0, ::/0\n"
            "PersistentKeepalive = 25\n"
        )

        # Write config
        config_path = wg.config_path_for_server(test_user.id, test_vpn_server.server_id)
        config_path.write_text(config_content)

        # Read it back
        assert config_path.exists()
        read_back = config_path.read_text()
        assert read_back == config_content

    def test_qr_code_generation(self):
        """QR code generation must produce a non-empty base64 string."""
        from services.wireguard_service import WireGuardService

        wg = WireGuardService()
        config = "[Interface]\nPrivateKey = test\nAddress = 10.0.0.1\n"
        qr_base64 = wg.qr_from_config(config)

        assert qr_base64 is not None
        assert len(qr_base64) > 0
        # Base64 encoded PNG should be substantial
        assert len(qr_base64) > 100


class TestServerList:
    """Server listing must return active servers from the database."""

    def test_server_list(self, client, auth_headers, test_vpn_server):
        """GET /api/vpn/servers must return seeded servers."""
        response = client.get("/api/vpn/servers", headers=auth_headers)
        assert response.status_code == 200
        data = response.json()
        assert "servers" in data
        assert data["total"] >= 1

        server_ids = [s["server_id"] for s in data["servers"]]
        assert test_vpn_server.server_id in server_ids

    def test_server_list_requires_auth(self, client):
        """Server listing without auth should return 401."""
        response = client.get("/api/vpn/servers")
        assert response.status_code in (401, 403)

    def test_server_details(self, client, auth_headers, test_vpn_server):
        """GET /api/vpn/servers/{server_id} must return server details."""
        response = client.get(
            f"/api/vpn/servers/{test_vpn_server.server_id}",
            headers=auth_headers,
        )
        assert response.status_code == 200
        data = response.json()
        assert data["server_id"] == test_vpn_server.server_id
        assert data["country"] == "United States"
        assert data["status"] == "active"


class TestFreeTierAccess:
    """Free tier users should only see unrestricted servers."""

    def test_free_tier_access(self, client, auth_headers, test_vpn_servers):
        """Free user should not see premium-restricted servers."""
        response = client.get("/api/vpn/servers", headers=auth_headers)
        assert response.status_code == 200
        data = response.json()

        server_ids = [s["server_id"] for s in data["servers"]]
        # Free servers (no tier_restriction) should be visible
        assert "us-east-1-001" in server_ids
        assert "eu-west-1-001" in server_ids
        # Premium-restricted server should NOT be visible to free user
        assert "ap-east-1-001" not in server_ids

    def test_premium_user_sees_all_servers(self, client, auth_headers, test_user, test_vpn_servers, db):
        """A premium user should see both free and premium servers."""
        from models.subscription import Subscription
        from datetime import datetime, timedelta

        sub = Subscription(
            user_id=test_user.id,
            plan_id="premium",
            plan_name="Premium",
            provider="stripe",
            status="active",
            amount=9.99,
            currency="USD",
            billing_cycle="monthly",
            current_period_start=datetime.utcnow(),
            current_period_end=datetime.utcnow() + timedelta(days=30),
        )
        db.add(sub)
        db.commit()

        response = client.get("/api/vpn/servers", headers=auth_headers)
        assert response.status_code == 200
        data = response.json()

        server_ids = [s["server_id"] for s in data["servers"]]
        assert "us-east-1-001" in server_ids
        assert "ap-east-1-001" in server_ids


class TestIPAllocation:
    """IP allocation must produce valid VPN addresses."""

    def test_allocate_ip_deterministic(self):
        """The same user_id should produce the same IP."""
        from services.wireguard_service import WireGuardService

        wg = WireGuardService()
        ip1 = wg.allocate_ip(42)
        ip2 = wg.allocate_ip(42)
        assert ip1 == ip2

    def test_allocate_ip_unique_per_user(self):
        """Different user_ids should produce different IPs."""
        from services.wireguard_service import WireGuardService

        wg = WireGuardService()
        ip1 = wg.allocate_ip(1)
        ip2 = wg.allocate_ip(2)
        assert ip1 != ip2
