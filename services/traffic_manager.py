"""
SecureWave VPN — per-user bandwidth metering and tier-based traffic control.

Responsibilities:
  - Token-bucket rate accounting per user (in-process, lock-safe).
  - Tier classification: free → capped, premium → uncapped but shaped.
  - Per-user byte counters readable by observability endpoints.
  - tc/HTB shaping delegate for server-side enforcement (wraps
    apply_vpn_qos_policy.sh where tc is available).
  - CPU/wake-cycle efficiency: no polling loops; counters updated on
    packet-event callbacks from VPN service layer.

Non-goals (out of scope):
  - Routing changes.
  - Authentication.
  - Protocol configuration beyond efficiency parameters.
"""
from __future__ import annotations

import logging
import os
import shutil
import subprocess
import threading
import time
from dataclasses import dataclass, field
from typing import Dict, Optional

logger = logging.getLogger(__name__)

# ── constants (all overridable via env) ──────────────────────────────────────

_FREE_CAP_MBPS: float = float(os.getenv("SW_FREE_TIER_MBPS", "25"))
_FREE_BURST_MBPS: float = float(os.getenv("SW_FREE_BURST_MBPS", "35"))
_PREMIUM_CAP_MBPS: float = float(os.getenv("SW_PREMIUM_TIER_MBPS", "0"))   # 0 = uncapped
_BUCKET_WINDOW_S: float = float(os.getenv("SW_BUCKET_WINDOW_S", "1.0"))    # token-bucket refill interval
_METER_TTL_S: float = float(os.getenv("SW_METER_TTL_S", "300"))            # evict idle users after N seconds

_FREE_TIERS = frozenset({"free", "basic"})
_PREMIUM_TIERS = frozenset({"premium", "ultra", "pro"})


# ── token bucket ─────────────────────────────────────────────────────────────

@dataclass
class _Bucket:
    """Single-user token bucket for in-process byte accounting."""
    cap_bytes_per_s: float          # 0 = uncapped
    burst_bytes: float
    tokens: float = field(init=False)
    last_refill: float = field(init=False)
    total_rx: int = 0
    total_tx: int = 0
    last_seen: float = field(init=False)

    def __post_init__(self) -> None:
        self.tokens = self.burst_bytes
        self.last_refill = time.monotonic()
        self.last_seen = self.last_refill

    def _refill(self) -> None:
        now = time.monotonic()
        elapsed = now - self.last_refill
        if elapsed <= 0:
            return
        if self.cap_bytes_per_s > 0:
            self.tokens = min(
                self.burst_bytes,
                self.tokens + elapsed * self.cap_bytes_per_s,
            )
        self.last_refill = now
        self.last_seen = now

    def consume(self, nbytes: int) -> bool:
        """
        Record nbytes of traffic. Returns True if within budget, False if
        over cap (caller should signal throttle to tc layer).
        """
        self.total_rx += nbytes
        self._refill()
        if self.cap_bytes_per_s <= 0:
            return True                     # uncapped premium
        if self.tokens >= nbytes:
            self.tokens -= nbytes
            return True
        self.tokens = 0                     # drain but don't go negative
        return False

    def snapshot(self) -> dict:
        self._refill()
        return {
            "cap_mbps": round(self.cap_bytes_per_s * 8 / 1e6, 2) if self.cap_bytes_per_s else None,
            "tokens_remaining_kb": round(self.tokens / 1024, 1),
            "total_rx_mb": round(self.total_rx / 1e6, 3),
            "total_tx_mb": round(self.total_tx / 1e6, 3),
        }


# ── manager ──────────────────────────────────────────────────────────────────

