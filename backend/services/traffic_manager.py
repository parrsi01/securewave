from __future__ import annotations
import json
import os
import threading
import time
from pathlib import Path
from typing import Optional

_PROTO_IFACE = {"wireguard": "wg0", "openvpn": "tun0", "ikev2": "ipsec0"}
class TrafficManager:
    def __init__(self, usage_dir: str = "data/usage") -> None:
        self._lock = threading.Lock()
        self._active: dict[str, dict] = {}
        self._usage_dir = Path(usage_dir)
        self._usage_dir.mkdir(parents=True, exist_ok=True)
        self._store = self._usage_dir / "session_usage.jsonl"
        self._store.touch(exist_ok=True)

    @staticmethod
    def _counter_path(iface: str, key: str) -> Path:
        return Path(f"/sys/class/net/{iface}/statistics/{key}_bytes")

    @classmethod
    def _read_counters(cls, iface: str) -> tuple[int, int]:
        rx_path = cls._counter_path(iface, "rx")
        tx_path = cls._counter_path(iface, "tx")
        return int(rx_path.read_text(encoding="utf-8").strip()), int(tx_path.read_text(encoding="utf-8").strip())

    def _resolve_iface(self, protocol: str, iface_hint: Optional[str]) -> str:
        candidates = [iface_hint, _PROTO_IFACE.get(protocol)]
        if protocol == "ikev2":
            # strongSwan/xfrm deployments may expose ipsec0/xfrm0 depending on kernel/userspace mode.
            candidates.extend(["xfrm0"])
        for iface in [c for c in candidates if c]:
            if self._counter_path(iface, "rx").exists() and self._counter_path(iface, "tx").exists():
                return iface
        raise FileNotFoundError(f"no counter interface found for protocol={protocol}")

    def start_meter(
        self,
        user_id: int,
        protocol: str,
        session_id: Optional[str] = None,
        iface_hint: Optional[str] = None,
    ) -> dict:
        iface = self._resolve_iface(protocol, iface_hint)
        base_rx, base_tx = self._read_counters(iface)
        sid = session_id or f"{user_id}:{protocol}:{int(time.time() * 1000)}"
        with self._lock:
            self._active[sid] = {
                "session_id": sid,
                "user_id": int(user_id),
                "protocol": protocol,
                "iface": iface,
                "started_at": int(time.time()),
                "base_rx": base_rx,
                "base_tx": base_tx,
            }
        return {"session_id": sid, "user_id": int(user_id), "protocol": protocol, "iface": iface}

    def stop_meter(self, session_id: str) -> dict:
        with self._lock:
            entry = self._active.pop(session_id, None)
        if entry is None:
            return {"session_id": session_id, "stopped": False}
        now_rx, now_tx = self._read_counters(entry["iface"])
        record = {
            "session_id": entry["session_id"],
            "user_id": entry["user_id"],
            "protocol": entry["protocol"],
            "iface": entry["iface"],
            "started_at": entry["started_at"],
            "ended_at": int(time.time()),
            "rx_bytes": max(0, int(now_rx) - int(entry["base_rx"])),
            "tx_bytes": max(0, int(now_tx) - int(entry["base_tx"])),
            "stopped": True,
        }
        line = json.dumps(record, separators=(",", ":"), sort_keys=True)
        with self._store.open("a", encoding="utf-8") as handle:
            handle.write(line + "\n")
            handle.flush()
            os.fsync(handle.fileno())
        return record

    def current_session_usage(self, user_id: int, protocol: Optional[str] = None) -> Optional[dict]:
        with self._lock:
            entries = [e for e in self._active.values() if e["user_id"] == int(user_id)]
        if protocol:
            entries = [e for e in entries if e["protocol"] == protocol]
        if not entries:
            return None
        active = max(entries, key=lambda e: e["started_at"])
        now_rx, now_tx = self._read_counters(active["iface"])
        return {
            "session_id": active["session_id"],
            "protocol": active["protocol"],
            "iface": active["iface"],
            "rx_bytes": max(0, int(now_rx) - int(active["base_rx"])),
            "tx_bytes": max(0, int(now_tx) - int(active["base_tx"])),
        }

    def last_session_usage(self, user_id: int) -> Optional[dict]:
        lines = self._store.read_text(encoding="utf-8").splitlines() if self._store.exists() else []
        for raw in reversed(lines):
            try:
                record = json.loads(raw)
            except json.JSONDecodeError:
                continue
            if int(record.get("user_id", -1)) == int(user_id):
                return record
        return None
_manager: Optional[TrafficManager] = None
_manager_lock = threading.Lock()
def get_traffic_manager() -> TrafficManager:
    global _manager
    if _manager is None:
        with _manager_lock:
            if _manager is None:
                _manager = TrafficManager()
    return _manager
