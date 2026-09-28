"""Narrow local privilege boundary for the production WireGuard interface."""

from __future__ import annotations

import base64
import binascii
import grp
import ipaddress
import json
import os
import pwd
import signal
import socket
import stat
import struct
import subprocess
from typing import Callable


INTERFACE = "wg0"
CLIENT_POOL = ipaddress.IPv4Network("10.8.0.0/24")
CLIENT_HOST_MIN = 10
CLIENT_HOST_MAX = 254
RUNTIME_DIRECTORY = "/run/securewave-wg-helper"
SOCKET_PATH = f"{RUNTIME_DIRECTORY}/helper.sock"
SOCKET_GROUP = "securewave-wg"
API_USER = "securewave"
MAX_REQUEST_BYTES = 1024
MAX_RESPONSE_BYTES = 65536
COMMAND_TIMEOUT_SECONDS = 5
WG = "/usr/bin/wg"
WG_QUICK = "/usr/bin/wg-quick"

CommandRunner = Callable[[tuple[str, ...]], tuple[bool, str]]


class WireGuardHelperError(RuntimeError):
    """A constrained WireGuard operation could not be safely completed."""


def is_wireguard_public_key(value: object) -> bool:
    if not isinstance(value, str):
        return False
    try:
        decoded = base64.b64decode(value, validate=True)
    except (binascii.Error, ValueError, UnicodeEncodeError):
        return False
    return (
        len(decoded) == 32
        and any(decoded)
        and base64.b64encode(decoded).decode("ascii") == value
    )


def validate_client_address(value: object) -> ipaddress.IPv4Network:
    if not isinstance(value, str):
        raise WireGuardHelperError("invalid client address")
    try:
        interface = ipaddress.ip_interface(value)
    except ValueError as exc:
        raise WireGuardHelperError("invalid client address") from exc
    if (
        interface.version != 4
        or interface.network.prefixlen != 32
        or str(interface) != value
        or interface.ip not in CLIENT_POOL
        or not CLIENT_HOST_MIN <= int(interface.ip) - int(CLIENT_POOL.network_address) <= CLIENT_HOST_MAX
    ):
        raise WireGuardHelperError("invalid client address")
    return interface.network


def parse_wireguard_allowed_ips(output: str) -> dict[str, list[str]]:
    """Parse wg's public-key/AllowedIPs output, failing closed on ambiguity."""
    peers: dict[str, list[str]] = {}
    for line in output.splitlines():
        columns = line.split(maxsplit=1)
        if len(columns) != 2:
            raise WireGuardHelperError("invalid WireGuard peer state")
        public_key, raw_allowed_ips = columns
        if not is_wireguard_public_key(public_key) or public_key in peers:
            raise WireGuardHelperError("invalid WireGuard peer state")
        networks: list[str] = []
        if raw_allowed_ips.strip() not in {"", "none", "[none]"}:
            try:
                parsed = [
                    ipaddress.ip_network(item.strip(), strict=False)
                    for item in raw_allowed_ips.split(",")
                ]
            except ValueError as exc:
                raise WireGuardHelperError("invalid WireGuard peer state") from exc
            if any(not item for item in raw_allowed_ips.split(",")) or len(parsed) != len(set(parsed)):
                raise WireGuardHelperError("invalid WireGuard peer state")
            networks = sorted(str(network) for network in parsed)
        peers[public_key] = networks
    return peers


def _default_command_runner(argv: tuple[str, ...]) -> tuple[bool, str]:
    try:
        result = subprocess.run(
            argv,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=COMMAND_TIMEOUT_SECONDS,
            check=False,
            shell=False,
            close_fds=True,
        )
    except (OSError, subprocess.SubprocessError):
        return False, ""
    return result.returncode == 0, result.stdout.strip()


def _state_has_conflicting_address(
    peers: dict[str, list[str]],
    public_key: str,
    client_network: ipaddress.IPv4Network,
) -> bool:
    for existing_key, prefixes in peers.items():
        if existing_key == public_key:
            try:
                return {ipaddress.ip_network(item, strict=False) for item in prefixes} != {
                    client_network
                }
            except ValueError:
                return True
        for prefix in prefixes:
            try:
                existing_network = ipaddress.ip_network(prefix, strict=False)
            except ValueError:
                return True
            if existing_network.version == 4 and existing_network.overlaps(client_network):
                return True
    return False


