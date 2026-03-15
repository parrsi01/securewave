"""CI-safe unit tests for DPI resistance detection logic.

No root, tunnel, tcpdump, tc, or network access required.
"""

from __future__ import annotations

from unittest.mock import patch

from dev_tools.sandbox.live_validation.common import CommandResult
from dev_tools.sandbox.live_validation.dpi_resistance_test import (
    DpiResistanceReport,
    FingerprintResult,
    PacketMeta,
    PortBlockResult,
    ThrottleResult,
    TrafficPatternResult,
    WG_HANDSHAKE_INITIATION_SIZE,
    WG_HANDSHAKE_RESPONSE_SIZE,
    WG_HANDSHAKE_COOKIE_SIZE,
    WG_KNOWN_SIZES,
    bucket_sizes,
    classify_wg_handshake_packets,
    count_bursts,
    parse_tcpdump_text,
    run_dpi_resistance_test,
    shannon_entropy,
    check_fingerprint,
    check_port_block,
    check_traffic_pattern,
    check_udp_throttle,
    variance,
)


# ---------------------------------------------------------------------------
# Shannon entropy
# ---------------------------------------------------------------------------


class TestShannonEntropy:
    def test_uniform_distribution_max_entropy(self):
        # All unique values -> high entropy.
        values = list(range(100))
        e = shannon_entropy(values)
        assert e > 0.9  # Near 1.0 for uniform.

    def test_single_value_zero_entropy(self):
        values = [42] * 100
        assert shannon_entropy(values) == 0.0

    def test_two_equal_groups(self):
        values = [1] * 50 + [2] * 50
        e = shannon_entropy(values)
        assert 0.1 < e < 0.5  # Moderate entropy.

    def test_empty(self):
        assert shannon_entropy([]) == 0.0


class TestVariance:
    def test_zero_for_constant(self):
        assert variance([5.0, 5.0, 5.0]) == 0.0

    def test_positive_for_spread(self):
        v = variance([1.0, 2.0, 3.0, 4.0, 5.0])
        assert v > 0
        assert abs(v - 2.0) < 0.01  # Population variance of 1..5.

    def test_single_value(self):
        assert variance([42.0]) == 0.0


class TestCountBursts:
    def test_no_bursts(self):
        assert count_bursts([100.0, 200.0, 150.0]) == 0

    def test_single_burst(self):
        assert count_bursts([1.0, 2.0, 3.0, 100.0, 200.0]) == 1

    def test_multiple_bursts(self):
        assert count_bursts([1.0, 2.0, 100.0, 1.0, 3.0, 200.0]) == 2

    def test_empty(self):
        assert count_bursts([]) == 0


class TestBucketSizes:
    def test_default_width(self):
        sizes = [148, 92, 64, 100, 200]
        bucketed = bucket_sizes(sizes)
        assert bucketed == [144, 80, 64, 96, 192]

    def test_custom_width(self):
        sizes = [10, 25, 50]
        bucketed = bucket_sizes(sizes, bucket_width=10)
        assert bucketed == [10, 20, 50]


# ---------------------------------------------------------------------------
# Packet parsing
# ---------------------------------------------------------------------------


class TestParseTcpdumpText:
    def test_parses_udp_lines(self):
        output = (
            "12:34:56.789012 IP 10.0.0.1.51820 > 10.0.0.2.12345: UDP, length 148\n"
            "12:34:56.800000 IP 10.0.0.2.12345 > 10.0.0.1.51820: UDP, length 92\n"
        )
        packets = parse_tcpdump_text(output)
        assert len(packets) == 2
        assert packets[0].src_ip == "10.0.0.1"
        assert packets[0].src_port == 51820
        assert packets[0].dst_ip == "10.0.0.2"
        assert packets[0].udp_payload_size == 148
        assert packets[1].udp_payload_size == 92

    def test_ignores_non_udp(self):
        output = "12:34:56.000000 IP 10.0.0.1.80 > 10.0.0.2.443: TCP, length 100\n"
        assert parse_tcpdump_text(output) == []

    def test_empty_input(self):
        assert parse_tcpdump_text("") == []

    def test_malformed_lines(self):
        output = "some random text\nno useful data here\n"
        assert parse_tcpdump_text(output) == []


class TestClassifyWgHandshakePackets:
    def test_classifies_known_sizes(self):
        packets = [
            PacketMeta(udp_payload_size=148),  # Initiation
            PacketMeta(udp_payload_size=92),   # Response
            PacketMeta(udp_payload_size=64),   # Cookie
            PacketMeta(udp_payload_size=128),  # Data
            PacketMeta(udp_payload_size=0),    # Other
        ]
        counts = classify_wg_handshake_packets(packets)
        assert counts["initiation"] == 1
        assert counts["response"] == 1
        assert counts["cookie"] == 1
        assert counts["data"] == 1
        assert counts["other"] == 1

    def test_empty(self):
        counts = classify_wg_handshake_packets([])
        assert all(v == 0 for v in counts.values())


# ---------------------------------------------------------------------------
# Simulation mode tests
# ---------------------------------------------------------------------------


