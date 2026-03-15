"""
Unit tests for VPNHealthMonitor — port check, offline transitions, probe logic.
"""
import socket
from datetime import datetime
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from models.vpn_server import VPNServer
from services.vpn_health_monitor import (
    VPNHealthMonitor,
    _udp_port_probe,
    OFFLINE_FAILURE_THRESHOLD,
)


# ---------------------------------------------------------------------------
# _apply_health_transition
# ---------------------------------------------------------------------------


class TestHealthTransitions:
    """Test server health state machine transitions."""

    @staticmethod
    def _make_server(**overrides) -> VPNServer:
        defaults = dict(
            server_id="test-srv-1",
            location="Test",
            country="Testland",
            country_code="TT",
            city="Testville",
            hcloud_location="fsn1",
            public_ip="10.0.0.1",
            endpoint="10.0.0.1:51820",
            wg_public_key="key==",
            wg_private_key_encrypted="enc",
            status="active",
            health_status="healthy",
            hcloud_server_state="running",
            max_connections=100,
            current_connections=0,
            consecutive_health_failures=0,
        )
        defaults.update(overrides)
        return VPNServer(**defaults)

    def test_both_probes_pass_sets_healthy(self):
        monitor = VPNHealthMonitor()
        server = self._make_server(health_status="degraded", consecutive_health_failures=2)
        monitor._apply_health_transition(server, ping_ok=True, port_ok=True)
        assert server.health_status == "healthy"
        assert server.consecutive_health_failures == 0

    def test_ping_only_sets_degraded(self):
        monitor = VPNHealthMonitor()
        server = self._make_server()
        monitor._apply_health_transition(server, ping_ok=True, port_ok=False)
        assert server.health_status == "degraded"
        assert server.consecutive_health_failures == 1

    def test_port_only_sets_degraded(self):
        monitor = VPNHealthMonitor()
        server = self._make_server()
        monitor._apply_health_transition(server, ping_ok=False, port_ok=True)
        assert server.health_status == "degraded"
        assert server.consecutive_health_failures == 1

    def test_both_fail_sets_unhealthy(self):
        monitor = VPNHealthMonitor()
        server = self._make_server()
        monitor._apply_health_transition(server, ping_ok=False, port_ok=False)
        assert server.health_status == "unhealthy"
        assert server.consecutive_health_failures == 1

    def test_consecutive_failures_reach_offline(self):
        monitor = VPNHealthMonitor()
        server = self._make_server(
            consecutive_health_failures=OFFLINE_FAILURE_THRESHOLD - 1,
        )
        monitor._apply_health_transition(server, ping_ok=False, port_ok=False)
        assert server.health_status == "offline"
        assert server.consecutive_health_failures == OFFLINE_FAILURE_THRESHOLD

    def test_offline_stays_offline_on_continued_failure(self):
        monitor = VPNHealthMonitor()
        server = self._make_server(
            health_status="offline",
            consecutive_health_failures=OFFLINE_FAILURE_THRESHOLD + 3,
        )
        monitor._apply_health_transition(server, ping_ok=False, port_ok=False)
        assert server.health_status == "offline"

    def test_recovery_from_offline_to_healthy(self):
        monitor = VPNHealthMonitor()
        server = self._make_server(
            health_status="offline",
            consecutive_health_failures=10,
        )
        monitor._apply_health_transition(server, ping_ok=True, port_ok=True)
        assert server.health_status == "healthy"
        assert server.consecutive_health_failures == 0

    def test_recovery_from_unreachable_to_healthy(self):
        monitor = VPNHealthMonitor()
        server = self._make_server(
            health_status="unreachable",
            consecutive_health_failures=3,
        )
        monitor._apply_health_transition(server, ping_ok=True, port_ok=True)
        assert server.health_status == "healthy"
        assert server.consecutive_health_failures == 0

    def test_last_health_check_always_updated(self):
        monitor = VPNHealthMonitor()
        server = self._make_server(last_health_check=None)
        monitor._apply_health_transition(server, ping_ok=True, port_ok=True)
        assert server.last_health_check is not None


# ---------------------------------------------------------------------------
# _udp_port_probe (sync helper)
# ---------------------------------------------------------------------------


class TestUdpPortProbe:
    """Test the low-level UDP port probe used for WireGuard reachability."""

    def test_probe_returns_true_on_timeout(self):
        """Timeout (no ICMP error) means port is open (WireGuard drops silently)."""
        with patch("services.vpn_health_monitor.socket.socket") as mock_cls:
            mock_sock = MagicMock()
            mock_cls.return_value = mock_sock
            mock_sock.recvfrom.side_effect = socket.timeout
            assert _udp_port_probe("10.0.0.1", 51820, 1.0) is True
            mock_sock.close.assert_called_once()

    def test_probe_returns_false_on_connection_refused(self):
        """ECONNREFUSED means port is explicitly closed."""
        with patch("services.vpn_health_monitor.socket.socket") as mock_cls:
            mock_sock = MagicMock()
            mock_cls.return_value = mock_sock
            mock_sock.recvfrom.side_effect = OSError(111, "Connection refused")
            assert _udp_port_probe("10.0.0.1", 51820, 1.0) is False
            mock_sock.close.assert_called_once()

    def test_probe_returns_false_on_host_unreachable(self):
        """EHOSTUNREACH means host is down."""
        with patch("services.vpn_health_monitor.socket.socket") as mock_cls:
            mock_sock = MagicMock()
            mock_cls.return_value = mock_sock
            mock_sock.recvfrom.side_effect = OSError(113, "No route to host")
            assert _udp_port_probe("10.0.0.1", 51820, 1.0) is False

    def test_probe_returns_false_on_sendto_oserror(self):
        """OSError during sendto means network unreachable."""
        with patch("services.vpn_health_monitor.socket.socket") as mock_cls:
            mock_sock = MagicMock()
            mock_cls.return_value = mock_sock
            mock_sock.sendto.side_effect = OSError(101, "Network unreachable")
            assert _udp_port_probe("10.0.0.1", 51820, 1.0) is False

    def test_probe_returns_true_on_response(self):
        """Actual response from port means it's open."""
        with patch("services.vpn_health_monitor.socket.socket") as mock_cls:
            mock_sock = MagicMock()
            mock_cls.return_value = mock_sock
            mock_sock.recvfrom.return_value = (b"\x00", ("10.0.0.1", 51820))
            assert _udp_port_probe("10.0.0.1", 51820, 1.0) is True


