from __future__ import annotations

import json
import logging
import threading
import time
from datetime import datetime, timezone
from functools import lru_cache
from typing import Any, Optional, Protocol

import redis

from config.settings import get_settings


logger = logging.getLogger(__name__)
SETTINGS = get_settings()
_KEY_PREFIX = "securewave:security"


class SecurityStateBackend(Protocol):
    def incr(self, key: str, *, ttl_seconds: int) -> int: ...
    def set_json(self, key: str, payload: dict[str, Any], *, ttl_seconds: int) -> None: ...
    def get_json(self, key: str) -> Optional[dict[str, Any]]: ...
    def exists(self, key: str) -> bool: ...
    def delete(self, key: str) -> None: ...
    def delete_prefix(self, prefix: str) -> int: ...


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _ttl_until(expires_at: datetime | None, *, default_seconds: int = 3600) -> int:
    if expires_at is None:
        return max(1, default_seconds)
    if expires_at.tzinfo is None:
        expires_at = expires_at.replace(tzinfo=timezone.utc)
    ttl = int((expires_at - _utcnow()).total_seconds())
    return max(1, ttl)


class _InMemorySecurityStateBackend:
    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._data: dict[str, tuple[Any, float]] = {}

    def _purge_expired(self, *, now: float | None = None) -> None:
        current = time.time() if now is None else now
        expired = [key for key, (_, expires_at) in self._data.items() if expires_at <= current]
        for key in expired:
            self._data.pop(key, None)

    def incr(self, key: str, *, ttl_seconds: int) -> int:
        with self._lock:
            now = time.time()
            self._purge_expired(now=now)
            current_value, expires_at = self._data.get(key, (0, now + ttl_seconds))
            if expires_at <= now:
                current_value = 0
                expires_at = now + ttl_seconds
            current_value = int(current_value) + 1
            self._data[key] = (current_value, expires_at)
            return current_value

    def set_json(self, key: str, payload: dict[str, Any], *, ttl_seconds: int) -> None:
        with self._lock:
            expires_at = time.time() + ttl_seconds
            self._data[key] = (json.dumps(payload), expires_at)

    def get_json(self, key: str) -> Optional[dict[str, Any]]:
        with self._lock:
            self._purge_expired()
            stored = self._data.get(key)
            if stored is None:
                return None
            raw, _expires_at = stored
            if not isinstance(raw, str):
                return None
            try:
                return json.loads(raw)
            except json.JSONDecodeError:
                return None

    def exists(self, key: str) -> bool:
        with self._lock:
            self._purge_expired()
            return key in self._data

    def delete(self, key: str) -> None:
        with self._lock:
            self._data.pop(key, None)

    def delete_prefix(self, prefix: str) -> int:
        with self._lock:
            keys = [key for key in self._data if key.startswith(prefix)]
            for key in keys:
                self._data.pop(key, None)
            return len(keys)


class _RedisSecurityStateBackend:
    def __init__(self, client: redis.Redis) -> None:
        self._client = client

    def incr(self, key: str, *, ttl_seconds: int) -> int:
        value = int(self._client.incr(key))
        if value == 1:
            self._client.expire(key, ttl_seconds)
        return value

    def set_json(self, key: str, payload: dict[str, Any], *, ttl_seconds: int) -> None:
        self._client.setex(key, ttl_seconds, json.dumps(payload, separators=(",", ":"), default=str))

    def get_json(self, key: str) -> Optional[dict[str, Any]]:
        raw = self._client.get(key)
        if raw is None:
            return None
        try:
            return json.loads(raw)
        except json.JSONDecodeError:
            logger.warning("Invalid JSON cached in shared security state", extra={"cache_key": key})
            return None

    def exists(self, key: str) -> bool:
        return bool(self._client.exists(key))

    def delete(self, key: str) -> None:
        self._client.delete(key)

    def delete_prefix(self, prefix: str) -> int:
        deleted = 0
        for key in self._client.scan_iter(match=f"{prefix}*"):
            deleted += int(self._client.delete(key) or 0)
        return deleted


_memory_backend = _InMemorySecurityStateBackend()
_override_backend: Optional[SecurityStateBackend] = None


def _redis_enabled() -> bool:
    return bool(SETTINGS.redis_url and SETTINGS.redis_url != "memory://")