class TestTestFingerprint:
    def test_simulation_mode(self):
        result = check_fingerprint("wg0", execute=False)
        assert result.verdict == "SIMULATED"

    @patch("dev_tools.sandbox.live_validation.dpi_resistance_test.run_command")
    def test_detectable_when_handshake_seen(self, mock_run):
        tcpdump_output = (
            "12:00:00.000 IP 1.2.3.4.51820 > 5.6.7.8.12345: UDP, length 148\n"
            "12:00:00.010 IP 5.6.7.8.12345 > 1.2.3.4.51820: UDP, length 92\n"
            "12:00:00.020 IP 1.2.3.4.51820 > 5.6.7.8.12345: UDP, length 148\n"
            "12:00:00.030 IP 5.6.7.8.12345 > 1.2.3.4.51820: UDP, length 92\n"
        )
        mock_run.return_value = CommandResult("tcpdump", 0, tcpdump_output, "", 5000.0)
        result = check_fingerprint("wg0", execute=True)
        assert result.verdict == "DETECTABLE"
        assert result.handshake_signature_match is True
        assert result.initiation_count == 2
        assert result.response_count == 2

    @patch("dev_tools.sandbox.live_validation.dpi_resistance_test.run_command")
    def test_pass_when_no_signature(self, mock_run):
        # All data packets, no handshake.
        tcpdump_output = (
            "12:00:00.000 IP 1.2.3.4.51820 > 5.6.7.8.12345: UDP, length 128\n"
            "12:00:00.010 IP 1.2.3.4.51820 > 5.6.7.8.12345: UDP, length 256\n"
            "12:00:00.020 IP 1.2.3.4.51820 > 5.6.7.8.12345: UDP, length 512\n"
        )
        mock_run.return_value = CommandResult("tcpdump", 0, tcpdump_output, "", 3000.0)
        result = check_fingerprint("wg0", execute=True)
        assert result.verdict == "PASS"
        assert result.handshake_signature_match is False


class TestTestPortBlock:
    def test_simulation_mode(self):
        result = check_port_block("wg0", execute=False)
        assert result.verdict == "SIMULATED"

    @patch("dev_tools.sandbox.live_validation.dpi_resistance_test.os")
    def test_skip_when_not_root(self, mock_os):
        mock_os.geteuid.return_value = 1000
        result = check_port_block("wg0", execute=True)
        assert result.verdict == "SKIP"


class TestTestUdpThrottle:
    def test_simulation_mode(self):
        result = check_udp_throttle("wg0", execute=False)
        assert result.verdict == "SIMULATED"
        assert "30%" in result.detail


class TestTestTrafficPattern:
    def test_simulation_mode(self):
        result = check_traffic_pattern("wg0", execute=False)
        assert result.verdict == "SIMULATED"

    @patch("dev_tools.sandbox.live_validation.dpi_resistance_test.run_command")
    def test_high_entropy_passes(self, mock_run):
        # Generate diverse packet sizes.
        lines = []
        for i in range(50):
            size = 64 + (i * 37) % 1400  # Spread across range.
            ts = f"12:00:{i:02d}.{(i*17)%1000:03d}000"
            lines.append(
                f"{ts} IP 1.2.3.4.51820 > 5.6.7.8.12345: UDP, length {size}"
            )
        mock_run.return_value = CommandResult("tcpdump", 0, "\n".join(lines), "", 10000.0)
        result = check_traffic_pattern("wg0", execute=True)
        assert result.packets_analyzed == 50
        assert result.size_entropy > 0.5  # High diversity.
        assert result.verdict == "PASS"


# ---------------------------------------------------------------------------
# Full test runner
# ---------------------------------------------------------------------------


class TestRunDpiResistanceTest:
    def test_simulation_mode(self):
        report = run_dpi_resistance_test(
            tunnel_interface="wg0",
            execute=False,
        )
        assert report.verdict == "SIMULATED"
        assert report.fingerprint.verdict == "SIMULATED"
        assert report.port_block.verdict == "SIMULATED"
        assert report.throttle.verdict == "SIMULATED"
        assert report.traffic_pattern.verdict == "SIMULATED"
        assert report.failures == []


class TestDpiResistanceReport:
    def test_to_dict(self):
        r = DpiResistanceReport(verdict="PASS")
        d = r.to_dict()
        assert d["verdict"] == "PASS"
        assert "fingerprint" in d
        assert "port_block" in d
        assert "throttle" in d
        assert "traffic_pattern" in d

    def test_defaults(self):
        r = DpiResistanceReport()
        assert r.verdict == "UNTESTED"
        assert r.execute is False


# ---------------------------------------------------------------------------
# WireGuard constants
# ---------------------------------------------------------------------------


class TestWireGuardConstants:
    def test_known_sizes(self):
        assert WG_HANDSHAKE_INITIATION_SIZE == 148
        assert WG_HANDSHAKE_RESPONSE_SIZE == 92
        assert WG_HANDSHAKE_COOKIE_SIZE == 64
        assert len(WG_KNOWN_SIZES) == 3
