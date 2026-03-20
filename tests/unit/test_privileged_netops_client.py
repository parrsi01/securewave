from __future__ import annotations

import json
import socket
import threading
import time
from pathlib import Path

import pytest

from services.privileged_netops_client import (
    PrivilegedNetopsClient,
    PrivilegedNetopsProtocolError,
    PrivilegedNetopsRejectedError,
    PrivilegedNetopsUnavailableError,
)


def _serve_once(socket_path: Path, handler, *, delay_s: float = 0.0) -> threading.Thread:
    ready = threading.Event()

    def _run() -> None:
        if socket_path.exists():
            socket_path.unlink()
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as server:
            server.bind(str(socket_path))
            server.listen(1)
            ready.set()
            conn, _ = server.accept()
            with conn:
                chunks: list[bytes] = []
                while True:
                    chunk = conn.recv(65536)
                    if not chunk:
                        break
                    chunks.append(chunk)
                request = json.loads(b"".join(chunks).decode("utf-8"))
                if delay_s:
                    time.sleep(delay_s)
                response = handler(request)
                try:
                    conn.sendall(json.dumps(response).encode("utf-8"))
                except BrokenPipeError:
                    pass
        if socket_path.exists():
            socket_path.unlink()

    thread = threading.Thread(target=_run, daemon=True)
    thread.start()
    if not ready.wait(timeout=2.0):
        raise TimeoutError("test server did not start listening")
    return thread


def test_health_ping_round_trip(tmp_path: Path) -> None:
    socket_path = tmp_path / "netops.sock"

    def _handler(request: dict) -> dict:
        assert request["method"] == "health.ping"
        return {
            "version": "v1",
            "id": request["id"],
            "ok": True,
            "result": {"status": "ok"},
        }

    server = _serve_once(socket_path, _handler)
    client = PrivilegedNetopsClient(socket_path=str(socket_path), timeout_ms=500)

    result = client.health_ping()

    server.join(timeout=1.0)
    assert result.status == "ok"


def test_call_raises_rejected_error(tmp_path: Path) -> None:
    socket_path = tmp_path / "netops.sock"

    def _handler(request: dict) -> dict:
        return {
            "version": "v1",
            "id": request["id"],
            "ok": False,
            "error": {"code": "operation_failed", "message": "denied"},
        }

    server = _serve_once(socket_path, _handler)
    client = PrivilegedNetopsClient(socket_path=str(socket_path), timeout_ms=500)

    with pytest.raises(PrivilegedNetopsRejectedError, match="operation_failed"):
        client.setup_protocol_network(
            protocol="wireguard",
            source_cidr="10.8.0.0/24",
            tunnel_iface="wg0",
            egress_iface="eth0",
        )

    server.join(timeout=1.0)


def test_call_raises_unavailable_when_socket_missing(tmp_path: Path) -> None:
    client = PrivilegedNetopsClient(socket_path=str(tmp_path / "missing.sock"), timeout_ms=200)

    with pytest.raises(PrivilegedNetopsUnavailableError):
        client.health_ping()


def test_call_raises_protocol_error_on_bad_id(tmp_path: Path) -> None:
    socket_path = tmp_path / "netops.sock"

    def _handler(_request: dict) -> dict:
        return {
            "version": "v1",
            "id": "wrong-id",
            "ok": True,
            "result": {"status": "ok"},
        }

    server = _serve_once(socket_path, _handler)
    client = PrivilegedNetopsClient(socket_path=str(socket_path), timeout_ms=500)

    with pytest.raises(PrivilegedNetopsProtocolError, match="response id mismatch"):
        client.health_ping()

    server.join(timeout=1.0)


def test_call_raises_unavailable_on_timeout(tmp_path: Path) -> None:
    socket_path = tmp_path / "netops.sock"

    def _handler(request: dict) -> dict:
        return {
            "version": "v1",
            "id": request["id"],
            "ok": True,
            "result": {"status": "ok"},
        }

    server = _serve_once(socket_path, _handler, delay_s=0.4)
    client = PrivilegedNetopsClient(socket_path=str(socket_path), timeout_ms=50)

    with pytest.raises(PrivilegedNetopsUnavailableError, match="timed out"):
        client.health_ping()

    server.join(timeout=1.0)
