from __future__ import annotations
import json
import os
import subprocess
import threading
import time
from pathlib import Path

from backend.services.plan_manager import get_plan_manager

_PROTO_IFACE = {"wireguard": "wg0", "openvpn": "tun0", "ikev2": "ipsec0"}
_TBF_HANDLE = "551:"


class TrafficShaper:
    def __init__(self, state_file: str = "data/usage/traffic_shaper_state.json") -> None:
        self._lock = threading.Lock()
        self._down_kbit = int(os.getenv("SW_FREE_DOWN_KBIT", "20000"))
        self._burst_kbit = int(os.getenv("SW_FREE_BURST_KBIT", "512"))
        self._daily_quota_bytes = int(os.getenv("SW_FREE_DAILY_QUOTA_BYTES", "0"))
        self._state_file = Path(state_file)
        self._state_file.parent.mkdir(parents=True, exist_ok=True)
        self._state = self._load()

    def _load(self) -> dict:
        try:
            return json.loads(self._state_file.read_text(encoding="utf-8"))
        except Exception:
            return {"sessions": {}}

    def _save(self) -> None:
        tmp = self._state_file.with_suffix(".tmp")
        tmp.write_text(json.dumps(self._state, separators=(",", ":"), sort_keys=True), encoding="utf-8")
        tmp.replace(self._state_file)

    @staticmethod
    def _run(*args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(list(args), capture_output=True, text=True, timeout=10, check=False)  # nosec B603

    @staticmethod
    def _used_today_bytes(user_id: int, usage_file: Path) -> int:
        if not usage_file.exists():
            return 0
        total = 0
        now = int(time.time())
        for raw in usage_file.read_text(encoding="utf-8").splitlines():
            try:
                rec = json.loads(raw)
            except json.JSONDecodeError:
                continue
            if int(rec.get("user_id", -1)) != int(user_id):
                continue
            if now - int(rec.get("ended_at", now)) > 86400:
                continue
            total += int(rec.get("rx_bytes", 0)) + int(rec.get("tx_bytes", 0))
        return total

    def _iface_for(self, protocol: str, iface_hint: str | None) -> str:
        iface = (iface_hint or _PROTO_IFACE.get(protocol, "")).strip()
        if protocol == "ikev2" and not Path(f"/sys/class/net/{iface}").exists():
            iface = "xfrm0" if Path("/sys/class/net/xfrm0").exists() else iface
        if not iface or not Path(f"/sys/class/net/{iface}").exists():
            raise FileNotFoundError(f"shaping iface missing for protocol={protocol}")
        return iface

    def _root_qdisc(self, iface: str) -> str:
        out = self._run("tc", "qdisc", "show", "dev", iface).stdout or ""
        for line in out.splitlines():
            if " root " in line:
                return line.strip()
        return ""

    def _is_default_root(self, line: str) -> bool:
        return any(name in line for name in ("qdisc noqueue ", "qdisc pfifo_fast ", "qdisc fq_codel "))

    def _apply_free_tbf(self, iface: str) -> None:
        root = self._root_qdisc(iface)
        if _TBF_HANDLE in root and " tbf " in root:
            return
        if root and not self._is_default_root(root):
            raise RuntimeError(f"unmanaged_root_qdisc iface={iface} root={root}")
        # Rollback path: `tc qdisc del dev <iface> root` restores kernel default qdisc.
        self._run(
            "tc", "qdisc", "replace", "dev", iface, "root", "handle", _TBF_HANDLE, "tbf",
            "rate", f"{self._down_kbit}kbit", "burst", f"{self._burst_kbit}kbit", "latency", "50ms",
        )

    def _remove_free_tbf(self, iface: str) -> None:
        root = self._root_qdisc(iface)
        if _TBF_HANDLE in root and " tbf " in root:
            self._run("tc", "qdisc", "del", "dev", iface, "root")

    def apply_for_session(self, user_id: int, protocol: str, tier: str, session_id: str, iface_hint: str | None = None) -> dict:
        decision = get_plan_manager().resolve(user_id=user_id, raw_tier=tier)
        iface = self._iface_for(protocol, iface_hint)
        sid = session_id or f"{user_id}:{protocol}:{int(time.time()*1000)}"
        with self._lock:
            if sid in self._state["sessions"]:
                return self._state["sessions"][sid]
            if decision.is_free and self._daily_quota_bytes > 0:
                used = self._used_today_bytes(decision.user_id, Path("data/usage/session_usage.jsonl"))
                if used >= self._daily_quota_bytes:
                    rec = {"session_id": sid, "protocol": protocol, "tier": "free", "iface": iface, "shaped": False, "blocked": True}
                    self._state["sessions"][sid] = rec
                    self._save()
                    return rec
            shaped = False
            if decision.is_free:
                self._apply_free_tbf(iface)
                shaped = True
            rec = {"session_id": sid, "user_id": decision.user_id, "protocol": protocol, "tier": decision.tier, "iface": iface, "shaped": shaped, "blocked": False}
            self._state["sessions"][sid] = rec
            self._save()
            return rec

    def remove_for_session(self, session_id: str) -> dict:
        with self._lock:
            rec = self._state["sessions"].pop(session_id, None)
            if rec is None:
                return {"session_id": session_id, "removed": False}
            if rec.get("shaped"):
                iface = rec["iface"]
                keep = any(v.get("iface") == iface and v.get("shaped") for v in self._state["sessions"].values())
                if not keep:
                    self._remove_free_tbf(iface)
            self._save()
            return {"session_id": session_id, "removed": True, "shaped": bool(rec.get("shaped")), "iface": rec.get("iface")}


_shaper: TrafficShaper | None = None


def get_traffic_shaper() -> TrafficShaper:
    global _shaper
    if _shaper is None:
        _shaper = TrafficShaper()
    return _shaper
