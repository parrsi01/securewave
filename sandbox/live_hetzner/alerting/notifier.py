#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import smtplib
import ssl
from dataclasses import dataclass
from email.message import EmailMessage
from typing import Any, Optional
from urllib import request as urlrequest


@dataclass(frozen=True)
class NotifyResult:
    ok: bool
    channel: str
    detail: str


def _bool_env(name: str, default: bool = False) -> bool:
    raw = os.getenv(name)
    if raw is None:
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on"}


def notify_via_webhook(*, title: str, text: str, payload: dict[str, Any]) -> NotifyResult:
    url = (os.getenv("NOTIFY_WEBHOOK_URL") or "").strip()
    if not url:
        return NotifyResult(ok=False, channel="webhook", detail="NOTIFY_WEBHOOK_URL not set")

    body = json.dumps({"title": title, "text": text, "payload": payload}, separators=(",", ":")).encode("utf-8")
    req = urlrequest.Request(
        url=url,
        method="POST",
        data=body,
        headers={"Content-Type": "application/json", "User-Agent": "securewave-alerting/1.0"},
    )
    try:
        with urlrequest.urlopen(req, timeout=10) as resp:
            if 200 <= int(resp.status) < 300:
                return NotifyResult(ok=True, channel="webhook", detail=f"status={resp.status}")
            return NotifyResult(ok=False, channel="webhook", detail=f"status={resp.status}")
    except Exception as exc:
        return NotifyResult(ok=False, channel="webhook", detail=str(exc))


def notify_via_smtp(*, subject: str, body_text: str) -> NotifyResult:
    host = (os.getenv("SMTP_HOST") or "").strip()
    port = int((os.getenv("SMTP_PORT") or "587").strip() or "587")
    user = (os.getenv("SMTP_USER") or "").strip()
    password = (os.getenv("SMTP_PASS") or "").strip()
    mail_from = (os.getenv("SMTP_FROM") or user or "").strip()
    mail_to = (os.getenv("ALERT_EMAIL_TO") or "").strip()
    use_tls = _bool_env("SMTP_TLS", True)

    if not host or not mail_from or not mail_to:
        return NotifyResult(ok=False, channel="smtp", detail="SMTP_HOST/SMTP_FROM/ALERT_EMAIL_TO not set")

    msg = EmailMessage()
    msg["Subject"] = subject
    msg["From"] = mail_from
    msg["To"] = mail_to
    msg.set_content(body_text)

    try:
        if use_tls:
            context = ssl.create_default_context()
            with smtplib.SMTP(host=host, port=port, timeout=10) as smtp:
                smtp.ehlo()
                smtp.starttls(context=context)
                smtp.ehlo()
                if user and password:
                    smtp.login(user, password)
                smtp.send_message(msg)
        else:
            with smtplib.SMTP(host=host, port=port, timeout=10) as smtp:
                if user and password:
                    smtp.login(user, password)
                smtp.send_message(msg)
        return NotifyResult(ok=True, channel="smtp", detail="sent")
    except Exception as exc:
        return NotifyResult(ok=False, channel="smtp", detail=str(exc))


def notify(*, title: str, text: str, payload: dict[str, Any]) -> list[NotifyResult]:
    """
    Send notifications over configured channels.

    Channels:
    - Webhook: NOTIFY_WEBHOOK_URL
    - SMTP email: SMTP_* + ALERT_EMAIL_TO
    """
    results: list[NotifyResult] = []

    if (os.getenv("NOTIFY_WEBHOOK_URL") or "").strip():
        results.append(notify_via_webhook(title=title, text=text, payload=payload))

    if (os.getenv("SMTP_HOST") or "").strip() and (os.getenv("ALERT_EMAIL_TO") or "").strip():
        results.append(notify_via_smtp(subject=title, body_text=text + "\n\n" + json.dumps(payload, indent=2)))

    if not results:
        results.append(NotifyResult(ok=False, channel="none", detail="no notifier configured"))
    return results