class WireGuardController:
    """Only inspect, ensure and remove validated peers on the fixed wg0 device."""

    def __init__(self, command_runner: CommandRunner = _default_command_runner):
        self._run = command_runner

    def inspect(self) -> dict[str, object]:
        success, public_key = self._run((WG, "show", INTERFACE, "public-key"))
        if not success or not is_wireguard_public_key(public_key):
            raise WireGuardHelperError("WireGuard interface is unavailable")
        success, raw_port = self._run((WG, "show", INTERFACE, "listen-port"))
        if not success or not raw_port.isdecimal():
            raise WireGuardHelperError("WireGuard interface is unavailable")
        port = int(raw_port)
        if not 1 <= port <= 65535:
            raise WireGuardHelperError("WireGuard interface is unavailable")
        success, raw_peers = self._run((WG, "show", INTERFACE, "allowed-ips"))
        if not success:
            raise WireGuardHelperError("WireGuard interface is unavailable")
        peers = parse_wireguard_allowed_ips(raw_peers)
        return {
            "server_public_key": public_key,
            "listen_port": port,
            "peers": peers,
        }

    def ensure_peer(self, public_key: str, address: str) -> None:
        if not is_wireguard_public_key(public_key):
            raise WireGuardHelperError("invalid public key")
        client_network = validate_client_address(address)
        state = self.inspect()
        peers = state["peers"]
        assert isinstance(peers, dict)
        if _state_has_conflicting_address(peers, public_key, client_network):
            raise WireGuardHelperError("peer or address assignment conflicts")

        added = public_key not in peers
        if added:
            success, _ = self._run(
                (
                    WG,
                    "set",
                    INTERFACE,
                    "peer",
                    public_key,
                    "allowed-ips",
                    str(client_network),
                )
            )
            if not success:
                raise WireGuardHelperError("peer could not be configured")

        try:
            verified = self.inspect()
            verified_peers = verified["peers"]
            if not isinstance(verified_peers, dict) or _state_has_conflicting_address(
                verified_peers, public_key, client_network
            ):
                raise WireGuardHelperError("peer assignment could not be verified")
            if set(verified_peers.get(public_key, [])) != {str(client_network)}:
                raise WireGuardHelperError("peer assignment could not be verified")
            if not self._save():
                raise WireGuardHelperError("peer persistence failed")
        except WireGuardHelperError:
            if added:
                self._remove_runtime_peer(public_key)
            raise

    def remove_peer(self, public_key: str, address: str) -> None:
        if not is_wireguard_public_key(public_key):
            raise WireGuardHelperError("invalid public key")
        client_network = validate_client_address(address)
        state = self.inspect()
        peers = state["peers"]
        assert isinstance(peers, dict)
        if public_key not in peers:
            return
        if set(peers[public_key]) != {str(client_network)}:
            raise WireGuardHelperError("peer assignment conflicts")
        if not self._remove_runtime_peer(public_key):
            raise WireGuardHelperError("peer removal failed")
        try:
            verified = self.inspect()
            verified_peers = verified["peers"]
            if not isinstance(verified_peers, dict) or public_key in verified_peers:
                raise WireGuardHelperError("peer removal could not be verified")
            if not self._save():
                raise WireGuardHelperError("peer persistence failed")
        except WireGuardHelperError:
            self._restore_runtime_peer(public_key, str(client_network))
            raise

    def dispatch(self, request: object) -> dict[str, object]:
        if not isinstance(request, dict) or not isinstance(request.get("operation"), str):
            raise WireGuardHelperError("invalid request")
        operation = request["operation"]
        if operation == "inspect" and set(request) == {"operation"}:
            return {"ok": True, **self.inspect()}
        if operation in {"ensure_peer", "remove_peer"} and set(request) == {
            "operation",
            "public_key",
            "address",
        }:
            public_key, address = request.get("public_key"), request.get("address")
            if not isinstance(public_key, str) or not isinstance(address, str):
                raise WireGuardHelperError("invalid request")
            if operation == "ensure_peer":
                self.ensure_peer(public_key, address)
                return {"ok": True, "status": "configured"}
            self.remove_peer(public_key, address)
            return {"ok": True, "status": "removed"}
        raise WireGuardHelperError("invalid request")

    def _save(self) -> bool:
        success, _ = self._run((WG_QUICK, "save", INTERFACE))
        return success

    def _remove_runtime_peer(self, public_key: str) -> bool:
        success, _ = self._run((WG, "set", INTERFACE, "peer", public_key, "remove"))
        return success

    def _restore_runtime_peer(self, public_key: str, address: str) -> None:
        success, _ = self._run(
            (WG, "set", INTERFACE, "peer", public_key, "allowed-ips", address)
        )
        if success:
            self._save()


