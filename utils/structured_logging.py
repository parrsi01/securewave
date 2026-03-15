from __future__ import annotations

import contextvars
import json
import logging
import re
import time
from logging.handlers import RotatingFileHandler
from pathlib import Path
from typing import Any, Iterable, Mapping


LOG_PATH = Path("/var/log/securewave/backend.log")
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
    "token",
    "wg_key",
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
_STRING_REDACTIONS = (
    (re.compile(r"(Bearer\s+)[A-Za-z0-9._\-]+", re.IGNORECASE), r"\1[redacted]"),
    (re.compile(r"(PrivateKey\s*=\s*)([^\s]+)", re.IGNORECASE), r"\1[redacted]"),
    (re.compile(r"(PresharedKey\s*=\s*)([^\s]+)", re.IGNORECASE), r"\1[redacted]"),
    (re.compile(r"((?:access|refresh|csrf)?_?token=)([^&\s]+)", re.IGNORECASE), r"\1[redacted]"),
    (re.compile(r"((?:password|secret|api_key)=)([^&\s]+)", re.IGNORECASE), r"\1[redacted]"),
)


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
        LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
        handlers.append(
            _build_handler(
                RotatingFileHandler(
                    LOG_PATH,
                    maxBytes=10 * 1024 * 1024,
                    backupCount=5,
                    encoding="utf-8",
                )
            )
        )
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
