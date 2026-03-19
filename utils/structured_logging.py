from __future__ import annotations

import contextvars
import hashlib
import json
import logging
import os
import re
import time
from logging.handlers import RotatingFileHandler
from pathlib import Path
from typing import Any, Iterable, Mapping

from config.security_config import enforce_permission_policy


_DEFAULT_LOG_DIR = Path.home() / ".local" / "state" / "securewave" / "logs"
LOG_DIR = Path(os.getenv("SECUREWAVE_LOG_DIR", str(_DEFAULT_LOG_DIR))).expanduser()
LOG_PATH = LOG_DIR / os.getenv("SECUREWAVE_LOG_FILE", "backend.log")
request_id_ctx = contextvars.ContextVar("request_id", default="-")
user_id_ctx = contextvars.ContextVar("user_id", default=None)

_REDACTED = "[redacted]"
_SENSITIVE_FIELD_NAMES = {
    "access_token",
    "api_key",
    "authorization",
    "cookie",
    "csrf_token",
    "password",
    "password_confirm",
    "private_key",
    "preshared_key",
    "refresh_token",
    "secret",
    "stripe_webhook_secret",
    "token",
    "wg_key",
    "wg_private_key_encrypted",
}
_SENSITIVE_FIELD_SUFFIXES = (
    "_token",
    "_secret",
    "_password",
    "_private_key",
    "_preshared_key",
    "_api_key",
)
_STANDARD_LOG_ATTRS = set(logging.makeLogRecord({}).__dict__.keys())
_ANSI_ESCAPE_RE = re.compile(r"\x1b\[[0-9;]*[mGKHFABCDEJsu]|\x1b[()][AB012]")
_STRING_REDACTIONS = (
    (re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"), "[redacted-email]"),
    (re.compile(r"(Bearer\s+)[A-Za-z0-9._\-]+", re.IGNORECASE), r"\1[redacted]"),
    (re.compile(r"\bsk_(?:live|test)_[A-Za-z0-9]+\b"), "[redacted-stripe-secret]"),
    (re.compile(r"\bwhsec_[A-Za-z0-9]+\b"), "[redacted-stripe-webhook-secret]"),
    (re.compile(r"(PrivateKey\s*=\s*)([^\s]+)", re.IGNORECASE), r"\1[redacted]"),
    (re.compile(r"(PresharedKey\s*=\s*)([^\s]+)", re.IGNORECASE), r"\1[redacted]"),
    (re.compile(r"((?:JWT_SECRET|SECRET_KEY|ACCESS_TOKEN_SECRET|REFRESH_TOKEN_SECRET)=)([^&\s]+)", re.IGNORECASE), r"\1[redacted]"),
    # Redact NEW_KEY='...' patterns used in SSH key rotation commands
    (re.compile(r"(NEW_KEY\s*=\s*')[^']+'", re.IGNORECASE), r"\1[redacted]'"),
    (re.compile(r"((?:access|refresh|csrf)?_?token=)([^&\s]+)", re.IGNORECASE), r"\1[redacted]"),
    (re.compile(r"((?:password|secret|api_key)=)([^&\s]+)", re.IGNORECASE), r"\1[redacted]"),
)

_security_logger = logging.getLogger("securewave.security")


def bind_request_context(request_id: str, *, user_id: Any = None) -> tuple[contextvars.Token, contextvars.Token]:
    return (
        request_id_ctx.set(request_id),
        user_id_ctx.set(user_id),
    )


def reset_request_context(tokens: tuple[contextvars.Token, contextvars.Token]) -> None:
    request_id_ctx.reset(tokens[0])
    user_id_ctx.reset(tokens[1])


def bind_user_id(user_id: Any) -> contextvars.Token:
    return user_id_ctx.set(user_id)


def reset_user_id(token: contextvars.Token) -> None:
    user_id_ctx.reset(token)


def get_request_id() -> str:
    return request_id_ctx.get("-")


def get_user_id() -> Any:
    return user_id_ctx.get(None)


def _is_sensitive_key(key: str) -> bool:
    lowered = key.lower()
    if lowered in {"token_type"}:
        return False
    if lowered in _SENSITIVE_FIELD_NAMES:
        return True
    return any(lowered.endswith(suffix) for suffix in _SENSITIVE_FIELD_SUFFIXES)


def _sanitize_string(value: str) -> str:
    sanitized = value
    for pattern, replacement in _STRING_REDACTIONS:
        sanitized = pattern.sub(replacement, sanitized)
    return sanitized


def sanitize_value(key: str, value: Any) -> Any:
    if _is_sensitive_key(key):
        return _REDACTED
    if value is None or isinstance(value, (bool, int, float)):
        return value
    if isinstance(value, str):
        return _sanitize_string(value)
    if isinstance(value, bytes):
        return f"<bytes:{len(value)}>"
    if isinstance(value, Path):
        return str(value)
    if isinstance(value, Mapping):
        return {
            nested_key: sanitize_value(str(nested_key), nested_value)
            for nested_key, nested_value in value.items()
        }
    if isinstance(value, (list, tuple, set, frozenset)):
        return [sanitize_value(key, item) for item in value]
    return str(value)


class StructuredLogFilter(logging.Filter):
    def filter(self, record: logging.LogRecord) -> bool:
        if not getattr(record, "request_id", None):
            record.request_id = get_request_id()
        if getattr(record, "user_id", None) is None:
            record.user_id = get_user_id()

        record.msg = sanitize_value("message", record.getMessage())
        record.args = ()
        for key, value in list(record.__dict__.items()):
            if key in _STANDARD_LOG_ATTRS or key in {"request_id", "user_id", "message"}:
                continue
            record.__dict__[key] = sanitize_value(key, value)
        return True


class StructuredJsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        payload = {
            "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(record.created)),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
            "request_id": getattr(record, "request_id", get_request_id()),
        }
        user_id = getattr(record, "user_id", get_user_id())
        if user_id is not None:
            payload["user_id"] = user_id

        for key, value in record.__dict__.items():
            if key in _STANDARD_LOG_ATTRS or key in {"message", "request_id", "user_id"}:
                continue
            payload[key] = sanitize_value(key, value)

        if record.exc_info:
            payload["exception"] = self.formatException(record.exc_info)

        return json.dumps(payload, default=str, separators=(",", ":"))


def _build_handler(handler: logging.Handler) -> logging.Handler:
    handler.setFormatter(StructuredJsonFormatter())
    handler.addFilter(StructuredLogFilter())
    return handler


def configure_structured_logging(log_level: str) -> None:
    handlers: list[logging.Handler] = [_build_handler(logging.StreamHandler())]
    setup_warnings: list[str] = []

    try:
        LOG_DIR.mkdir(parents=True, exist_ok=True)
        permission_result = enforce_permission_policy((LOG_DIR,), dir_mode=0o700)
        setup_warnings.extend(permission_result.warnings)
        file_handler = RotatingFileHandler(
            LOG_PATH,
            maxBytes=10 * 1024 * 1024,
            backupCount=5,
            encoding="utf-8",
        )
        permission_result = enforce_permission_policy((LOG_PATH,), file_mode=0o600)
        setup_warnings.extend(permission_result.warnings)
        handlers.append(_build_handler(file_handler))
    except OSError as exc:
        setup_warnings.append(f"File logging unavailable at {LOG_PATH}: {exc}")

    logging.basicConfig(level=log_level, handlers=handlers, force=True)
    logging.getLogger("httpx").setLevel(logging.WARNING)
    logging.getLogger("httpcore").setLevel(logging.WARNING)
    logging.getLogger("uvicorn.access").setLevel(logging.WARNING)

    if setup_warnings:
        logger = logging.getLogger(__name__)
        for warning in setup_warnings:
            logger.warning(warning, extra={"event": "logging_configuration"})


def log_event(
    logger: logging.Logger,
    event: str,
    *,
    level: int = logging.INFO,
    message: str | None = None,
    **fields: Any,
) -> None:
    logger.log(level, message or event, extra={"event": event, **fields})


def structured_extras(record: logging.LogRecord) -> dict[str, Any]:
    return {
        key: value
        for key, value in record.__dict__.items()
        if key not in _STANDARD_LOG_ATTRS
    }


def sanitize_for_log(value: str, max_len: int = 500) -> str:
    if not isinstance(value, str):
        value = str(value)
    value = _ANSI_ESCAPE_RE.sub("", value)
    value = value.replace("\r", "\\r").replace("\n", "\\n").replace("\x00", "\\x00")
    if len(value) > max_len:
        value = value[:max_len] + "[truncated]"
    return value


def _hash_email(email: str) -> str:
    return "sha256:" + hashlib.sha256(email.lower().encode()).hexdigest()[:16]


def log_security_event(
    event_type: str,
    severity: str,
    **fields: Any,
) -> None:
    _security_logger.warning(
        event_type,
        extra={
            "event": event_type,
            "severity": severity,
            **fields,
        },
    )


def log_auth_failure(
    reason: str,
    ip_address: str | None,
    email_hint: str | None,
    **extra: Any,
) -> None:
    log_security_event(
        "auth_failure",
        "medium",
        reason=reason,
        ip_address=sanitize_for_log(ip_address or "unknown", 64),
        email_hint=_hash_email(email_hint) if email_hint else None,
        **extra,
    )


def log_admin_action(
    action: str,
    user_id: Any,
    ip_address: str | None,
    result: str,
    **extra: Any,
) -> None:
    log_security_event(
        "admin_action",
        "low" if result == "success" else "medium",
        action=action,
        user_id=user_id,
        ip_address=sanitize_for_log(ip_address or "unknown", 64),
        result=result,
        **extra,
    )
