"""Fail-closed protocol availability derived from recent runtime evidence."""

from __future__ import annotations

import os
import re
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from ipaddress import ip_address

from models.vpn_server import VPNServer


@dataclass(frozen=True)
class ProtocolReadiness:
    enabled: bool
    reason: str | None = None


class ProtocolAvailabilityService:
    """Keep endpoint metadata separate from evidence that the backend is usable."""

    _FAILURE_REASONS = frozenset({"probe_failed", "probe_exception"})
    _TRANSITIONS = frozenset(
        {"initial", "steady_healthy", "steady_failed", "failed", "recovered"}
    )

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
        try:
            max_connections = int(server.max_connections)
            current_connections = int(server.current_connections)
        except (TypeError, ValueError):
            return ProtocolReadiness(False, "Server capacity is not available.")
        if (
            max_connections <= 0
            or current_connections < 0
            or current_connections >= max_connections
        ):
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
            if not self._has_fresh_data_plane_evidence(server, protocol):
                return ProtocolReadiness(
                    False,
                    "OpenVPN data-plane evidence has not been recorded.",
                )
            if not self.configured_egress_evidence_secret():
                return ProtocolReadiness(
                    False,
                    "OpenVPN authenticated egress evidence is not configured.",
                )
            return ProtocolReadiness(True)
        if protocol == "ikev2":
            if not self._has_usable_ikev2_metadata(server):
                return ProtocolReadiness(False, "IKEv2 endpoint metadata is incomplete.")
            # IKEv2 must never inherit the historic provider-state default.
            # Missing state is not evidence that the host is running.
            if (server.hcloud_server_state or "").strip().lower() != "running":
                return ProtocolReadiness(False, "Server runtime is not running.")
            if not self._has_fresh_protocol_evidence(server, protocol):
                return ProtocolReadiness(
                    False,
                    "IKEv2 protocol-specific runtime evidence has not been recorded.",
                )
            if not self._has_fresh_data_plane_evidence(server, protocol):
                return ProtocolReadiness(
                    False,
                    "IKEv2 data-plane evidence has not been recorded.",
                )
            if not self.configured_egress_evidence_secret():
                return ProtocolReadiness(
                    False,
                    "IKEv2 authenticated egress evidence is not configured.",
                )
            return ProtocolReadiness(True)
        return ProtocolReadiness(False, "Protocol is not release-ready.")

    def supports(self, server: VPNServer, protocol: str) -> bool:
        return self.evaluate(server, protocol).enabled

    @staticmethod
    def configured_egress_evidence_secret() -> str | None:
        """Return the secret used to redact authenticated egress observations.

        Credentialed Linux protocols are unavailable unless the API can verify
        a post-connect source without returning an address to the client.
        Tests use a fixed non-production value; development and production
        must configure one.
        """
        if os.getenv("TESTING", "").lower() == "true":
            return "securewave-openvpn-egress-test-only-secret"
        value = os.getenv("SECUREWAVE_EGRESS_EVIDENCE_SECRET", "")
        if len(value) < 32 or any(not character.isprintable() for character in value):
            return None
        return value

    @staticmethod
    def record_evidence(
        server: VPNServer,
        protocol: str,
        *,
        healthy: bool,
        observed_at: datetime | None = None,
        data_plane_healthy: bool | None = None,
        failure_reason: str | None = None,
        authenticated: bool | None = None,
    ) -> str:
        """Attach compact, fail-closed probe state without persisting output.

        The transition is deliberately a small fixed vocabulary. Probe output,
        credentials, endpoints, and exception messages never become runtime
        evidence or alert data.
        """
        observed = ProtocolAvailabilityService._naive_utc(
            observed_at or datetime.utcnow()
        )
        evidence = dict(server.protocol_runtime_evidence or {})
        previous = evidence.get(protocol)
        previous_healthy = (
            previous.get("healthy") if isinstance(previous, dict) else None
        )
        if previous_healthy is None:
            transition = "initial"
        elif bool(healthy) and previous_healthy is False:
            transition = "recovered"
        elif not healthy and previous_healthy is True:
            transition = "failed"
        elif healthy:
            transition = "steady_healthy"
        else:
            transition = "steady_failed"
        protocol_evidence = {
            "healthy": bool(healthy),
            "observed_at": observed.isoformat(),
            "transition": transition,
        }
        if data_plane_healthy is not None:
            protocol_evidence["data_plane_healthy"] = bool(data_plane_healthy)
            protocol_evidence["data_plane_observed_at"] = observed.isoformat()
        elif isinstance(previous, dict):
            # Runtime health checks occur more frequently than independent
            # data-plane probes. Retain the original timestamp so old proof
            # naturally expires instead of being accidentally refreshed.
            for key in ("data_plane_healthy", "data_plane_observed_at"):
                if key in previous:
                    protocol_evidence[key] = previous[key]
        if authenticated is not None:
            protocol_evidence["authenticated"] = bool(authenticated)
        if not healthy:
            reason = failure_reason if failure_reason in ProtocolAvailabilityService._FAILURE_REASONS else "probe_failed"
            protocol_evidence["failure_reason"] = reason
        evidence[protocol] = protocol_evidence
        server.protocol_runtime_evidence = evidence
        return transition

    def _has_fresh_protocol_evidence(self, server: VPNServer, protocol: str) -> bool:
        evidence = (server.protocol_runtime_evidence or {}).get(protocol)
        if (
            not isinstance(evidence, dict)
            or evidence.get("healthy") is not True
            # Missing authentication is stale legacy metadata, not evidence
            # that this authenticated control-plane probe reached a usable
            # server runtime.
            or evidence.get("authenticated") is not True
        ):
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

    def _has_fresh_data_plane_evidence(self, server: VPNServer, protocol: str) -> bool:
        evidence = (server.protocol_runtime_evidence or {}).get(protocol)
        if (
            not isinstance(evidence, dict)
            or evidence.get("authenticated") is not True
            or evidence.get("data_plane_healthy") is not True
        ):
            return False
        observed_at = evidence.get("data_plane_observed_at") or evidence.get("observed_at")
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
    def _has_usable_ikev2_metadata(server: VPNServer) -> bool:
        if not server.supports_ikev2:
            return False

        endpoint = (server.endpoint or "").strip() or (server.public_ip or "").strip()
        remote_id = (server.ikev2_remote_id or server.public_ip or "").strip()
        ca_cert = (server.ikev2_ca_cert_pem or "").strip()
        if not ProtocolAvailabilityService._has_usable_endpoint(endpoint) or not remote_id:
            return False
        try:
            ip_address((server.public_ip or "").strip())
        except ValueError:
            return False
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._:@-]{0,252}", remote_id):
            return False
        if ca_cert.count("-----BEGIN CERTIFICATE-----") != 1:
            return False
        if ca_cert.count("-----END CERTIFICATE-----") != 1:
            return False
        if "PRIVATE KEY" in ca_cert or any(
            not character.isprintable() and character not in "\n\r\t"
            for character in ca_cert
        ):
            return False
        return True

    @staticmethod
    def _has_usable_endpoint(value: str) -> bool:
        if not value or any(character.isspace() for character in value):
            return False
        if value.startswith("["):
            closing_bracket = value.find("]")
            if closing_bracket <= 1:
                return False
            try:
                if ip_address(value[1:closing_bracket]).version != 6:
                    return False
            except ValueError:
                return False
            suffix = value[closing_bracket + 1:]
            if not suffix:
                return True
            if not suffix.startswith(":"):
                return False
            port = suffix[1:]
            return port.isdigit() and 1 <= int(port) <= 65535
        if value.count(":") == 1:
            host, port = value.rsplit(":", 1)
            return (
                ProtocolAvailabilityService._has_usable_host(host)
                and port.isdigit()
                and 1 <= int(port) <= 65535
            )
        if value.count(":") > 1:
            try:
                return ip_address(value).version == 6
            except ValueError:
                return False
        return ProtocolAvailabilityService._has_usable_host(value)

    @staticmethod
    def _has_usable_host(value: str) -> bool:
        try:
            ip_address(value)
            return True
        except ValueError:
            pass

        hostname = value.rstrip(".")
        if not hostname or len(hostname) > 253:
            return False
        return all(
            re.fullmatch(r"(?!-)[A-Za-z0-9-]{1,63}(?<!-)", label) is not None
            for label in hostname.split(".")
        )

    @staticmethod
    def _naive_utc(value: datetime) -> datetime:
        if value.tzinfo is None:
            return value
        return value.astimezone(timezone.utc).replace(tzinfo=None)
