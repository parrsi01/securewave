from __future__ import annotations

from dataclasses import dataclass, replace
from enum import Enum


class FailureBucket(str, Enum):
    ROUTING_ERROR = "ROUTING_ERROR"
    DNS_FAILURE = "DNS_FAILURE"
    INTERFACE_DOWN = "INTERFACE_DOWN"
    FIREWALL_BLOCK = "FIREWALL_BLOCK"
    NAT_FAILURE = "NAT_FAILURE"
    HANDSHAKE_FAILURE = "HANDSHAKE_FAILURE"
    MTU_ISSUE = "MTU_ISSUE"
    DHCP_FAILURE = "DHCP_FAILURE"
    VM_NETWORK_MODE_CONFLICT = "VM_NETWORK_MODE_CONFLICT"
    SERVICE_FAILURE = "SERVICE_FAILURE"


@dataclass(frozen=True)
class SimulatedVpnState:
    vpn_interface: str = "wg0"
    nat_interface: str = "enp0s1"
    default_route_dev: str = "wg0"
    stale_default_gateway: str | None = None
    dns_working: bool = True
    interface_up: bool = True
    firewall_forward_accept: bool = True
    nat_masquerade: bool = True
    handshake_ok: bool = True
    mtu_ok: bool = True
    dhcp_ok: bool = True
    vm_network_mode_ok: bool = True
    service_running: bool = True
    internet_reachable: bool = True

    def healthy(self) -> bool:
        return (
            self.default_route_dev == self.vpn_interface
            and self.stale_default_gateway is None
            and self.dns_working
            and self.interface_up
            and self.firewall_forward_accept
            and self.nat_masquerade
            and self.handshake_ok
            and self.mtu_ok
            and self.dhcp_ok
            and self.vm_network_mode_ok
            and self.service_running
            and self.internet_reachable
        )


def classify_failures(state: SimulatedVpnState) -> list[FailureBucket]:
    failures: list[FailureBucket] = []
    if state.default_route_dev != state.vpn_interface or state.stale_default_gateway:
        failures.append(FailureBucket.ROUTING_ERROR)
    if not state.dns_working:
        failures.append(FailureBucket.DNS_FAILURE)
    if not state.interface_up:
        failures.append(FailureBucket.INTERFACE_DOWN)
    if not state.firewall_forward_accept:
        failures.append(FailureBucket.FIREWALL_BLOCK)
    if not state.nat_masquerade:
        failures.append(FailureBucket.NAT_FAILURE)
    if not state.handshake_ok:
        failures.append(FailureBucket.HANDSHAKE_FAILURE)
    if not state.mtu_ok:
        failures.append(FailureBucket.MTU_ISSUE)
    if not state.dhcp_ok:
        failures.append(FailureBucket.DHCP_FAILURE)
    if not state.vm_network_mode_ok:
        failures.append(FailureBucket.VM_NETWORK_MODE_CONFLICT)
    if not state.service_running:
        failures.append(FailureBucket.SERVICE_FAILURE)
    return failures


def build_fix_plan(state: SimulatedVpnState) -> list[str]:
    commands: list[str] = []
    for bucket in classify_failures(state):
        if bucket is FailureBucket.ROUTING_ERROR:
            commands.append(f"ip route replace default dev {state.vpn_interface}")
            if state.stale_default_gateway:
                commands.append(f"ip route delete default via {state.stale_default_gateway}")
        elif bucket is FailureBucket.DNS_FAILURE:
            commands.append('echo "nameserver 1.1.1.1" > /etc/resolv.conf')
        elif bucket is FailureBucket.INTERFACE_DOWN:
            commands.append(f"ip link set {state.nat_interface} up")
            commands.append(f"dhclient {state.nat_interface}")
        elif bucket is FailureBucket.FIREWALL_BLOCK:
            commands.append("iptables -P FORWARD ACCEPT")
            commands.append("iptables -F")
        elif bucket is FailureBucket.NAT_FAILURE:
            commands.append(f"iptables -t nat -A POSTROUTING -o {state.nat_interface} -j MASQUERADE")
        elif bucket is FailureBucket.HANDSHAKE_FAILURE:
            commands.append("wg show")
            commands.append("systemctl restart wg-quick@wg0")
        elif bucket is FailureBucket.MTU_ISSUE:
            commands.append(f"ip link set dev {state.vpn_interface} mtu 1380")
        elif bucket is FailureBucket.DHCP_FAILURE:
            commands.append(f"dhclient -v {state.nat_interface}")
        elif bucket is FailureBucket.VM_NETWORK_MODE_CONFLICT:
            commands.append("nmcli networking on")
            commands.append(f"ip link set {state.nat_interface} up")
        elif bucket is FailureBucket.SERVICE_FAILURE:
            commands.append("systemctl restart NetworkManager")
    return commands


def apply_fix_plan(state: SimulatedVpnState) -> SimulatedVpnState:
    failures = classify_failures(state)
    updated = state
    for bucket in failures:
        if bucket is FailureBucket.ROUTING_ERROR:
            updated = replace(
                updated,
                default_route_dev=updated.vpn_interface,
                stale_default_gateway=None,
            )
        elif bucket is FailureBucket.DNS_FAILURE:
            updated = replace(updated, dns_working=True)
        elif bucket is FailureBucket.INTERFACE_DOWN:
            updated = replace(updated, interface_up=True, dhcp_ok=True)
        elif bucket is FailureBucket.FIREWALL_BLOCK:
            updated = replace(updated, firewall_forward_accept=True)
        elif bucket is FailureBucket.NAT_FAILURE:
            updated = replace(updated, nat_masquerade=True)
        elif bucket is FailureBucket.HANDSHAKE_FAILURE:
            updated = replace(updated, handshake_ok=True)
        elif bucket is FailureBucket.MTU_ISSUE:
            updated = replace(updated, mtu_ok=True)
        elif bucket is FailureBucket.DHCP_FAILURE:
            updated = replace(updated, dhcp_ok=True)
        elif bucket is FailureBucket.VM_NETWORK_MODE_CONFLICT:
            updated = replace(updated, vm_network_mode_ok=True, interface_up=True)
        elif bucket is FailureBucket.SERVICE_FAILURE:
            updated = replace(updated, service_running=True)

    if updated.default_route_dev == updated.vpn_interface and updated.stale_default_gateway is None:
        updated = replace(updated, internet_reachable=True)
    if updated.dns_working and updated.interface_up and updated.service_running:
        updated = replace(updated, internet_reachable=True)
    return updated
