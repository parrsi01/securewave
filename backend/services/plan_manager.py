from __future__ import annotations

from dataclasses import dataclass

_FREE = {"free", "basic"}
_PREMIUM = {"premium", "pro", "ultra", "plus"}


@dataclass(frozen=True)
class PlanDecision:
    user_id: int
    tier: str
    is_free: bool
    is_premium: bool


class PlanManager:
    @staticmethod
    def normalize_tier(raw_tier: str | None) -> str:
        tier = (raw_tier or "free").strip().lower()
        if tier in _PREMIUM:
            return "premium"
        if tier in _FREE:
            return "free"
        return "free"

    def resolve(self, user_id: int, raw_tier: str | None) -> PlanDecision:
        tier = self.normalize_tier(raw_tier)
        return PlanDecision(
            user_id=int(user_id),
            tier=tier,
            is_free=tier == "free",
            is_premium=tier == "premium",
        )


_plan_manager: PlanManager | None = None


def get_plan_manager() -> PlanManager:
    global _plan_manager
    if _plan_manager is None:
        _plan_manager = PlanManager()
    return _plan_manager
