"""Unix-socket client for the privileged SecureWave netops daemon."""

from __future__ import annotations

import json
import socket
import uuid
from dataclasses import dataclass
from typing import Any, Optional


RPC_VERSION = "v1"


class PrivilegedNetopsError(RuntimeError):
    """Base class for netops daemon client errors."""


class PrivilegedNetopsUnavailableError(PrivilegedNetopsError):
    """Raised when the daemon cannot be reached."""


class PrivilegedNetopsProtocolError(PrivilegedNetopsError):
    """Raised when the daemon response is malformed."""


class PrivilegedNetopsRejectedError(PrivilegedNetopsError):
    """Raised when the daemon rejects a request."""

    def __init__(self, code: str, message: str, details: Optional[dict[str, Any]] = None):
        self.code = code
        self.message = message
        self.details = details or {}
        super().__init__(f"{code}: {message}")


@dataclass(frozen=True)
class HealthPingResult:
    status: str


class PrivilegedNetopsClient:
    """Small synchronous client for Unix-socket JSON RPC calls."""

    def __init__(self, *, socket_path: str, timeout_ms: int = 5000) -> None:
        self.socket_path = socket_path
        self.timeout_s = timeout_ms / 1000.0

    def health_ping(self) -> HealthPingResult:
        result = self._call("health.ping", {})
        status = str(result.get("status") or "")
        if not status:
            raise PrivilegedNetopsProtocolError("health.ping response missing status")
        return HealthPingResult(status=status)

    def setup_protocol_network(
        self,
        *,
        protocol: str,
        source_cidr: str,
        tunnel_iface: str,
        egress_iface: str,
    ) -> dict[str, Any]:
        return self._call(
            "net.setup_protocol",
            {
                "protocol": protocol,
                "source_cidr": source_cidr,
                "tunnel_iface": tunnel_iface,
                "egress_iface": egress_iface,
            },
        )

    def teardown_protocol_network(
        self,
        *,
        protocol: str,
        source_cidr: str,
        tunnel_iface: str,
        egress_iface: str,
        bring_link_down: bool = True,
        cleanup_xfrm_mark: Optional[str] = None,
    ) -> dict[str, Any]:
        payload: dict[str, Any] = {
            "protocol": protocol,
            "source_cidr": source_cidr,
            "tunnel_iface": tunnel_iface,
            "egress_iface": egress_iface,
            "bring_link_down": bring_link_down,
        }
        if cleanup_xfrm_mark:
            payload["cleanup_xfrm_mark"] = cleanup_xfrm_mark
        return self._call("net.teardown_protocol", payload)

    def _call(self, method: str, params: dict[str, Any]) -> dict[str, Any]:
        request_id = uuid.uuid4().hex
        payload = {
            "version": RPC_VERSION,
            "id": request_id,
            "method": method,
            "params": params,
        }
        raw_request = json.dumps(payload, separators=(",", ":")).encode("utf-8")

        try:
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as conn:
                conn.settimeout(self.timeout_s)
                conn.connect(self.socket_path)
                conn.sendall(raw_request)
                conn.shutdown(socket.SHUT_WR)

                chunks: list[bytes] = []
                while True:
                    chunk = conn.recv(65536)
                    if not chunk:
                        break
                    chunks.append(chunk)
        except FileNotFoundError as exc:
            raise PrivilegedNetopsUnavailableError(f"socket not found: {self.socket_path}") from exc
        except ConnectionRefusedError as exc:
            raise PrivilegedNetopsUnavailableError(f"socket refused: {self.socket_path}") from exc
        except socket.timeout as exc:
            raise PrivilegedNetopsUnavailableError("netops daemon request timed out") from exc
        except OSError as exc:
            raise PrivilegedNetopsUnavailableError(f"netops daemon unavailable: {exc}") from exc

        if not chunks:
            raise PrivilegedNetopsProtocolError("empty response from netops daemon")
        try:
            response = json.loads(b"".join(chunks).decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise PrivilegedNetopsProtocolError("invalid JSON response from netops daemon") from exc

        if response.get("version") != RPC_VERSION:
            raise PrivilegedNetopsProtocolError("protocol version mismatch")
        if response.get("id") != request_id:
            raise PrivilegedNetopsProtocolError("response id mismatch")

        if response.get("ok") is True:
            result = response.get("result")
            if isinstance(result, dict):
                return result
            raise PrivilegedNetopsProtocolError("response result must be an object")

        error = response.get("error")
        if not isinstance(error, dict):
            raise PrivilegedNetopsProtocolError("error response missing error body")
        raise PrivilegedNetopsRejectedError(
            str(error.get("code") or "unknown_error"),
            str(error.get("message") or "netops daemon rejected request"),
            error.get("details") if isinstance(error.get("details"), dict) else None,
        )