def _peer_uid_allowed(uid: int, api_uid: int) -> bool:
    return uid in {0, api_uid}


def _read_request(connection: socket.socket) -> object:
    data = bytearray()
    while len(data) <= MAX_REQUEST_BYTES:
        chunk = connection.recv(min(4096, MAX_REQUEST_BYTES + 1 - len(data)))
        if not chunk:
            raise WireGuardHelperError("invalid request")
        newline = chunk.find(b"\n")
        if newline >= 0:
            if chunk[newline + 1 :] or len(data) + newline > MAX_REQUEST_BYTES:
                raise WireGuardHelperError("invalid request")
            try:
                return json.loads(
                    (bytes(data) + chunk[:newline]).decode("utf-8"),
                    object_pairs_hook=_unique_object,
                )
            except (UnicodeDecodeError, json.JSONDecodeError, ValueError) as exc:
                raise WireGuardHelperError("invalid request") from exc
        data.extend(chunk)
    raise WireGuardHelperError("invalid request")


def _unique_object(pairs: list[tuple[str, object]]) -> dict[str, object]:
    result: dict[str, object] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate JSON key")
        result[key] = value
    return result


def _handle_connection(
    connection: socket.socket,
    controller: WireGuardController,
    api_uid: int,
) -> None:
    response: dict[str, object]
    try:
        raw_credentials = connection.getsockopt(
            socket.SOL_SOCKET, socket.SO_PEERCRED, struct.calcsize("3i")
        )
        _, peer_uid, _ = struct.unpack("3i", raw_credentials)
        if not _peer_uid_allowed(peer_uid, api_uid):
            raise WireGuardHelperError("unauthorized local peer")
        response = controller.dispatch(_read_request(connection))
    except (OSError, WireGuardHelperError):
        response = {"ok": False, "error": "operation_failed"}
    try:
        encoded = json.dumps(response, separators=(",", ":")).encode("utf-8") + b"\n"
        if len(encoded) <= MAX_RESPONSE_BYTES:
            connection.sendall(encoded)
    except OSError:
        pass


def serve() -> None:
    group_id = grp.getgrnam(SOCKET_GROUP).gr_gid
    api_uid = pwd.getpwnam(API_USER).pw_uid
    runtime_stat = os.stat(RUNTIME_DIRECTORY, follow_symlinks=False)
    if (
        not stat.S_ISDIR(runtime_stat.st_mode)
        or runtime_stat.st_uid != 0
        or runtime_stat.st_gid != group_id
        or runtime_stat.st_mode & 0o007
        or runtime_stat.st_mode & 0o020
    ):
        raise RuntimeError("WireGuard helper runtime directory permissions are unsafe")

    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(SOCKET_PATH)
    os.chown(SOCKET_PATH, 0, group_id)
    os.chmod(SOCKET_PATH, 0o660)
    server.listen(16)
    server.settimeout(1.0)
    controller = WireGuardController()
    stopping = False

    def stop(_signum: int, _frame: object) -> None:
        nonlocal stopping
        stopping = True

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    try:
        while not stopping:
            try:
                connection, _ = server.accept()
            except socket.timeout:
                continue
            with connection:
                connection.settimeout(COMMAND_TIMEOUT_SECONDS)
                _handle_connection(connection, controller, api_uid)
    finally:
        server.close()
        try:
            os.unlink(SOCKET_PATH)
        except FileNotFoundError:
            pass


if __name__ == "__main__":
    serve()
