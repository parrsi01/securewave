from dev_tools.sandbox.live_validation.common import (
    evaluate_dns_leak,
    parse_latest_handshake_epoch,
    parse_wireguard_config,
)


def test_parse_wireguard_config_sections():
    text = """
[Interface]
PrivateKey = TEST_PRIVATE_KEY
Address = 10.88.0.2/32
DNS = 94.140.14.14

[Peer]
PublicKey = TEST_SERVER_PUBLIC_KEY
AllowedIPs = 0.0.0.0/0
Endpoint = 198.51.100.10:51820
"""
    parsed = parse_wireguard_config(text)
    assert parsed["interface"]["privatekey"] == "TEST_PRIVATE_KEY"
    assert parsed["peer"]["publickey"] == "TEST_SERVER_PUBLIC_KEY"
    assert parsed["peer"]["endpoint"] == "198.51.100.10:51820"


def test_parse_latest_handshake_epoch_filters_peer():
    output = """
peerA 1700000000
peerB 1700000300
"""
    assert parse_latest_handshake_epoch(output) == 1700000300
    assert parse_latest_handshake_epoch(output, "peerA") == 1700000000
    assert parse_latest_handshake_epoch(output, "peerX") == 0


def test_evaluate_dns_leak():
    allowed = {"94.140.14.14", "94.140.15.15"}
    clean, leaked = evaluate_dns_leak(["94.140.14.14", "127.0.0.53"], allowed)
    assert clean is True
    assert leaked == []

    clean2, leaked2 = evaluate_dns_leak(["8.8.8.8"], allowed, allow_private=True)
    assert clean2 is False
    assert leaked2 == ["8.8.8.8"]
