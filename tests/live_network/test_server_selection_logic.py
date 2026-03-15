"""CI-safe unit tests for server selection validation logic.

No tunnel, API, or network access required.
"""

from __future__ import annotations

from unittest.mock import patch

from dev_tools.sandbox.live_validation.server_selection_test import (
    ServerLatency,
    ServerSelectionReport,
    evaluate_selection,
    measure_latency,
    rank_servers_by_latency,
)
from dev_tools.sandbox.live_validation.common import CommandResult


class TestMeasureLatency:
    @patch("dev_tools.sandbox.live_validation.server_selection_test.run_command")
    def test_parses_ping_output(self, mock_run):
        mock_run.return_value = CommandResult(
            "ping -c 3 -W 2 1.2.3.4", 0,
            "PING 1.2.3.4 (1.2.3.4) 56(84) bytes of data.\n"
            "64 bytes from 1.2.3.4: icmp_seq=1 ttl=64 time=12.3 ms\n"
            "64 bytes from 1.2.3.4: icmp_seq=2 ttl=64 time=11.8 ms\n"
            "64 bytes from 1.2.3.4: icmp_seq=3 ttl=64 time=13.1 ms\n"
            "\n"
            "--- 1.2.3.4 ping statistics ---\n"
            "3 packets transmitted, 3 received, 0% packet loss, time 2003ms\n"
            "rtt min/avg/max/mdev = 11.800/12.400/13.100/0.535 ms\n",
            "", 3000.0,
        )
        ok, avg = measure_latency("1.2.3.4")
        assert ok is True
        assert avg == 12.4

    @patch("dev_tools.sandbox.live_validation.server_selection_test.run_command")
    def test_failure_returns_none(self, mock_run):
        mock_run.return_value = CommandResult("ping", 1, "", "timeout", 5000.0)
        ok, avg = measure_latency("unreachable.host")
        assert ok is False
        assert avg is None


class TestRankServersByLatency:
    @patch("dev_tools.sandbox.live_validation.server_selection_test.measure_latency")
    def test_ranks_by_latency(self, mock_lat):
        mock_lat.side_effect = [
            (True, 50.0),   # server-a
            (True, 20.0),   # server-b — lowest
            (True, 100.0),  # server-c
        ]
        servers = [
            {"id": "a", "name": "Server A", "ip_address": "1.1.1.1"},
            {"id": "b", "name": "Server B", "ip_address": "2.2.2.2"},
            {"id": "c", "name": "Server C", "ip_address": "3.3.3.3"},
        ]
        ranked = rank_servers_by_latency(servers)
        assert len(ranked) == 3
        assert ranked[0].server_id == "b"
        assert ranked[0].latency_ms == 20.0
        assert ranked[1].server_id == "a"
        assert ranked[2].server_id == "c"

    @patch("dev_tools.sandbox.live_validation.server_selection_test.measure_latency")
    def test_unreachable_sorted_last(self, mock_lat):
        mock_lat.side_effect = [
            (False, None),  # server-a unreachable
            (True, 30.0),   # server-b
        ]
        servers = [
            {"id": "a", "ip_address": "1.1.1.1"},
            {"id": "b", "ip_address": "2.2.2.2"},
        ]
        ranked = rank_servers_by_latency(servers)
        assert ranked[0].server_id == "b"
        assert ranked[1].server_id == "a"
        assert ranked[1].ping_success is False


class TestEvaluateSelection:
    def test_pass_when_best_selected(self):
        ranked = [
            ServerLatency(server_id="best", endpoint_host="1.1.1.1", latency_ms=10.0, ping_success=True),
            ServerLatency(server_id="second", endpoint_host="2.2.2.2", latency_ms=50.0, ping_success=True),
        ]
        ok, reason = evaluate_selection(ranked, "1.1.1.1:51820")
        assert ok is True
        assert "within_tolerance" in reason

    def test_pass_within_tolerance(self):
        ranked = [
            ServerLatency(server_id="best", endpoint_host="1.1.1.1", latency_ms=10.0, ping_success=True),
            ServerLatency(server_id="second", endpoint_host="2.2.2.2", latency_ms=25.0, ping_success=True),
        ]
        # Second server selected but within 20ms tolerance.
        ok, reason = evaluate_selection(ranked, "2.2.2.2:51820", tolerance_ms=20.0)
        assert ok is True

    def test_fail_outside_tolerance(self):
        ranked = [
            ServerLatency(server_id="best", endpoint_host="1.1.1.1", latency_ms=10.0, ping_success=True),
            ServerLatency(server_id="slow", endpoint_host="3.3.3.3", latency_ms=80.0, ping_success=True),
        ]
        ok, reason = evaluate_selection(ranked, "3.3.3.3:51820", tolerance_ms=20.0)
        assert ok is False
        assert "suboptimal" in reason

    def test_fail_when_not_in_list(self):
        ranked = [
            ServerLatency(server_id="a", endpoint_host="1.1.1.1", latency_ms=10.0, ping_success=True),
        ]
        ok, reason = evaluate_selection(ranked, "9.9.9.9:51820")
        assert ok is False
        assert "not_in_server_list" in reason

    def test_empty_ranking(self):
        ok, reason = evaluate_selection([], "1.1.1.1:51820")
        assert ok is False
        assert "no_servers_ranked" in reason

    def test_no_latency_for_best_is_pass(self):
        ranked = [
            ServerLatency(server_id="a", endpoint_host="1.1.1.1", latency_ms=None, ping_success=False),
        ]
        ok, reason = evaluate_selection(ranked, "1.1.1.1:51820")
        assert ok is True


class TestServerSelectionReport:
    def test_to_dict(self):
        r = ServerSelectionReport(verdict="PASS", servers_fetched=3)
        d = r.to_dict()
        assert d["verdict"] == "PASS"
        assert d["servers_fetched"] == 3
        assert "server_latencies" in d

    def test_defaults(self):
        r = ServerSelectionReport()
        assert r.verdict == "UNTESTED"
        assert r.tolerance_ms == 20.0
