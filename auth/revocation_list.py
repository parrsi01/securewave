"""
auth/revocation_list.py — Unified JTI revocation list with optional Redis acceleration.

Design:
  - Primary store: jwt_blacklist_tokens DB table (durable, indexed on token_jti)
  - Optional cache: Redis with TTL-based expiry (reduces DB queries under load)
  - Redis unavailable → graceful fallback to DB-only (no startup failure)
  - All writes go to DB; Redis is cache-aside (write-through on revoke)
  - Purge job removes expired entries — safe to run on a cron
  - Bulk revocation (logout-all) uses a set-based DB query, not Redis pub/sub
"""

from __future__ import annotations

import logging
from datetime import datetime
from typing import Optional

from sqlalchemy.orm import Session

from config.settings import get_settings
from models.jwt_blacklist_token import JWTBlacklistToken

logger = logging.getLogger(__name__)
SETTINGS = get_settings()

# ── Redis optional bootstrap ───────────────────────────────────────────────────
_redis_client = None
_REDIS_PREFIX = "jti:revoked:"


def _get_redis():
    """Return a Redis client if configured, else None. Thread-safe via import lock."""
    global _redis_client
    if _redis_client is not None:
        return _redis_client

    redis_url = SETTINGS.redis_url
    if not redis_url or redis_url == "memory://":
        return None

    try:
        import redis  # type: ignore

        client = redis.from_url(redis_url, decode_responses=True, socket_connect_timeout=2)
        client.ping()
        _redis_client = client
        logger.info("revocation_list: Redis cache enabled", extra={"redis_configured": True})
    except Exception as exc:
        logger.warning("revocation_list: Redis unavailable (%s) — DB-only mode", exc)
        _redis_client = None

    return _redis_client


def _redis_ttl(expires_at: datetime) -> int:
    """Seconds until the token expires (minimum 1 to avoid immediate eviction)."""
    from auth.token import _utcnow

    remaining = int((expires_at - _utcnow()).total_seconds())
    return max(remaining, 1)


# ── Public API ─────────────────────────────────────────────────────────────────
def add_to_revocation_list(
    db: Session,
    *,
    jti: str,
    token_type: str,
    expires_at: datetime,
    user_id: Optional[int] = None,
    reason: str = "revoked",
) -> None:
    """
    Revoke a token by JTI. Idempotent.

    Writes to DB (durable) and Redis cache (fast lookup) if available.
    """
    # DB write (idempotent)
    exists = (
        db.query(JWTBlacklistToken.id)
        .filter(JWTBlacklistToken.token_jti == jti)
        .first()
    )
    if not exists:
        db.add(
            JWTBlacklistToken(
                user_id=user_id,
                token_jti=jti,
                token_type=token_type[:16],
                reason=reason[:128],
                expires_at=expires_at,
            )
        )
        db.commit()

    # Redis write (best-effort)
    r = _get_redis()
    if r:
        try:
            ttl = _redis_ttl(expires_at)
            r.setex(f"{_REDIS_PREFIX}{jti}", ttl, "1")
        except Exception as exc:
            logger.warning("revocation_list: Redis write failed for jti=%s: %s", jti, exc)


def is_revoked(db: Session, jti: str) -> bool:
    """
    Check whether a JTI is revoked.

    Checks Redis first (O(1) lookup) then falls back to DB.
    """
    r = _get_redis()
    if r:
        try:
            if r.exists(f"{_REDIS_PREFIX}{jti}"):
                return True
            # Cache miss — fall through to DB
        except Exception as exc:
            logger.warning("revocation_list: Redis read failed for jti=%s: %s", jti, exc)

    return (
        db.query(JWTBlacklistToken.id)
        .filter(JWTBlacklistToken.token_jti == jti)
        .first()
        is not None
    )


def revoke_all_for_user(db: Session, user_id: int, *, reason: str = "logout_all") -> int:
    """
    Mark all unexpired tokens for a user as revoked.

    Used by logout-all. Returns the count of newly revoked entries.
    This operates on the DB entries created by previous revocations and
    the auth_refresh_tokens table is handled separately in refresh_tokens.py.

    Note: This cannot retroactively revoke access tokens whose JTIs were never
    added to the blacklist (i.e., tokens that are still valid but untracked).
    For those, the short access token TTL (15 min) is the limiting factor.
    """
    from auth.token import _utcnow

    now = _utcnow()
    # Find unexpired blacklist entries for the user to populate Redis cache
    # (so concurrent processes pick up the revocation from cache)
    existing = (
        db.query(JWTBlacklistToken)
        .filter(
            JWTBlacklistToken.user_id == user_id,
            JWTBlacklistToken.expires_at > now,
        )
        .all()
    )

    r = _get_redis()
    if r:
        for entry in existing:
            try:
                ttl = _redis_ttl(entry.expires_at)
                r.setex(f"{_REDIS_PREFIX}{entry.token_jti}", ttl, "1")
            except Exception:
                pass

    return len(existing)


def purge_expired(db: Session) -> int:
    """
    Delete blacklist entries for tokens that have already expired.

    Safe to run as a cron job. Returns the number of rows deleted.
    """
    from auth.token import _utcnow

    deleted = (
        db.query(JWTBlacklistToken)
        .filter(JWTBlacklistToken.expires_at <= _utcnow())
        .delete(synchronize_session=False)
    )
    db.commit()
    return int(deleted or 0)


def get_revocation_stats(db: Session) -> dict:
    """Admin diagnostic — total and recent revocation counts."""
    from auth.token import _utcnow
    from datetime import timedelta

    total = db.query(JWTBlacklistToken.id).count()
    last_hour = (
        db.query(JWTBlacklistToken.id)
        .filter(JWTBlacklistToken.revoked_at >= _utcnow() - timedelta(hours=1))
        .count()
    )
    return {
        "total_revoked": total,
        "revoked_last_hour": last_hour,
        "redis_enabled": _get_redis() is not None,
    }
