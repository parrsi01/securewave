"""Boundary wrapper for privileged network operations."""

from __future__ import annotations

from collections.abc import Callable
from typing import Optional

from config.settings import Settings, get_settings
from services.privileged_netops_client import (
    PrivilegedNetopsClient,
    PrivilegedNetopsError,
    PrivilegedNetopsUnavailableError,
)


LegacyCallback = Callable[[], None]


class PrivilegedNetworkService:
    """Calls the Go daemon when enabled, with an explicit legacy fallback."""

    def __init__(
        self,
        *,
        settings: Optional[Settings] = None,
        client: Optional[PrivilegedNetopsClient] = None,
    ) -> None:
        self.settings = settings or get_settings()
        self._client = client

    @property
    def client(self) -> Optional[PrivilegedNetopsClient]:
        if not self.settings.privileged_netops_enabled:
            return None
        if self._client is None:
            self._client = PrivilegedNetopsClient(
                socket_path=self.settings.privileged_netops_socket_path,
                timeout_ms=self.settings.privileged_netops_timeout_ms,
            )
        return self._client

    def health_ping(self) -> str:
        client = self.client
        if client is None:
            raise PrivilegedNetopsUnavailableError("privileged netops daemon is disabled")
        return client.health_ping().status

    def setup_protocol(
        self,
        *,
        protocol: str,
        source_cidr: str,
        tunnel_iface: str,
        egress_iface: str,
        legacy_fallback: Optional[LegacyCallback] = None,
    ) -> None:
        client = self.client
        if client is not None:
            client.setup_protocol_network(
                protocol=protocol,
                source_cidr=source_cidr,
                tunnel_iface=tunnel_iface,
                egress_iface=egress_iface,
            )
            return
        self._run_legacy_or_raise(legacy_fallback, operation=f"{protocol} setup")

    def teardown_protocol(
        self,
        *,
        protocol: str,
        source_cidr: str,
        tunnel_iface: str,
        egress_iface: str,
        bring_link_down: bool = True,
        cleanup_xfrm_mark: Optional[str] = None,
        legacy_fallback: Optional[LegacyCallback] = None,
    ) -> None:
        client = self.client
        if client is not None:
            client.teardown_protocol_network(
                protocol=protocol,
                source_cidr=source_cidr,
                tunnel_iface=tunnel_iface,
                egress_iface=egress_iface,
                bring_link_down=bring_link_down,
                cleanup_xfrm_mark=cleanup_xfrm_mark,
            )
            return
        self._run_legacy_or_raise(legacy_fallback, operation=f"{protocol} teardown")

    def _run_legacy_or_raise(
        self,
        legacy_fallback: Optional[LegacyCallback],
        *,
        operation: str,
    ) -> None:
        if legacy_fallback is not None and not self.settings.privileged_netops_required:
            legacy_fallback()
            return
        if self.settings.privileged_netops_enabled:
            raise PrivilegedNetopsUnavailableError(f"privileged netops daemon unavailable for {operation}")
        raise PrivilegedNetopsError(
            f"privileged netops daemon is disabled for {operation}; "
            "enable SECUREWAVE_NETOPSD_ENABLED or provide a migration fallback"
        )
