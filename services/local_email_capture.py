"""Explicit non-production email capture for Codex-local runs.

This provider is deliberately separate from SMTP, SendGrid, and SES.  It is
usable only when ``ENVIRONMENT=codex-local`` and writes redacted evidence to an
operator-selected directory outside the repository.  It never opens a socket
and never persists the original recipient, message URL, password, or token.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import secrets
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from utils.sensitive_data import redact_text


EMAIL_RE = re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}")
URL_RE = re.compile(r"https?://[^\s'\"]+", re.IGNORECASE)
TOKEN_RE = re.compile(
    r"(?i)\b(?:token|code|key|secret|password|passwd|authorization|cookie)\b"
    r"\s*[:=]\s*[^\s,;<>]+"
)


class LocalEmailCaptureError(RuntimeError):
    """Raised when the explicit local capture contract is not usable."""


def _capture_root() -> Path:
    if os.getenv("ENVIRONMENT", "").strip().lower() != "codex-local":
        raise LocalEmailCaptureError("local email capture requires ENVIRONMENT=codex-local")

    raw = os.getenv("SECUREWAVE_LOCAL_EMAIL_EVIDENCE_DIR", "").strip()
    if not raw:
        raise LocalEmailCaptureError(
            "SECUREWAVE_LOCAL_EMAIL_EVIDENCE_DIR is required for local email capture"
        )

    root = Path(raw).expanduser().resolve()
    repository_root = Path(__file__).resolve().parents[1]
    try:
        root.relative_to(repository_root)
    except ValueError:
        return root
    raise LocalEmailCaptureError("local email evidence must be outside the repository")


def _redact_message(value: str) -> str:
    # Replace complete URLs before generic ``token=...`` redaction so the
    # generic expression cannot consume the closing quote of an HTML
    # attribute.  The output remains useful for local layout inspection while
    # preserving the original markup boundaries.
    text = URL_RE.sub("[redacted-url]", value)
    text = EMAIL_RE.sub("[redacted-email]", text)
    text = TOKEN_RE.sub("[redacted-secret]", text)
    return redact_text(text)


def capture_email(
    *,
    to_email: str,
    subject: str,
    html_content: str,
    text_content: str | None = None,
    provider_name: str = "local_capture",
    metadata: dict[str, Any] | None = None,
) -> bool:
    """Write one redacted local email event and return whether it was stored."""

    root = _capture_root()
    root.mkdir(parents=True, exist_ok=True)
    try:
        os.chmod(root, 0o700)
    except OSError:
        pass

    redacted_html = _redact_message(html_content)
    redacted_text = _redact_message(text_content or "")
    payload = {
        "captured_at_utc": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "provider": provider_name,
        "recipient": "[redacted-email]",
        "subject": _redact_message(subject),
        "html_content": redacted_html,
        "text_content": redacted_text,
        "metadata": {"present": bool(metadata)},
        "content_sha256": hashlib.sha256(
            (redacted_html + "\n" + redacted_text).encode("utf-8")
        ).hexdigest(),
    }
    destination = root / f"email-{secrets.token_hex(12)}.json"
    destination.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    try:
        os.chmod(destination, 0o600)
    except OSError:
        pass
    return True


__all__ = ["LocalEmailCaptureError", "capture_email"]
