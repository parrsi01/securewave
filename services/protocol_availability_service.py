"""Fail-closed protocol availability derived from recent runtime evidence."""

from __future__ import annotations

import os
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

from models.vpn_server import VPNServer


@dataclass(frozen=True)
class ProtocolReadiness:
    enabled: bool
    reason: str | None = None


class ProtocolAvailabilityService:
    """Keep endpoint metadata separate from evidence that the backend is usable."""

    def __init__(self, *, now: datetime | None = None):
        self.now = self._naive_utc(now or datetime.utcnow())
        try:
            ttl_seconds = int(os.getenv("SECUREWAVE_PROTOCOL_EVIDENCE_TTL_SECONDS", "300"))
        except ValueError:
            ttl_seconds = 300
        self.evidence_ttl = timedelta(seconds=max(30, min(ttl_seconds, 3600)))

    def evaluate(self, server: VPNServer, protocol: str) -> ProtocolReadiness:
        if server.status not in {"active", "demo"}:
            return ProtocolReadiness(False, "Server is not active.")
        if server.health_status not in {"healthy", "degraded"}:
            return ProtocolReadiness(False, "No healthy runtime evidence is available.")
        if not server.last_health_check:
            return ProtocolReadiness(False, "Runtime evidence has not been recorded.")
        health_age = self.now - self._naive_utc(server.last_health_check)
        if health_age < timedelta(0):
            return ProtocolReadiness(False, "Runtime evidence timestamp is in the future.")
        if health_age > self.evidence_ttl:
            return ProtocolReadiness(False, "Runtime evidence is stale.")
        if server.max_connections <= 0 or server.current_connections >= server.max_connections:
            return ProtocolReadiness(False, "Server has no available capacity.")
        provider_state = (server.hcloud_server_state or "running").lower()
        if provider_state != "running":
            return ProtocolReadiness(False, "Server runtime is not running.")

        if protocol == "wireguard":
            if not (server.supports_wireguard and server.endpoint and server.wg_public_key):
                return ProtocolReadiness(False, "WireGuard endpoint metadata is incomplete.")
            if not self._has_fresh_protocol_evidence(server, protocol):
                return ProtocolReadiness(
                    False,
                    "WireGuard protocol-specific runtime evidence has not been recorded.",
                )
            return ProtocolReadiness(True)
        if protocol == "openvpn":
            if not (
                server.supports_openvpn
                and (server.openvpn_endpoint or server.public_ip)
                and server.openvpn_ca_cert_pem
            ):
                return ProtocolReadiness(False, "OpenVPN endpoint metadata is incomplete.")
            if not self._has_fresh_protocol_evidence(server, protocol):
                return ProtocolReadiness(
                    False,
                    "OpenVPN protocol-specific runtime evidence has not been recorded.",
                )
            return ProtocolReadiness(True)
        # IKEv2 is intentionally not a public release protocol until a
        # protocol-specific runtime verifier records evidence for it.
        return ProtocolReadiness(False, "Protocol is not release-ready.")

    def supports(self, server: VPNServer, protocol: str) -> bool:
        return self.evaluate(server, protocol).enabled

    @staticmethod
    def record_evidence(
        server: VPNServer,
        protocol: str,
        *,
        healthy: bool,
        observed_at: datetime | None = None,
    ) -> None:
        """Attach a compact probe result without persisting probe output."""
        observed = ProtocolAvailabilityService._naive_utc(
            observed_at or datetime.utcnow()
        )
        evidence = dict(server.protocol_runtime_evidence or {})
        evidence[protocol] = {
            "healthy": bool(healthy),
            "observed_at": observed.isoformat(),
        }
        server.protocol_runtime_evidence = evidence

    def _has_fresh_protocol_evidence(self, server: VPNServer, protocol: str) -> bool:
        evidence = (server.protocol_runtime_evidence or {}).get(protocol)
        if not isinstance(evidence, dict) or evidence.get("healthy") is not True:
            return False
        observed_at = evidence.get("observed_at")
        if not isinstance(observed_at, str):
            return False
        try:
            observed = self._naive_utc(
                datetime.fromisoformat(observed_at.replace("Z", "+00:00"))
            )
        except ValueError:
            return False
        age = self.now - observed
        return timedelta(0) <= age <= self.evidence_ttl

    @staticmethod
    def _naive_utc(value: datetime) -> datetime:
        if value.tzinfo is None:
            return value
        return value.astimezone(timezone.utc).replace(tzinfo=None)
