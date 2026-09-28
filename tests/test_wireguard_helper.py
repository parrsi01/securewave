import base64
from pathlib import Path

import pytest

from services import wireguard_helper


def _public_key(fill_byte: int) -> str:
    return base64.b64encode(bytes([fill_byte]) * 32).decode("ascii")


class FakeWireGuard:
    def __init__(self, peers=None, *, fail_save=False, fail_set=False):
        self.server_public_key = _public_key(1)
        self.listen_port = 51820
        self.peers = {key: set(values) for key, values in (peers or {}).items()}
        self.fail_save = fail_save
        self.fail_set = fail_set
        self.calls = []

    def __call__(self, argv):
        self.calls.append(argv)
        if argv == (wireguard_helper.WG, "show", "wg0", "public-key"):
            return True, self.server_public_key
        if argv == (wireguard_helper.WG, "show", "wg0", "listen-port"):
            return True, str(self.listen_port)
        if argv == (wireguard_helper.WG, "show", "wg0", "allowed-ips"):
            return True, "\n".join(
                f"{key}\t{','.join(sorted(values)) or '[none]'}"
                for key, values in self.peers.items()
            )
        if argv[:4] == (wireguard_helper.WG, "set", "wg0", "peer"):
            if self.fail_set:
                return False, ""
            key = argv[4]
            if argv[-1] == "remove":
                self.peers.pop(key, None)
            else:
                self.peers[key] = {argv[-1]}
            return True, ""
        if argv == (wireguard_helper.WG_QUICK, "save", "wg0"):
            return not self.fail_save, ""
        return False, ""


def test_helper_inspects_only_public_wireguard_state():
    fake = FakeWireGuard(peers={_public_key(2): {"10.8.0.10/32"}})
    result = wireguard_helper.WireGuardController(fake).dispatch({"operation": "inspect"})

    assert result == {
        "ok": True,
        "server_public_key": _public_key(1),
        "listen_port": 51820,
        "peers": {_public_key(2): ["10.8.0.10/32"]},
    }
    assert "private_key" not in repr(result).lower()
    assert all(argv[0] in {wireguard_helper.WG, wireguard_helper.WG_QUICK} for argv in fake.calls)


@pytest.mark.parametrize(
    "public_key,address",
    [
        ("!" * 44, "10.8.0.10/32"),
        (base64.b64encode(bytes(32)).decode("ascii"), "10.8.0.10/32"),
        (_public_key(2), "10.8.0.9/32"),
        (_public_key(2), "10.8.1.10/32"),
        (_public_key(2), "10.8.0.10/24"),
        (_public_key(2), "fd00::10/128"),
        (_public_key(2), "10.8.0.10/32\n"),
    ],
)
def test_helper_rejects_invalid_public_key_or_client_address_without_commands(
    public_key, address
):
    fake = FakeWireGuard()
    controller = wireguard_helper.WireGuardController(fake)

    with pytest.raises(wireguard_helper.WireGuardHelperError):
        controller.ensure_peer(public_key, address)

    assert fake.calls == []


def test_helper_adds_and_verifies_exact_peer_on_fixed_interface():
    fake = FakeWireGuard()
    controller = wireguard_helper.WireGuardController(fake)
    public_key = _public_key(3)

    controller.ensure_peer(public_key, "10.8.0.11/32")

    assert fake.peers == {public_key: {"10.8.0.11/32"}}
    assert (
        wireguard_helper.WG,
        "set",
        "wg0",
        "peer",
        public_key,
        "allowed-ips",
        "10.8.0.11/32",
    ) in fake.calls
    assert (wireguard_helper.WG_QUICK, "save", "wg0") in fake.calls
    assert all("wg1" not in argv for argv in fake.calls)
    assert all("sudo" not in argv[0] and "ssh" not in argv[0] for argv in fake.calls)


@pytest.mark.parametrize(
    "existing",
    [
        {_public_key(4): {"10.8.0.0/24"}},
        {_public_key(3): {"10.8.0.13/32"}},
    ],
)
def test_helper_refuses_conflicting_existing_peer_or_address(existing):
    fake = FakeWireGuard(peers=existing)
    controller = wireguard_helper.WireGuardController(fake)

    with pytest.raises(wireguard_helper.WireGuardHelperError):
        controller.ensure_peer(_public_key(3), "10.8.0.12/32")

    assert not any(argv[:2] == (wireguard_helper.WG, "set") for argv in fake.calls)
    assert (wireguard_helper.WG_QUICK, "save", "wg0") not in fake.calls


def test_helper_removes_only_the_exact_managed_client_assignment():
    public_key = _public_key(5)
    fake = FakeWireGuard(peers={public_key: {"10.8.0.13/32"}})
    controller = wireguard_helper.WireGuardController(fake)

    controller.remove_peer(public_key, "10.8.0.13/32")

    assert public_key not in fake.peers
    assert (wireguard_helper.WG, "set", "wg0", "peer", public_key, "remove") in fake.calls
    assert (wireguard_helper.WG_QUICK, "save", "wg0") in fake.calls


