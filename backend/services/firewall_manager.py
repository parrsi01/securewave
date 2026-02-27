from __future__ import annotations

import logging
import subprocess

logger = logging.getLogger(__name__)

_CHAIN_BY_PROTOCOL = {
    "wireguard": "WG_NAT",
    "openvpn": "OVPN_NAT",
    "ikev2": "IKEV2_NAT",
}


class FirewallManager:
    def __init__(self, iptables_bin: str = "iptables") -> None:
        self.iptables_bin = iptables_bin

    @staticmethod
    def _run(*args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(  # nosec B603
            list(args),
            capture_output=True,
            text=True,
            timeout=10,
            check=False,
        )

    def _chain(self, protocol: str) -> str:
        try:
            return _CHAIN_BY_PROTOCOL[protocol]
        except KeyError as exc:
            raise ValueError(f"Unsupported protocol: {protocol!r}") from exc

    @staticmethod
    def _tag(protocol: str, kind: str) -> str:
        return f"sw:{protocol}:{kind}"

    def _rule_exists(self, table: str, chain: str, rule: tuple[str, ...]) -> bool:
        proc = self._run(self.iptables_bin, "-t", table, "-C", chain, *rule)
        return proc.returncode == 0

    def _chain_exists(self, chain: str) -> bool:
        proc = self._run(self.iptables_bin, "-t", "nat", "-S", chain)
        return proc.returncode == 0

    @staticmethod
    def _enable_ip_forward() -> None:
        proc = subprocess.run(  # nosec B603
            ["sysctl", "-n", "net.ipv4.ip_forward"],
            capture_output=True,
            text=True,
            timeout=10,
            check=False,
        )
        if (proc.stdout or "").strip() == "1":
            return
        subprocess.run(  # nosec B603
            ["sysctl", "-w", "net.ipv4.ip_forward=1"],
            capture_output=True,
            text=True,
            timeout=10,
            check=False,
        )

    def setup_protocol_nat(self, protocol: str, source_cidr: str, egress_iface: str) -> None:
        chain = self._chain(protocol)
        self._enable_ip_forward()

        if not self._chain_exists(chain):
            self._run(self.iptables_bin, "-t", "nat", "-N", chain)

        masq_rule = (
            "-s",
            source_cidr,
            "-o",
            egress_iface,
            "-m",
            "comment",
            "--comment",
            self._tag(protocol, "masq"),
            "-j",
            "MASQUERADE",
        )
        if not self._rule_exists("nat", chain, masq_rule):
            self._run(self.iptables_bin, "-t", "nat", "-A", chain, *masq_rule)

        hook_rule = ("-m", "comment", "--comment", self._tag(protocol, "hook"), "-j", chain)
        if not self._rule_exists("nat", "POSTROUTING", hook_rule):
            self._run(self.iptables_bin, "-t", "nat", "-I", "POSTROUTING", "1", *hook_rule)

        logger.info("nat setup protocol=%s chain=%s cidr=%s egress=%s", protocol, chain, source_cidr, egress_iface)

    def teardown_protocol_nat(self, protocol: str, source_cidr: str, egress_iface: str) -> None:
        chain = self._chain(protocol)
        hook_rule = ("-m", "comment", "--comment", self._tag(protocol, "hook"), "-j", chain)
        masq_rule = (
            "-s",
            source_cidr,
            "-o",
            egress_iface,
            "-m",
            "comment",
            "--comment",
            self._tag(protocol, "masq"),
            "-j",
            "MASQUERADE",
        )

        while self._rule_exists("nat", "POSTROUTING", hook_rule):
            self._run(self.iptables_bin, "-t", "nat", "-D", "POSTROUTING", *hook_rule)

        if self._chain_exists(chain):
            while self._rule_exists("nat", chain, masq_rule):
                self._run(self.iptables_bin, "-t", "nat", "-D", chain, *masq_rule)
            chain_dump = self._run(self.iptables_bin, "-t", "nat", "-S", chain)
            owned_entries = [line for line in (chain_dump.stdout or "").splitlines() if line.startswith("-A ")]
            if owned_entries:
                logger.warning("leaving non-empty nat chain %s intact to avoid removing foreign rules", chain)
            else:
                self._run(self.iptables_bin, "-t", "nat", "-X", chain)

        logger.info(
            "nat teardown protocol=%s chain=%s cidr=%s egress=%s",
            protocol,
            chain,
            source_cidr,
            egress_iface,
        )
