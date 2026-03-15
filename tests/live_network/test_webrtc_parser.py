"""CI-safe unit tests for WebRTC leak detection logic.

No browser, tunnel, or network access required.
"""

from __future__ import annotations

import struct

from dev_tools.sandbox.live_validation.webrtc_leak_test import (
    IceCandidate,
    WebRtcLeakReport,
    _is_private_ip,
    _parse_stun_response,
    _stun_binding_request,
    evaluate_candidates,
    parse_ice_candidate_line,
)


class TestParseIceCandidateLine:
    def test_parses_host_candidate(self):
        line = "candidate:0 1 UDP 2122252543 192.168.1.100 54321 typ host"
        c = parse_ice_candidate_line(line)
        assert c is not None
        assert c.ip == "192.168.1.100"
        assert c.port == 54321
        assert c.candidate_type == "host"

    def test_parses_srflx_candidate(self):
        line = "candidate:1 1 UDP 1686052863 203.0.113.50 12345 typ srflx raddr 192.168.1.100 rport 54321"
        c = parse_ice_candidate_line(line)
        assert c is not None
        assert c.ip == "203.0.113.50"
        assert c.candidate_type == "srflx"

    def test_returns_none_for_invalid(self):
        assert parse_ice_candidate_line("") is None
        assert parse_ice_candidate_line("not a candidate") is None


class TestIsPrivateIp:
    def test_private_ranges(self):
        assert _is_private_ip("192.168.1.1") is True
        assert _is_private_ip("10.0.0.1") is True
        assert _is_private_ip("172.16.0.1") is True
        assert _is_private_ip("127.0.0.1") is True

    def test_public_ips(self):
        assert _is_private_ip("8.8.8.8") is False
        assert _is_private_ip("138.199.204.139") is False

    def test_link_local(self):
        assert _is_private_ip("169.254.1.1") is True

    def test_invalid(self):
        assert _is_private_ip("not_an_ip") is False


class TestEvaluateCandidates:
    def test_pass_when_only_vpn_exit(self):
        candidates = [IceCandidate(ip="138.199.204.139", candidate_type="srflx")]
        ok, leaked = evaluate_candidates(
            candidates,
            vpn_exit_ip="138.199.204.139",
            tunnel_interface_ips={"10.88.0.2"},
        )
        assert ok is True
        assert leaked == []

    def test_pass_with_tunnel_private_ip(self):
        candidates = [
            IceCandidate(ip="138.199.204.139", candidate_type="srflx"),
            IceCandidate(ip="10.88.0.2", candidate_type="host"),
        ]
        ok, leaked = evaluate_candidates(
            candidates,
            vpn_exit_ip="138.199.204.139",
            tunnel_interface_ips={"10.88.0.2"},
        )
        assert ok is True

    def test_fail_with_real_public_ip(self):
        candidates = [
            IceCandidate(ip="138.199.204.139", candidate_type="srflx"),
            IceCandidate(ip="203.0.113.50", candidate_type="srflx"),  # Real IP leak.
        ]
        ok, leaked = evaluate_candidates(
            candidates,
            vpn_exit_ip="138.199.204.139",
            tunnel_interface_ips={"10.88.0.2"},
        )
        assert ok is False
        assert "203.0.113.50" in leaked

    def test_fail_with_non_vpn_private_ip(self):
        candidates = [
            IceCandidate(ip="192.168.1.100", candidate_type="host"),  # Local LAN leak.
        ]
        ok, leaked = evaluate_candidates(
            candidates,
            vpn_exit_ip="138.199.204.139",
            tunnel_interface_ips={"10.88.0.2"},
        )
        assert ok is False
        assert "192.168.1.100" in leaked

    def test_empty_candidates_pass(self):
        ok, leaked = evaluate_candidates(
            [],
            vpn_exit_ip="138.199.204.139",
            tunnel_interface_ips=set(),
        )
        assert ok is True


class TestStunProtocol:
    def test_binding_request_format(self):
        req = _stun_binding_request()
        assert len(req) == 20  # 4 + 4 + 12 bytes
        msg_type = struct.unpack("!H", req[0:2])[0]
        assert msg_type == 0x0001  # Binding Request
        magic = struct.unpack("!I", req[4:8])[0]
        assert magic == 0x2112A442

    def test_parse_xor_mapped_address(self):
        # Build a synthetic STUN Binding Success Response.
        magic = 0x2112A442
        txn_id = b"\x00" * 12

        # XOR-MAPPED-ADDRESS: IPv4, port 54321, IP 203.0.113.50
        import socket
        ip_int = struct.unpack("!I", socket.inet_aton("203.0.113.50"))[0]
        xip = ip_int ^ magic
        xport = 54321 ^ (magic >> 16)
        attr = struct.pack("!BBHI", 0, 0x01, xport, xip)
        attr_header = struct.pack("!HH", 0x0020, len(attr))

        header = struct.pack("!HHI", 0x0101, len(attr_header) + len(attr), magic) + txn_id
        response = header + attr_header + attr

        result = _parse_stun_response(response)
        assert result == "203.0.113.50"

    def test_parse_too_short(self):
        assert _parse_stun_response(b"\x00" * 10) is None

    def test_parse_wrong_type(self):
        # Build a non-success response.
        header = struct.pack("!HHI", 0x0111, 0, 0x2112A442) + b"\x00" * 12
        assert _parse_stun_response(header) is None


class TestWebRtcLeakReport:
    def test_to_dict(self):
        r = WebRtcLeakReport(verdict="PASS", method="stun")
        d = r.to_dict()
        assert d["verdict"] == "PASS"
        assert d["method"] == "stun"
        assert "candidates" in d
        assert "leaked_ips" in d

    def test_defaults(self):
        r = WebRtcLeakReport()
        assert r.verdict == "UNTESTED"
        assert r.method == ""