def test_helper_refuses_to_remove_peer_with_another_address():
    public_key = _public_key(6)
    fake = FakeWireGuard(peers={public_key: {"10.8.0.14/32"}})
    controller = wireguard_helper.WireGuardController(fake)

    with pytest.raises(wireguard_helper.WireGuardHelperError):
        controller.remove_peer(public_key, "10.8.0.15/32")

    assert fake.peers == {public_key: {"10.8.0.14/32"}}
    assert not any(argv[:2] == (wireguard_helper.WG, "set") for argv in fake.calls)


def test_helper_rolls_back_runtime_peer_if_persistence_fails():
    fake = FakeWireGuard(fail_save=True)
    controller = wireguard_helper.WireGuardController(fake)
    public_key = _public_key(7)

    with pytest.raises(wireguard_helper.WireGuardHelperError, match="persistence"):
        controller.ensure_peer(public_key, "10.8.0.15/32")

    assert public_key not in fake.peers
    assert (wireguard_helper.WG, "set", "wg0", "peer", public_key, "remove") in fake.calls


def test_helper_restores_runtime_peer_if_removal_cannot_be_persisted():
    public_key = _public_key(9)
    fake = FakeWireGuard(peers={public_key: {"10.8.0.17/32"}}, fail_save=True)
    controller = wireguard_helper.WireGuardController(fake)

    with pytest.raises(wireguard_helper.WireGuardHelperError, match="persistence"):
        controller.remove_peer(public_key, "10.8.0.17/32")

    assert fake.peers == {public_key: {"10.8.0.17/32"}}


def test_default_runner_never_uses_a_shell(monkeypatch):
    recorded = {}

    class Result:
        returncode = 0
        stdout = "public output\n"

    def run(argv, **kwargs):
        recorded["argv"] = argv
        recorded.update(kwargs)
        return Result()

    monkeypatch.setattr(wireguard_helper.subprocess, "run", run)
    success, output = wireguard_helper._default_command_runner(
        (wireguard_helper.WG, "show", "wg0", "public-key")
    )

    assert success is True
    assert output == "public output"
    assert recorded["shell"] is False
    assert recorded["stdin"] is wireguard_helper.subprocess.DEVNULL
    assert recorded["stderr"] is wireguard_helper.subprocess.DEVNULL


def test_helper_rejects_arbitrary_operations_interfaces_and_extra_fields():
    fake = FakeWireGuard()
    controller = wireguard_helper.WireGuardController(fake)

    for request in (
        {"operation": "exec", "command": "id"},
        {"operation": "inspect", "interface": "wg1"},
        {
            "operation": "ensure_peer",
            "public_key": _public_key(8),
            "address": "10.8.0.16/32",
            "interface": "wg1",
        },
    ):
        with pytest.raises(wireguard_helper.WireGuardHelperError):
            controller.dispatch(request)

    assert fake.calls == []


def test_helper_denies_untrusted_unix_socket_peer_uid():
    assert wireguard_helper._peer_uid_allowed(1000, 1000)
    assert wireguard_helper._peer_uid_allowed(0, 1000)
    assert not wireguard_helper._peer_uid_allowed(1001, 1000)


def test_systemd_privilege_boundary_is_narrow_and_local():
    root = Path(__file__).resolve().parents[1]
    helper_unit = (root / "infrastructure/systemd/securewave-wg-helper.service").read_text()
    api_dropin = (
        root / "infrastructure/systemd/securewave-api.service.d/securewave-wg-helper.conf"
    ).read_text()

    assert "User=root" in helper_unit
    assert "Group=securewave-wg" in helper_unit
    assert "CapabilityBoundingSet=CAP_NET_ADMIN" in helper_unit
    assert "AmbientCapabilities=CAP_NET_ADMIN" in helper_unit
    assert "NoNewPrivileges=yes" in helper_unit
    assert "RestrictAddressFamilies=AF_UNIX AF_NETLINK" in helper_unit
    assert "ListenStream=" not in helper_unit
    assert api_dropin == "[Service]\nSupplementaryGroups=securewave-wg\n"


def test_helper_request_parser_handles_fragmented_data_and_rejects_duplicate_keys():
    class ChunkedConnection:
        def __init__(self, chunks):
            self.chunks = list(chunks)

        def recv(self, _size):
            return self.chunks.pop(0) if self.chunks else b""

    parsed = wireguard_helper._read_request(
        ChunkedConnection([b'{"operation":', b'"inspect"}\n'])
    )
    assert parsed == {"operation": "inspect"}

    with pytest.raises(wireguard_helper.WireGuardHelperError):
        wireguard_helper._read_request(
            ChunkedConnection([b'{"operation":"inspect","operation":"inspect"}\n'])
        )
