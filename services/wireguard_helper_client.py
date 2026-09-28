"""Async FastAPI client for the local, root-owned WireGuard helper socket."""

from __future__ import annotations

import asyncio
import json
import socket


SOCKET_PATH = "/run/securewave-wg-helper/helper.sock"
SOCKET_TIMEOUT_SECONDS = 5
MAX_RESPONSE_BYTES = 65536


class WireGuardHelperError(RuntimeError):
    """The local WireGuard helper is unavailable or rejected an operation."""


def _request_sync(payload: dict[str, str]) -> dict[str, object]:
    encoded = json.dumps(payload, separators=(",", ":")).encode("utf-8") + b"\n"
    response = bytearray()
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
            client.settimeout(SOCKET_TIMEOUT_SECONDS)
            client.connect(SOCKET_PATH)
            client.sendall(encoded)
            while len(response) <= MAX_RESPONSE_BYTES:
                chunk = client.recv(min(4096, MAX_RESPONSE_BYTES + 1 - len(response)))
                if not chunk:
                    break
                newline = chunk.find(b"\n")
                if newline >= 0:
                    if chunk[newline + 1 :] or len(response) + newline > MAX_RESPONSE_BYTES:
                        raise WireGuardHelperError("invalid helper response")
                    response.extend(chunk[:newline])
                    break
                response.extend(chunk)
    except (OSError, TimeoutError) as exc:
        raise WireGuardHelperError("local WireGuard helper unavailable") from exc
    if not response or len(response) > MAX_RESPONSE_BYTES:
        raise WireGuardHelperError("invalid helper response")
    try:
        result = json.loads(response.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise WireGuardHelperError("invalid helper response") from exc
    if not isinstance(result, dict) or result.get("ok") is not True:
        raise WireGuardHelperError("WireGuard helper rejected the operation")
    return result


async def _request(payload: dict[str, str]) -> dict[str, object]:
    return await asyncio.to_thread(_request_sync, payload)


async def inspect_state() -> dict[str, object]:
    result = await _request({"operation": "inspect"})
    if (
        not isinstance(result.get("server_public_key"), str)
        or type(result.get("listen_port")) is not int
        or not isinstance(result.get("peers"), dict)
    ):
        raise WireGuardHelperError("invalid helper state")
    return result


async def ensure_peer(public_key: str, address: str) -> None:
    result = await _request(
        {"operation": "ensure_peer", "public_key": public_key, "address": address}
    )
    if result.get("status") != "configured":
        raise WireGuardHelperError("peer configuration was not confirmed")


async def remove_peer(public_key: str, address: str) -> None:
    result = await _request(
        {"operation": "remove_peer", "public_key": public_key, "address": address}
    )
    if result.get("status") != "removed":
        raise WireGuardHelperError("peer removal was not confirmed")
