import io
import json
import logging

from utils.structured_logging import (
    StructuredJsonFormatter,
    StructuredLogFilter,
    bind_request_context,
    log_event,
    reset_request_context,
    sanitize_value,
)


def _build_logger(stream: io.StringIO) -> logging.Logger:
    logger = logging.getLogger("tests.structured_logging")
    logger.handlers = []
    logger.propagate = False
    logger.setLevel(logging.INFO)
    handler = logging.StreamHandler(stream)
    handler.setFormatter(StructuredJsonFormatter())
    handler.addFilter(StructuredLogFilter())
    logger.addHandler(handler)
    return logger


def test_sanitize_value_redacts_sensitive_fields():
    assert sanitize_value("password", "super-secret") == "[redacted]"
    assert sanitize_value("access_token", "abc123") == "[redacted]"
    assert sanitize_value("nested", {"refresh_token": "abc123"}) == {
        "refresh_token": "[redacted]"
    }


def test_structured_log_includes_request_context_and_sanitizes_payload():
    stream = io.StringIO()
    logger = _build_logger(stream)
    tokens = bind_request_context("req-123", user_id=42)
    try:
        log_event(
            logger,
            "authentication",
            action="login",
            password="do-not-log",
            access_token="do-not-log",
        )
    finally:
        reset_request_context(tokens)

    payload = json.loads(stream.getvalue().strip())
    assert payload["event"] == "authentication"
    assert payload["action"] == "login"
    assert payload["request_id"] == "req-123"
    assert payload["user_id"] == 42
    assert payload["password"] == "[redacted]"
    assert payload["access_token"] == "[redacted]"


def test_structured_log_redacts_bearer_tokens_in_message():
    stream = io.StringIO()
    logger = _build_logger(stream)
    logger.info("Authorization failed for Bearer abc.def.ghi")
    payload = json.loads(stream.getvalue().strip())
    assert payload["message"] == "Authorization failed for Bearer [redacted]"
