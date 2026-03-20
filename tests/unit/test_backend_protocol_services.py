from __future__ import annotations

from backend.services.ikev2_service import IKEv2Service
from backend.services.openvpn_service import OpenVPNService
from backend.services.wireguard_service import WireGuardService


class _StubPrivilegedNetworkService:
    def __init__(self) -> None:
        self.calls: list[tuple[str, dict]] = []

    def setup_protocol(self, **kwargs) -> None:
        self.calls.append(("setup", kwargs))

    def teardown_protocol(self, **kwargs) -> None:
        self.calls.append(("teardown", kwargs))


def test_wireguard_service_delegates_setup_and_teardown_to_privileged_wrapper(monkeypatch) -> None:
    monkeypatch.setenv("WG_CIDR", "10.8.0.0/24")
    monkeypatch.setenv("WG_EGRESS_IFACE", "eth9")
    monkeypatch.setenv("WG_TUNNEL_IFACE", "wg9")

    stub = _StubPrivilegedNetworkService()
    service = WireGuardService(privileged_network=stub)

    service.setup_network_state()
    service.teardown_network_state()

    assert stub.calls[0][0] == "setup"
    assert stub.calls[0][1]["protocol"] == "wireguard"
    assert stub.calls[0][1]["source_cidr"] == "10.8.0.0/24"
    assert stub.calls[0][1]["tunnel_iface"] == "wg9"
    assert stub.calls[0][1]["egress_iface"] == "eth9"
    assert callable(stub.calls[0][1]["legacy_fallback"])

    assert stub.calls[1][0] == "teardown"
    assert stub.calls[1][1]["protocol"] == "wireguard"
    assert stub.calls[1][1]["source_cidr"] == "10.8.0.0/24"
    assert stub.calls[1][1]["tunnel_iface"] == "wg9"
    assert stub.calls[1][1]["egress_iface"] == "eth9"
    assert callable(stub.calls[1][1]["legacy_fallback"])


def test_openvpn_service_delegates_to_privileged_wrapper(monkeypatch) -> None:
    monkeypatch.setenv("OVPN_CIDR", "10.44.0.0/24")
    monkeypatch.setenv("OVPN_EGRESS_IFACE", "eth7")
    monkeypatch.setenv("OVPN_TUNNEL_IFACE", "tun7")

    stub = _StubPrivilegedNetworkService()
    service = OpenVPNService(privileged_network=stub)

    service.setup_network_state()
    service.teardown_network_state()

    assert stub.calls[0][0] == "setup"
    assert stub.calls[0][1]["protocol"] == "openvpn"
    assert stub.calls[0][1]["source_cidr"] == "10.44.0.0/24"
    assert stub.calls[0][1]["tunnel_iface"] == "tun7"
    assert stub.calls[0][1]["egress_iface"] == "eth7"
    assert stub.calls[1][0] == "teardown"
    assert stub.calls[1][1]["protocol"] == "openvpn"


def test_ikev2_service_delegates_cleanup_mark_to_privileged_wrapper(monkeypatch) -> None:
    monkeypatch.setenv("IKEV2_CIDR", "10.45.0.0/24")
    monkeypatch.setenv("IKEV2_EGRESS_IFACE", "eth5")
    monkeypatch.setenv("IKEV2_TUNNEL_IFACE", "ipsec5")
    monkeypatch.setenv("IKEV2_FWMARK", "12c")

    stub = _StubPrivilegedNetworkService()
    service = IKEv2Service(privileged_network=stub)

    service.setup_network_state()
    service.teardown_network_state()

    assert stub.calls[0][0] == "setup"
    assert stub.calls[0][1]["protocol"] == "ikev2"
    assert stub.calls[1][0] == "teardown"
    assert stub.calls[1][1]["cleanup_xfrm_mark"] == "0x12c"
