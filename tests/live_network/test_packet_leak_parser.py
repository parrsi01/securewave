from dev_tools.sandbox.live_validation.packet_leak_test import (
    PacketObservation,
    analyze_packet_observations,
    derive_blocked_interfaces,
    packet_signature,
    parse_tcpdump_capture,
)


def test_parse_tcpdump_capture_extracts_interface_and_direction():
    output = """
2026-03-13 03:00:00.000000 wg0 Out IP 10.8.0.2.43124 > 93.184.216.34.443: Flags [S]
2026-03-13 03:00:00.100000 enp0s1 Out IP 192.168.64.2.40000 > 1.1.1.1.53: UDP, length 32
""".strip()

    packets = parse_tcpdump_capture(output)

    assert len(packets) == 2
    assert packets[0].interface == "wg0"
    assert packets[0].direction == "Out"
    assert packets[0].destination_host() == "93.184.216.34"
    assert packets[1].interface == "enp0s1"
    assert packets[1].destination_host() == "1.1.1.1"


def test_derive_blocked_interfaces_prefers_default_gateway_and_physical_ifaces():
    snapshot = """
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536
2: enp0s1: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500
3: docker0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500
4: wg0: <POINTOPOINT,NOARP,UP,LOWER_UP> mtu 1420
5: wlan0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500
""".strip()

    blocked = derive_blocked_interfaces(
        snapshot,
        tunnel_interface="wg0",
        default_route_interfaces=["enp0s1"],
    )

    assert blocked == ["enp0s1", "wlan0"]


def test_analyze_packet_observations_flags_non_tunnel_probe_traffic():
    packets = [
        PacketObservation(
            timestamp="2026-03-13 03:00:00.000000",
            interface="wg0",
            direction="Out",
            protocol="IP",
            source="10.8.0.2.43124",
            destination="93.184.216.34.443",
        ),
        PacketObservation(
            timestamp="2026-03-13 03:00:00.100000",
            interface="enp0s1",
            direction="Out",
            protocol="IP",
            source="192.168.64.2.40000",
            destination="1.1.1.1.53",
        ),
    ]

    leaks, ignored, tunnel_probe_packets = analyze_packet_observations(
        packets,
        tunnel_interface="wg0",
        blocked_interfaces={"enp0s1"},
        probe_targets={"93.184.216.34", "1.1.1.1"},
        baseline_signatures=None,
    )

    assert ignored == 0
    assert tunnel_probe_packets == 1
    assert len(leaks) == 1
    assert leaks[0].interface == "enp0s1"


def test_analyze_packet_observations_ignores_baseline_noise():
    baseline_packet = PacketObservation(
        timestamp="2026-03-13 03:00:00.000000",
        interface="enp0s1",
        direction="Out",
        protocol="IP",
        source="192.168.64.2.5353",
        destination="224.0.0.251.5353",
    )
    packets = [
        baseline_packet,
        PacketObservation(
            timestamp="2026-03-13 03:00:01.000000",
            interface="wg0",
            direction="Out",
            protocol="IP",
            source="10.8.0.2.43124",
            destination="93.184.216.34.443",
        ),
    ]

    leaks, ignored, tunnel_probe_packets = analyze_packet_observations(
        packets,
        tunnel_interface="wg0",
        blocked_interfaces={"enp0s1"},
        probe_targets={"93.184.216.34"},
        baseline_signatures={packet_signature(baseline_packet)},
    )

    assert leaks == []
    assert ignored == 1
    assert tunnel_probe_packets == 1