class TrafficManager:
    """
    Per-user bandwidth metering and tier-based traffic control.

    Thread-safe. No background threads — eviction is lazy (on next access).
    """

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._buckets: Dict[int, _Bucket] = {}

    # ── internal ─────────────────────────────────────────────────────────────

    def _make_bucket(self, tier: str) -> _Bucket:
        tier_l = (tier or "free").strip().lower()
        if tier_l in _PREMIUM_TIERS and _PREMIUM_CAP_MBPS == 0:
            return _Bucket(cap_bytes_per_s=0, burst_bytes=0)
        cap_mbps = _PREMIUM_CAP_MBPS if tier_l in _PREMIUM_TIERS else _FREE_CAP_MBPS
        burst_mbps = cap_mbps * 1.4         # allow 40% burst headroom
        return _Bucket(
            cap_bytes_per_s=cap_mbps * 1e6 / 8,
            burst_bytes=burst_mbps * 1e6 / 8,
        )

    def _evict_stale(self) -> None:
        """Remove buckets idle for more than _METER_TTL_S. Call while holding lock."""
        cutoff = time.monotonic() - _METER_TTL_S
        stale = [uid for uid, b in self._buckets.items() if b.last_seen < cutoff]
        for uid in stale:
            del self._buckets[uid]

    # ── public ───────────────────────────────────────────────────────────────

    def register(self, user_id: int, tier: str) -> None:
        """Create or replace a user's bucket (call on connect)."""
        bucket = self._make_bucket(tier)
        with self._lock:
            self._buckets[user_id] = bucket

    def record_bytes(self, user_id: int, rx: int = 0, tx: int = 0) -> bool:
        """
        Record traffic for a user. Returns False when the user is over cap
        (caller may signal the tc layer to enforce shaping).
        Auto-registers unknown users as free tier.
        """
        with self._lock:
            bucket = self._buckets.get(user_id)
            if bucket is None:
                bucket = self._make_bucket("free")
                self._buckets[user_id] = bucket
            bucket.total_tx += tx
            ok = bucket.consume(rx + tx)
        return ok

    def unregister(self, user_id: int) -> None:
        with self._lock:
            self._buckets.pop(user_id, None)

    def snapshot(self, user_id: int) -> Optional[dict]:
        with self._lock:
            b = self._buckets.get(user_id)
            return b.snapshot() if b else None

    def all_snapshots(self) -> dict:
        with self._lock:
            self._evict_stale()
            return {uid: b.snapshot() for uid, b in self._buckets.items()}

    # ── server-side tc shaping (best-effort, no-op if tc absent) ─────────────

    @staticmethod
    def apply_qos(
        iface: str,
        free_cidr: str,
        premium_cidr: str,
        free_mbps: Optional[str] = None,
        premium_mbps: Optional[str] = None,
        egress_iface: Optional[str] = None,
    ) -> bool:
        """
        Delegate tc/HTB setup to apply_vpn_qos_policy.sh.
        Returns True on success. Safe no-op if tc or script not available.
        No routing changes are made.
        """
        script = shutil.which("securewave-vpn-qos") or shutil.which("bash")
        qos_script = os.path.join(
            os.path.dirname(__file__), "..", "scripts", "ops", "apply_vpn_qos_policy.sh"
        )
        if not os.path.isfile(qos_script) or not shutil.which("tc"):
            logger.debug("tc or qos script not available; skipping server-side shaping")
            return False

        cmd = [
            "bash", qos_script,
            "--iface", iface,
            "--free-cidr", free_cidr,
            "--premium-cidr", premium_cidr,
        ]
        if free_mbps:
            cmd += ["--free-down", free_mbps]
        if premium_mbps:
            cmd += ["--premium-down", premium_mbps]

        try:
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=15)  # nosec B603
            if result.returncode != 0:
                logger.warning("qos setup failed: %s", result.stderr.strip())
                return False
            logger.info("qos applied: iface=%s free=%s premium=%s", iface, free_cidr, premium_cidr)
            return True
        except Exception as exc:
            logger.warning("qos apply error: %s", exc)
            return False


# ── module-level singleton ────────────────────────────────────────────────────

_manager: Optional[TrafficManager] = None
_manager_lock = threading.Lock()


def get_traffic_manager() -> TrafficManager:
    global _manager
    if _manager is None:
        with _manager_lock:
            if _manager is None:
                _manager = TrafficManager()
    return _manager
