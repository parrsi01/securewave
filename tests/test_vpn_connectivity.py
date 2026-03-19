from dev_tools.local_agents.vpn_failure_playbook import (
    FailureBucket,
    SimulatedVpnState,
    apply_fix_plan,
    build_fix_plan,
    classify_failures,
)


def test_broken_routing_restored():
    state = SimulatedVpnState(
        default_route_dev="enp0s1",
        stale_default_gateway="192.168.64.1",
        internet_reachable=False,
    )

    failures = classify_failures(state)
    assert FailureBucket.ROUTING_ERROR in failures
    commands = build_fix_plan(state)
    assert "ip route replace default dev wg0" in commands
    assert "ip route delete default via 192.168.64.1" in commands

    fixed = apply_fix_plan(state)
    assert fixed.healthy()


def test_dns_failure_restored():
    state = SimulatedVpnState(dns_working=False, internet_reachable=False)

    failures = classify_failures(state)
    assert FailureBucket.DNS_FAILURE in failures
    commands = build_fix_plan(state)
    assert 'echo "nameserver 1.1.1.1" > /etc/resolv.conf' in commands

    fixed = apply_fix_plan(state)
    assert fixed.healthy()


def test_interface_down_restored():
    state = SimulatedVpnState(interface_up=False, dhcp_ok=False, internet_reachable=False)

    failures = classify_failures(state)
    assert FailureBucket.INTERFACE_DOWN in failures
    commands = build_fix_plan(state)
    assert "ip link set enp0s1 up" in commands
    assert "dhclient enp0s1" in commands

    fixed = apply_fix_plan(state)
    assert fixed.healthy()


def test_firewall_block_restored():
    state = SimulatedVpnState(firewall_forward_accept=False, internet_reachable=False)

    failures = classify_failures(state)
    assert FailureBucket.FIREWALL_BLOCK in failures
    commands = build_fix_plan(state)
    assert "iptables -P FORWARD ACCEPT" in commands
    assert "iptables -F" in commands

    fixed = apply_fix_plan(state)
    assert fixed.healthy()


def test_nat_failure_restored():
    state = SimulatedVpnState(nat_masquerade=False, internet_reachable=False)

    failures = classify_failures(state)
    assert FailureBucket.NAT_FAILURE in failures
    commands = build_fix_plan(state)
    assert "iptables -t nat -A POSTROUTING -o enp0s1 -j MASQUERADE" in commands

    fixed = apply_fix_plan(state)
    assert fixed.healthy()


def test_handshake_failure_restored():
    state = SimulatedVpnState(handshake_ok=False, internet_reachable=False)

    failures = classify_failures(state)
    assert FailureBucket.HANDSHAKE_FAILURE in failures
    commands = build_fix_plan(state)
    assert "wg show" in commands
    assert "systemctl restart wg-quick@wg0" in commands

    fixed = apply_fix_plan(state)
    assert fixed.healthy()


def test_mtu_issue_restored():
    state = SimulatedVpnState(mtu_ok=False, internet_reachable=False)

    failures = classify_failures(state)
    assert FailureBucket.MTU_ISSUE in failures
    commands = build_fix_plan(state)
    assert "ip link set dev wg0 mtu 1380" in commands

    fixed = apply_fix_plan(state)
    assert fixed.healthy()