@lru_cache(maxsize=1)
def _redis_backend() -> Optional[_RedisSecurityStateBackend]:
    if not _redis_enabled():
        return None
    client = redis.Redis.from_url(
        SETTINGS.redis_url,
        decode_responses=True,
        socket_timeout=2,
        socket_connect_timeout=2,
        health_check_interval=30,
    )
    client.ping()
    return _RedisSecurityStateBackend(client)


def _backend() -> SecurityStateBackend:
    if _override_backend is not None:
        return _override_backend
    try:
        redis_backend = _redis_backend()
    except Exception as exc:
        logger.warning(
            "Falling back to in-memory shared security state",
            extra={"reason": str(exc), "redis_configured": _redis_enabled()},
        )
        redis_backend = None
    return redis_backend or _memory_backend


def set_shared_security_backend_for_tests(backend: Optional[SecurityStateBackend]) -> None:
    global _override_backend
    _override_backend = backend


def build_in_memory_security_state_backend() -> SecurityStateBackend:
    return _InMemorySecurityStateBackend()


def clear_shared_security_state_for_tests() -> None:
    prefix = f"{_KEY_PREFIX}:"
    _memory_backend.delete_prefix(prefix)
    backend = _override_backend
    if backend is not None:
        backend.delete_prefix(prefix)
    if _redis_enabled():
        try:
            redis_backend = _redis_backend()
        except Exception:
            redis_backend = None
        if redis_backend is not None:
            redis_backend.delete_prefix(prefix)


def _key(*parts: str) -> str:
    return ":".join((_KEY_PREFIX, *parts))


def increment_rate_limit_window(scope: str, subject: str, *, window_seconds: int) -> int:
    normalized_scope = scope.strip().replace(" ", "_")
    normalized_subject = subject.strip() or "unknown"
    return _backend().incr(_key("rate_limit", normalized_scope, normalized_subject), ttl_seconds=window_seconds)


def remember_revoked_token(
    *,
    token_jti: str,
    token_type: str,
    expires_at: datetime,
    user_id: Optional[int],
    reason: Optional[str],
) -> None:
    _backend().set_json(
        _key("revoked_token", token_jti),
        {
            "token_jti": token_jti,
            "token_type": token_type,
            "user_id": user_id,
            "reason": reason,
            "expires_at": expires_at.isoformat(),
        },
        ttl_seconds=_ttl_until(expires_at),
    )


def is_token_revoked(token_jti: str) -> bool:
    return _backend().exists(_key("revoked_token", token_jti))


def register_refresh_session(
    *,
    token_jti: str,
    user_id: int,
    expires_at: datetime,
    issued_at: Optional[datetime] = None,
    ip_address: Optional[str] = None,
    user_agent: Optional[str] = None,
    revoked_at: Optional[datetime] = None,
    replaced_by_jti: Optional[str] = None,
) -> None:
    payload = {
        "token_jti": token_jti,
        "user_id": user_id,
        "issued_at": (issued_at or _utcnow()).isoformat(),
        "expires_at": expires_at.isoformat(),
        "ip_address": ip_address,
        "user_agent": user_agent,
        "revoked_at": revoked_at.isoformat() if revoked_at else None,
        "replaced_by_jti": replaced_by_jti,
    }
    _backend().set_json(
        _key("refresh_session", token_jti),
        payload,
        ttl_seconds=_ttl_until(expires_at),
    )


def get_refresh_session(token_jti: str) -> Optional[dict[str, Any]]:
    return _backend().get_json(_key("refresh_session", token_jti))


def revoke_refresh_session(
    *,
    token_jti: str,
    expires_at: datetime,
    user_id: Optional[int] = None,
    revoked_at: Optional[datetime] = None,
    replaced_by_jti: Optional[str] = None,
) -> None:
    existing = get_refresh_session(token_jti) or {}
    register_refresh_session(
        token_jti=token_jti,
        user_id=int(existing.get("user_id") or user_id or 0),
        expires_at=expires_at,
        issued_at=_parse_iso_datetime(existing.get("issued_at")),
        ip_address=existing.get("ip_address"),
        user_agent=existing.get("user_agent"),
        revoked_at=revoked_at or _utcnow(),
        replaced_by_jti=replaced_by_jti or existing.get("replaced_by_jti"),
    )


def _parse_iso_datetime(value: Any) -> Optional[datetime]:
    if not isinstance(value, str) or not value:
        return None
    try:
        parsed = datetime.fromisoformat(value)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed
