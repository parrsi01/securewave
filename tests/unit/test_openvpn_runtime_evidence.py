from datetime import datetime, timedelta

from models.vpn_server import VPNServer
from services.protocol_availability_service import ProtocolAvailabilityService


def _server(evidence):
    now = datetime.utcnow()
    return VPNServer(
        server_id="openvpn-evidence",
        location="Evidence City",
        country="Testland",
        country_code="TS",
        city="Evidence City",
        public_ip="203.0.113.130",
        endpoint="203.0.113.130:51820",
        wg_public_key="evidence-key",
        wg_private_key_encrypted="encrypted",
        supports_openvpn=True,
        openvpn_endpoint="203.0.113.130",
        openvpn_ca_cert_pem="-----BEGIN CERTIFICATE-----\nMIIB\n-----END CERTIFICATE-----",
        status="active",
        health_status="healthy",
        last_health_check=now,
        hcloud_server_state="running",
        max_connections=10,
        current_connections=0,
        protocol_runtime_evidence=evidence,
    )


def test_runtime_health_update_cannot_refresh_stale_openvpn_data_plane_proof():
    now = datetime.utcnow()
    stale = now - timedelta(minutes=10)
    server = _server(
        {
            "openvpn": {
                "healthy": True,
                "authenticated": True,
                "observed_at": stale.isoformat(),
                "data_plane_healthy": True,
                "data_plane_observed_at": stale.isoformat(),
            }
        }
    )
    ProtocolAvailabilityService.record_evidence(
        server, "openvpn", healthy=True, authenticated=True, observed_at=now
    )
    evidence = server.protocol_runtime_evidence["openvpn"]
    assert evidence["data_plane_observed_at"] == stale.isoformat()
    assert ProtocolAvailabilityService(now=now).evaluate(server, "openvpn").enabled is False
