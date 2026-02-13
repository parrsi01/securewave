#!/usr/bin/env python3
"""
System audit probe for RSS/FD/thread leak detection during live validation.

Writes artifacts under:
- artifacts/system_audit/
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional

import httpx


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _ensure_dir(path: Path) -> Path:
    path.mkdir(parents=True, exist_ok=True)
    return path


def _atomic_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(content, encoding="utf-8")
    tmp.replace(path)


def _post_json(client: httpx.Client, url: str, payload: dict, *, timeout: float) -> httpx.Response:
    return client.post(url, json=payload, timeout=timeout)


def _get(client: httpx.Client, url: str, *, headers: Optional[dict] = None, timeout: float) -> httpx.Response:
    return client.get(url, headers=headers or {}, timeout=timeout)


def _register_or_login(
    client: httpx.Client,
    *,
    api_base_url: str,
    email: str,
    password: str,
    timeout_seconds: float,
) -> tuple[bool, str, dict[str, Any]]:
    meta: dict[str, Any] = {"email": email}
    try:
        reg = _post_json(
            client,
            f"{api_base_url}/api/auth/register",
            {"email": email, "password": password, "password_confirm": password},
            timeout=timeout_seconds,
        )
        meta["register_status"] = reg.status_code
    except Exception as exc:
        meta["register_error"] = str(exc)

    try:
        login = _post_json(
            client,
            f"{api_base_url}/api/auth/login",
            {"email": email, "password": password},
            timeout=timeout_seconds,
        )
        meta["login_status"] = login.status_code
        if login.status_code != 200:
            meta["login_body"] = login.text[:5000]
            return False, "", meta
        body = login.json()
        token = str(body.get("access_token") or "")
        if not token:
            meta["login_body"] = body
            return False, "", meta
        return True, token, meta
    except Exception as exc:
        meta["login_error"] = str(exc)
        return False, "", meta


def main() -> int:
    parser = argparse.ArgumentParser(description="Fetch /api/metrics/system + /metrics for audits")
    parser.add_argument("--output-dir", default="artifacts/system_audit")
    parser.add_argument("--api-base-url", required=True)
    parser.add_argument("--label", default="snapshot")
    parser.add_argument("--strict", action="store_true")
    parser.add_argument("--timeout-seconds", type=float, default=10.0)
    args = parser.parse_args()

    out_dir = _ensure_dir(Path(args.output_dir))
    label = str(args.label).strip().replace("/", "_").replace(" ", "_")
    ts = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    prefix = f"{ts}_{label}"

    email_prefix = os.getenv("SYSTEM_AUDIT_EMAIL_PREFIX") or os.getenv("LIVE_VALIDATION_EMAIL_PREFIX") or "system.audit"
    password = os.getenv("SYSTEM_AUDIT_PASSWORD") or os.getenv("LIVE_VALIDATION_PASSWORD") or "SystemAudit#123"
    email = os.getenv("SYSTEM_AUDIT_EMAIL") or f"{email_prefix}+{int(time.time())}@example.com"

    report: dict[str, Any] = {
        "generated_at": _utc_now_iso(),
        "label": label,
        "api_base_url": args.api_base_url,
        "status": "unknown",
    }

    with httpx.Client() as client:
        ok_auth, token, auth_meta = _register_or_login(
            client,
            api_base_url=args.api_base_url.rstrip("/"),
            email=email,
            password=password,
            timeout_seconds=args.timeout_seconds,
        )
        report["auth"] = auth_meta

        # Always fetch Prometheus metrics (public).
        prom = None
        prom_err = None
        try:
            prom_resp = _get(client, f"{args.api_base_url.rstrip('/')}/metrics", timeout=args.timeout_seconds)
            report["prometheus_status"] = prom_resp.status_code
            prom = prom_resp.text
        except Exception as exc:
            prom_err = str(exc)
            report["prometheus_error"] = prom_err

        system_metrics = None
        system_err = None
        if ok_auth and token:
            try:
                headers = {"Authorization": f"Bearer {token}"}
                resp = _get(
                    client,
                    f"{args.api_base_url.rstrip('/')}/api/metrics/system",
                    headers=headers,
                    timeout=args.timeout_seconds,
                )
                report["system_status"] = resp.status_code
                if resp.status_code == 200:
                    system_metrics = resp.json()
                else:
                    system_err = resp.text[:5000]
                    report["system_error"] = system_err
            except Exception as exc:
                system_err = str(exc)
                report["system_error"] = system_err
        else:
            report["system_status"] = "skipped"
            report["system_error"] = "auth_failed"

        if prom is not None:
            _atomic_write(out_dir / f"{prefix}_prometheus_metrics.txt", prom)

        if system_metrics is not None:
            _atomic_write(out_dir / f"{prefix}_metrics_system.json", json.dumps(system_metrics, indent=2, sort_keys=True) + "\n")

            # Pull out the leak-audit fields into the report for quick scanning.
            runtime_system = ((system_metrics.get("runtime") or {}).get("system") or {}) if isinstance(system_metrics, dict) else {}
            wg_peers = system_metrics.get("wireguard_peers") if isinstance(system_metrics, dict) else None
            report["audit"] = {
                "process_memory_mb": runtime_system.get("process_memory_mb"),
                "process_open_fds": runtime_system.get("process_open_fds"),
                "process_threads": runtime_system.get("process_threads"),
                "wg_processes": runtime_system.get("wg_processes"),
                "zombie_processes": runtime_system.get("zombie_processes"),
                "zombie_peers": (wg_peers or {}).get("zombie") if isinstance(wg_peers, dict) else None,
            }

        report["status"] = "pass" if system_metrics is not None else "degraded"
        _atomic_write(out_dir / f"{prefix}_system_audit_report.json", json.dumps(report, indent=2, sort_keys=True) + "\n")

        if args.strict and system_metrics is None:
            return 1
        return 0


if __name__ == "__main__":
    raise SystemExit(main())

