#!/usr/bin/env python3
"""WebRTC leak detection for SecureWave VPN tunnels.

Validates that WebRTC ICE candidates do not expose the real (non-VPN)
IP address. Uses a lightweight approach:

1. If Playwright is available: headless Chromium ICE candidate extraction.
2. Fallback: STUN-based detection using raw UDP (no browser needed).

A WebRTC leak occurs when ICE candidates contain the host's real
public IP or a local network IP that differs from the VPN interface.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import socket
import struct
import sys
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[3]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from dev_tools.sandbox.live_validation.common import (
    fetch_public_ip,
    run_command,
    utc_now_iso,
    write_json,
)

# Default STUN servers for lightweight probing.
STUN_SERVERS = [
    ("stun.l.google.com", 19302),
    ("stun1.l.google.com", 19302),
]


@dataclass
class IceCandidate:
    """A WebRTC ICE candidate."""

    ip: str = ""
    port: int = 0
    candidate_type: str = ""  # host, srflx, relay
    source: str = ""  # "browser" or "stun"


@dataclass
class WebRtcLeakReport:
    """Full WebRTC leak test report."""

    test_name: str = "webrtc_leak_detection"
    started_at: str = ""
    finished_at: str = ""
    verdict: str = "UNTESTED"

    method: str = ""  # "playwright", "stun", "skip"
    vpn_exit_ip: str = ""
    tunnel_interface: str = ""

    candidates: list[IceCandidate] = field(default_factory=list)
    leaked_ips: list[str] = field(default_factory=list)

    leak_detected: bool = False
    leak_reason: str = ""
    failures: list[str] = field(default_factory=list)

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


def _is_private_ip(ip: str) -> bool:
    """Check if an IP is private/link-local/loopback."""
    import ipaddress
    try:
        addr = ipaddress.ip_address(ip)
        return addr.is_private or addr.is_loopback or addr.is_link_local
    except ValueError:
        return False


def _stun_binding_request() -> bytes:
    """Build a minimal STUN Binding Request (RFC 5389)."""
    msg_type = 0x0001  # Binding Request
    msg_length = 0
    magic_cookie = 0x2112A442
    # 96-bit transaction ID
    import secrets
    txn_id = secrets.token_bytes(12)
    header = struct.pack("!HHI", msg_type, msg_length, magic_cookie) + txn_id
    return header


def _parse_stun_response(data: bytes) -> str | None:
    """Extract XOR-MAPPED-ADDRESS from STUN response."""
    if len(data) < 20:
        return None

    msg_type = struct.unpack("!H", data[0:2])[0]
    if msg_type != 0x0101:  # Binding Success Response
        return None

    magic_cookie = 0x2112A442
    offset = 20  # Skip header.
    while offset + 4 <= len(data):
        attr_type = struct.unpack("!H", data[offset:offset + 2])[0]
        attr_length = struct.unpack("!H", data[offset + 2:offset + 4])[0]
        attr_data = data[offset + 4:offset + 4 + attr_length]

        if attr_type == 0x0020 and len(attr_data) >= 8:  # XOR-MAPPED-ADDRESS
            family = attr_data[1]
            if family == 0x01:  # IPv4
                xport = struct.unpack("!H", attr_data[2:4])[0] ^ (magic_cookie >> 16)
                xip = struct.unpack("!I", attr_data[4:8])[0] ^ magic_cookie
                ip = socket.inet_ntoa(struct.pack("!I", xip))
                return ip

        if attr_type == 0x0001 and len(attr_data) >= 8:  # MAPPED-ADDRESS (fallback)
            family = attr_data[1]
            if family == 0x01:
                ip = socket.inet_ntoa(attr_data[4:8])
                return ip

        # Pad to 4-byte boundary.
        offset += 4 + attr_length + (4 - attr_length % 4) % 4

    return None


def stun_probe(servers: list[tuple[str, int]] | None = None, *, timeout: float = 5.0) -> list[IceCandidate]:
    """Perform STUN binding requests to discover reflexive IP."""
    candidates: list[IceCandidate] = []
    for host, port in (servers or STUN_SERVERS):
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            sock.settimeout(timeout)
            sock.sendto(_stun_binding_request(), (host, port))
            data, _ = sock.recvfrom(1024)
            sock.close()
        except Exception:
            continue

        ip = _parse_stun_response(data)
        if ip:
            candidates.append(IceCandidate(
                ip=ip,
                port=0,
                candidate_type="srflx",
                source="stun",
            ))
    return candidates


def playwright_probe(*, timeout_ms: int = 15000) -> list[IceCandidate]:
    """Use Playwright headless Chromium to extract ICE candidates.

    Returns empty list if Playwright is not installed.
    """
    try:
        from playwright.sync_api import sync_playwright  # type: ignore[import-untyped]
    except ImportError:
        return []

    js_script = """
    async () => {
        const candidates = [];
        const pc = new RTCPeerConnection({iceServers: [{urls: 'stun:stun.l.google.com:19302'}]});
        pc.createDataChannel('');
        const offer = await pc.createOffer();
        await pc.setLocalDescription(offer);
        return new Promise((resolve) => {
            pc.onicecandidate = (e) => {
                if (e.candidate) {
                    candidates.push(e.candidate.candidate);
                } else {
                    resolve(candidates);
                }
            };
            setTimeout(() => resolve(candidates), 8000);
        });
    }
    """

    candidates: list[IceCandidate] = []
    try:
        with sync_playwright() as p:
            browser = p.chromium.launch(headless=True)
            page = browser.new_page()
            page.goto("about:blank")
            raw_candidates = page.evaluate(js_script)
            browser.close()

            for raw in raw_candidates:
                parsed = parse_ice_candidate_line(raw)
                if parsed:
                    candidates.append(parsed)
    except Exception:
        pass

    return candidates


def parse_ice_candidate_line(line: str) -> IceCandidate | None:
    """Parse an ICE candidate string.

    Format: "candidate:... <priority> <ip> <port> typ <type> ..."
    """
    # Match IP address in candidate line.
    match = re.search(
        r"candidate:\S+\s+\d+\s+\w+\s+\d+\s+([\d.]+)\s+(\d+)\s+typ\s+(\w+)",
        line,
    )
    if not match:
        return None
    return IceCandidate(
        ip=match.group(1),
        port=int(match.group(2)),
        candidate_type=match.group(3),
        source="browser",
    )


def evaluate_candidates(
    candidates: list[IceCandidate],
    *,
    vpn_exit_ip: str,
    tunnel_interface_ips: set[str],
) -> tuple[bool, list[str]]:
    """Evaluate ICE candidates for leaks.

    A leak is detected if a candidate contains:
    - A public IP that is NOT the VPN exit IP
    - A local IP not belonging to the VPN interface

    Private IPs on the VPN interface are allowed.
    """
    leaked: list[str] = []
    for c in candidates:
        if not c.ip:
            continue
        if c.ip == vpn_exit_ip:
            continue
        if c.ip in tunnel_interface_ips:
            continue
        if _is_private_ip(c.ip):
            # Private IP not on VPN interface — potential local leak.
            leaked.append(c.ip)
        else:
            # Public IP that isn't VPN exit — definite leak.
            leaked.append(c.ip)

    return len(leaked) == 0, leaked


def run_webrtc_leak_test(
    *,
    tunnel_interface: str | None = None,
    tunnel_active: bool = True,
    vpn_exit_ip: str = "",
    output_dir: Path | None = None,
) -> WebRtcLeakReport:
    """Run the full WebRTC leak detection test."""
    report = WebRtcLeakReport(started_at=utc_now_iso())
    report.tunnel_interface = tunnel_interface or ""
    report.vpn_exit_ip = vpn_exit_ip

    if not tunnel_active:
        report.verdict = "SKIP"
        report.method = "skip"
        report.failures.append("tunnel_not_active")
        report.finished_at = utc_now_iso()
        return report

    # Get VPN exit IP if not provided.
    if not vpn_exit_ip:
        vpn_exit_ip = fetch_public_ip() or ""
        report.vpn_exit_ip = vpn_exit_ip

    # Get tunnel interface IPs.
    tunnel_ips: set[str] = set()
    if tunnel_interface:
        result = run_command(
            ["ip", "-4", "addr", "show", "dev", tunnel_interface],
            timeout_seconds=5,
        )
        for match in re.finditer(r"inet\s+([\d.]+)/", result.stdout):
            tunnel_ips.add(match.group(1))

    # Try Playwright first, fall back to STUN.
    candidates = playwright_probe()
    if candidates:
        report.method = "playwright"
    else:
        candidates = stun_probe()
        report.method = "stun"

    report.candidates = candidates

    if not candidates:
        # No candidates obtained — can't determine leak status.
        report.verdict = "SKIP"
        report.leak_reason = "no_candidates_obtained"
        report.failures.append("unable_to_obtain_ice_candidates")
        report.finished_at = utc_now_iso()
        if output_dir:
            write_json(output_dir / "webrtc_leak_report.json", report.to_dict())
        return report

    ok, leaked = evaluate_candidates(
        candidates,
        vpn_exit_ip=vpn_exit_ip,
        tunnel_interface_ips=tunnel_ips,
    )

    report.leak_detected = not ok
    report.leaked_ips = leaked
    report.verdict = "PASS" if ok else "FAIL"
    if not ok:
        report.leak_reason = f"leaked_ips: {leaked}"
        report.failures.append(f"webrtc_leak: {leaked}")

    report.finished_at = utc_now_iso()
    if output_dir:
        write_json(output_dir / "webrtc_leak_report.json", report.to_dict())
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description="SecureWave WebRTC Leak Detection Test")
    parser.add_argument("--interface", default=os.getenv("DNS_LEAK_TEST_INTERFACE", ""))
    parser.add_argument("--vpn-exit-ip", default="")
    parser.add_argument("--output-dir", default="artifacts/webrtc_leak_test")
    args = parser.parse_args()

    out_dir = Path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    report = run_webrtc_leak_test(
        tunnel_interface=args.interface.strip() or None,
        tunnel_active=True,
        vpn_exit_ip=args.vpn_exit_ip.strip(),
        output_dir=out_dir,
    )

    print(f"\nWEBRTC_LEAK_TEST: {report.verdict}")
    print(f"  method:         {report.method}")
    print(f"  vpn_exit_ip:    {report.vpn_exit_ip}")
    print(f"  candidates:     {len(report.candidates)}")
    print(f"  leak_detected:  {report.leak_detected}")
    if report.leaked_ips:
        print(f"  leaked_ips:     {report.leaked_ips}")
    print()
    print(json.dumps(report.to_dict(), indent=2))
    return 0 if report.verdict == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
