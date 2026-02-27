import logging
import os
import subprocess  # nosec B404 - controlled invocation

from services import routing_manager

logger = logging.getLogger(__name__)


class OpenVPNService:
    @staticmethod
    def _detect_egress_iface() -> str:
        try:
            proc = subprocess.run(  # nosec B603 - fixed command
                ["ip", "-4", "route", "show", "default"],
                capture_output=True,
                text=True,
                timeout=5,
                check=False,
            )
            parts = (proc.stdout or "").split()
            if "dev" in parts:
                idx = parts.index("dev")
                if idx + 1 < len(parts):
                    return parts[idx + 1].strip()
        except Exception:
            pass
        return (os.getenv("OPENVPN_EGRESS_IFACE", "").strip() or "eth0")

    def setup_policy_routing(self, egress_iface: str | None = None) -> None:
        iface = egress_iface or self._detect_egress_iface()
        routing_manager.setup_protocol("openvpn", iface)
        logger.info("openvpn routing table=200 configured egress=%s", iface)

    def teardown_policy_routing(self, egress_iface: str | None = None) -> None:
        iface = egress_iface or self._detect_egress_iface()
        routing_manager.teardown_protocol("openvpn", iface)
        logger.info("openvpn routing table=200 removed egress=%s", iface)