# ---------------------------------------------------------------------------
# check_wg_port (async wrapper)
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_check_wg_port_returns_true_for_open_port():
    with patch("services.vpn_health_monitor._udp_port_probe", return_value=True):
        result = await VPNHealthMonitor.check_wg_port("10.0.0.1", 51820, timeout=1.0)
        assert result is True


@pytest.mark.asyncio
async def test_check_wg_port_returns_false_for_closed_port():
    with patch("services.vpn_health_monitor._udp_port_probe", return_value=False):
        result = await VPNHealthMonitor.check_wg_port("10.0.0.1", 51820, timeout=1.0)
        assert result is False


# ---------------------------------------------------------------------------
# probe_server
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_probe_server_includes_wg_port_open():
    monitor = VPNHealthMonitor()
    server = TestHealthTransitions._make_server()

    with patch.object(monitor, "ping_server", new_callable=AsyncMock, return_value=15.0), \
         patch.object(monitor, "check_wg_port", new_callable=AsyncMock, return_value=True), \
         patch.object(monitor, "_get_cpu_load", new_callable=AsyncMock, return_value=0.2):
        metrics = await monitor.probe_server(server)

    assert "wg_port_open" in metrics
    assert metrics["wg_port_open"] is True
    assert metrics["latency_ms"] == 15.0
    assert metrics["packet_loss"] == 0.0


@pytest.mark.asyncio
async def test_probe_server_unreachable_sets_high_packet_loss():
    monitor = VPNHealthMonitor()
    server = TestHealthTransitions._make_server()

    with patch.object(monitor, "ping_server", new_callable=AsyncMock, return_value=999.0), \
         patch.object(monitor, "check_wg_port", new_callable=AsyncMock, return_value=False), \
         patch.object(monitor, "_get_cpu_load", new_callable=AsyncMock, return_value=0.15):
        metrics = await monitor.probe_server(server)

    assert metrics["wg_port_open"] is False
    assert metrics["packet_loss"] == 1.0


# ---------------------------------------------------------------------------
# Offline filtering from GET /api/vpn/servers
# ---------------------------------------------------------------------------


def test_offline_servers_excluded_from_active_list(db):
    """Servers with health_status='offline' must not appear in get_active_servers."""
    from services.vpn_server_service import VPNServerService

    healthy = VPNServer(
        server_id="healthy-srv",
        location="Berlin",
        country="Germany",
        country_code="DE",
        city="Berlin",
        hcloud_location="fsn1",
        public_ip="10.0.0.1",
        endpoint="10.0.0.1:51820",
        wg_public_key="aGVhbHRoeS1rZXk=",
        wg_private_key_encrypted="enc",
        status="active",
        health_status="healthy",
        hcloud_server_state="running",
    )
    offline = VPNServer(
        server_id="offline-srv",
        location="Munich",
        country="Germany",
        country_code="DE",
        city="Munich",
        hcloud_location="fsn1",
        public_ip="10.0.0.2",
        endpoint="10.0.0.2:51820",
        wg_public_key="b2ZmbGluZS1rZXk=",
        wg_private_key_encrypted="enc",
        status="active",
        health_status="offline",
        hcloud_server_state="running",
    )
    db.add_all([healthy, offline])
    db.commit()

    result = VPNServerService.get_active_servers(db, "free")
    ids = [s.server_id for s in result]
    assert "healthy-srv" in ids
    assert "offline-srv" not in ids


def test_unhealthy_servers_excluded_from_active_list(db):
    """Servers with health_status='unhealthy' must not appear in get_active_servers."""
    from services.vpn_server_service import VPNServerService

    srv = VPNServer(
        server_id="unhealthy-srv",
        location="Hamburg",
        country="Germany",
        country_code="DE",
        city="Hamburg",
        hcloud_location="fsn1",
        public_ip="10.0.0.3",
        endpoint="10.0.0.3:51820",
        wg_public_key="dW5oZWFsdGh5LWtleQ==",
        wg_private_key_encrypted="enc",
        status="active",
        health_status="unhealthy",
        hcloud_server_state="running",
    )
    db.add(srv)
    db.commit()

    result = VPNServerService.get_active_servers(db, "free")
    ids = [s.server_id for s in result]
    assert "unhealthy-srv" not in ids
