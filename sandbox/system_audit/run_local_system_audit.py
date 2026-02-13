#!/usr/bin/env python3
"""
Local (in-process) system audit snapshot.

Why:
- The sandbox environment may forbid opening TCP sockets, which prevents
  running the HTTP-based system_audit_probe.py against a live server.
- This script exercises the same API endpoints in-process and writes stable
  artifact filenames for review/CI.

Writes:
- artifacts/system_audit/local_prometheus_metrics.txt
- artifacts/system_audit/local_metrics_system.json
- artifacts/system_audit/local_system_audit_report.json
"""

from __future__ import annotations

import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _set_default_env() -> None:
    os.environ.setdefault("ENVIRONMENT", "development")
    os.environ.setdefault("TESTING", "true")
    os.environ.setdefault("DEMO_MODE", "true")
    os.environ.setdefault("WG_MOCK_MODE", "true")
    os.environ.setdefault("DATABASE_URL", "sqlite:///:memory:")

    # Auth secrets (placeholders for local/offline use only).
    os.environ.setdefault("SECRET_KEY", "local-system-audit-key")
    os.environ.setdefault("ACCESS_TOKEN_SECRET", "local-access-secret")
    os.environ.setdefault("REFRESH_TOKEN_SECRET", "local-refresh-secret")


def _atomic_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(content, encoding="utf-8")
    tmp.replace(path)


def main() -> int:
    _set_default_env()

    # Import after env is set so database/session binds to the intended DB.
    from database.session import create_tables
    create_tables()

    from main import app
    from utils.inprocess_testclient import InProcessTestClient

    out_dir = Path("artifacts/system_audit")
    out_dir.mkdir(parents=True, exist_ok=True)

    report: dict[str, Any] = {
        "generated_at": _utc_now_iso(),
        "mode": "inprocess",
        "status": "unknown",
    }

    email = os.getenv("SYSTEM_AUDIT_EMAIL") or "system.audit.local@example.com"
    password = os.getenv("SYSTEM_AUDIT_PASSWORD") or "SystemAudit#123"

    with InProcessTestClient(app, raise_server_exceptions=False) as client:
        # Seed a user via register (idempotent).
        reg = client.post(
            "/api/auth/register",
            json={"email": email, "password": password, "password_confirm": password},
        )
        report["register_status"] = reg.status_code

        login = client.post("/api/auth/login", json={"email": email, "password": password})
        report["login_status"] = login.status_code
        token = ""
        if login.status_code == 200:
            try:
                token = str(login.json().get("access_token") or "")
            except Exception:
                token = ""

        prom_resp = client.get("/metrics")
        report["prometheus_status"] = prom_resp.status_code
        _atomic_write(out_dir / "local_prometheus_metrics.txt", prom_resp.text)

        system_metrics = None
        if token:
            sys_resp = client.get("/api/metrics/system", headers={"Authorization": f"Bearer {token}"})
            report["system_status"] = sys_resp.status_code
            if sys_resp.status_code == 200:
                system_metrics = sys_resp.json()
                _atomic_write(
                    out_dir / "local_metrics_system.json",
                    json.dumps(system_metrics, indent=2, sort_keys=True) + "\n",
                )
            else:
                report["system_error"] = sys_resp.text[:5000]
        else:
            report["system_status"] = "skipped"
            report["system_error"] = "auth_failed"

    if isinstance(system_metrics, dict):
        runtime_system = ((system_metrics.get("runtime") or {}).get("system") or {})
        wg_peers = system_metrics.get("wireguard_peers") or {}
        report["audit"] = {
            "process_memory_mb": runtime_system.get("process_memory_mb"),
            "process_open_fds": runtime_system.get("process_open_fds"),
            "process_threads": runtime_system.get("process_threads"),
            "wg_processes": runtime_system.get("wg_processes"),
            "zombie_processes": runtime_system.get("zombie_processes"),
            "zombie_peers": wg_peers.get("zombie") if isinstance(wg_peers, dict) else None,
        }
        report["status"] = "pass"
    else:
        report["status"] = "degraded"

    _atomic_write(out_dir / "local_system_audit_report.json", json.dumps(report, indent=2, sort_keys=True) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
