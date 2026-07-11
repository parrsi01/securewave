"""Small, dependency-free safeguards for logs, audit records, and API errors.

These helpers intentionally operate at process boundaries.  They do not try to
classify business data; they remove values that must never be copied into logs,
audit evidence, or error responses.
"""

from __future__ import annotations

import re
from collections.abc import Mapping, Sequence
from typing import Any


REDACTED = "[redacted]"

_SENSITIVE_KEY_RE = re.compile(
    r"(?:pass(?:word)?|secret|token|authorization|cookie|credential|"
    r"api[_-]?key|private[_-]?key|preshared|fernet|config|vpn_key)",
    re.IGNORECASE,
)
_DESTINATION_KEY_RE = re.compile(
    r"(?:destination|endpoint|remote(?:_addr(?:ess)?)?|host|url|uri|"
    r"traffic[_-]?target)",
    re.IGNORECASE,
)
_INLINE_SECRET_RE = re.compile(
    r"(?P<key>password|pass|token|secret|authorization|cookie|api[_ -]?key|"
    r"private[_ -]?key|presharedkey|refresh[_ -]?token)"
    r"(?P<sep>\s*[:=]\s*|\s+)(?P<value>[^\s,;]+)",
    re.IGNORECASE,
)
_BEARER_RE = re.compile(r"(Bearer\s+)[A-Za-z0-9._~+/=-]+", re.IGNORECASE)
_WG_SECRET_RE = re.compile(r"((?:PrivateKey|PresharedKey)\s*=\s*)[^\s]+", re.IGNORECASE)
_PEM_BLOCK_RE = re.compile(
    r"-----BEGIN [^-]+-----.*?-----END [^-]+-----",
    re.IGNORECASE | re.DOTALL,
)


def is_sensitive_key(key: object) -> bool:
    """Return whether a mapping key must not retain its value."""
    return bool(_SENSITIVE_KEY_RE.search(str(key)))


def is_destination_key(key: object) -> bool:
    """Return whether a traffic destination should be excluded from evidence."""
    return bool(_DESTINATION_KEY_RE.search(str(key)))


def redact_text(value: object) -> str:
    """Redact common inline credentials from a free-form log/audit string."""
    text = str(value)
    text = _BEARER_RE.sub(r"\1" + REDACTED, text)
    text = _WG_SECRET_RE.sub(r"\1" + REDACTED, text)
    text = _PEM_BLOCK_RE.sub(REDACTED, text)
    return _INLINE_SECRET_RE.sub(
        lambda match: f"{match.group('key')}{match.group('sep')}{REDACTED}",
        text,
    )


def sanitize_for_evidence(value: Any, *, max_depth: int = 8) -> Any:
    """Return a recursively redacted, JSON-safe representation for audit data.

    Values under secret or destination-like keys are deliberately removed.  A
    bounded recursion depth prevents unexpected nested payloads from becoming
    a logging denial-of-service vector.
    """
    if max_depth < 0:
        return REDACTED
    if isinstance(value, Mapping):
        sanitized: dict[str, Any] = {}
        for key, item in value.items():
            key_text = str(key)
            if is_sensitive_key(key_text) or is_destination_key(key_text):
                sanitized[key_text] = REDACTED
            else:
                sanitized[key_text] = sanitize_for_evidence(item, max_depth=max_depth - 1)
        return sanitized
    if isinstance(value, (str, bytes)):
        return redact_text(value.decode(errors="replace") if isinstance(value, bytes) else value)
    if isinstance(value, Sequence) and not isinstance(value, (str, bytes, bytearray)):
        return [sanitize_for_evidence(item, max_depth=max_depth - 1) for item in value]
    if value is None or isinstance(value, (bool, int, float)):
        return value
    return redact_text(value)


def safe_validation_errors(errors: Sequence[Mapping[str, Any]]) -> list[dict[str, Any]]:
    """Normalize Pydantic errors without reflecting invalid submitted values."""
    normalized: list[dict[str, Any]] = []
    for error in errors:
        location = error.get("loc", ())
        if not isinstance(location, (list, tuple)):
            location = ("body",)
        normalized.append(
            {
                "loc": [str(part) for part in location],
                "type": str(error.get("type", "invalid_request")),
                "message": "Invalid value",
            }
        )
    return normalized
