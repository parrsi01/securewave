#!/usr/bin/env python3
"""JWT replay and revocation protection harness."""

from __future__ import annotations

import argparse
import os
import tempfile
import sys
import uuid
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from utils.inprocess_testclient import InProcessTestClient

from dev_tools.sandbox.validation_common import (
    HarnessResult,
    StepResult,
    ensure_dir,
    harness_to_dict,
    summarize_steps,
    utc_now_iso,
    write_html,
    write_json,
    write_markdown,
)


def _prepare_runtime(db_file: Path) -> None:
    os.environ["TESTING"] = "true"
    os.environ["ENVIRONMENT"] = "development"
    os.environ["DATABASE_URL"] = f"sqlite:///{db_file}"
    os.environ["ACCESS_TOKEN_SECRET"] = "chaos-access-secret"
    os.environ["REFRESH_TOKEN_SECRET"] = "chaos-refresh-secret"
    os.environ["LOG_LEVEL"] = "WARNING"
    os.environ["DB_ECHO"] = "false"


def run_harness(*, output_dir: Path) -> dict:
    started = utc_now_iso()
    steps: list[StepResult] = []

    db_file = Path(tempfile.gettempdir()) / f"securewave_chaos_jwt_{uuid.uuid4().hex}.db"
    _prepare_runtime(db_file)

    import importlib
    import sys as _sys
    if "database.session" in _sys.modules:
        db_session = importlib.reload(_sys.modules["database.session"])
    else:
        db_session = importlib.import_module("database.session")
    create_tables = db_session.create_tables
    SessionLocal = db_session.SessionLocal
    if "main" in _sys.modules:
        _main_mod = importlib.reload(_sys.modules["main"])
    else:
        _main_mod = importlib.import_module("main")
    app = _main_mod.app

    from models.user import User
    from services.hashing_service import hash_password

    create_tables()
    db = SessionLocal()
    try:
        user = User(
            email="chaos-jwt@example.com",
            hashed_password=hash_password("ChaosPass123"),
            email_verified=True,
            is_active=True,
            subscription_status="active",
        )
        db.add(user)
        db.commit()
    finally:
        db.close()

    with InProcessTestClient(app, raise_server_exceptions=False) as client:
        login = client.post("/api/auth/login", json={"email": "chaos-jwt@example.com", "password": "ChaosPass123"})
        if login.status_code != 200:
            steps.append(StepResult(name="login", status="failed", duration_ms=0.0, detail=f"status={login.status_code}"))
        else:
            steps.append(StepResult(name="login", status="ok", duration_ms=0.0, detail="token_issued"))

        body = login.json() if login.status_code == 200 else {}
        access_token = body.get("access_token", "")
        # refresh_token is set as HttpOnly cookie by login — capture it for replay attempt
        original_refresh_cookie = client.cookies.get("refresh_token", "")

        # First refresh: cookie sent automatically by client
        first_refresh = client.post("/api/auth/refresh")
        steps.append(
            StepResult(
                name="refresh_once",
                status="ok" if first_refresh.status_code == 200 else "failed",
                duration_ms=0.0,
                detail=f"status={first_refresh.status_code}",
            )
        )

        # Replay: force the original (now-rotated/revoked) token to test replay protection
        replay_refresh = client.post(
            "/api/auth/refresh",
            cookies={"refresh_token": original_refresh_cookie},
        )
        replay_ok = replay_refresh.status_code == 401
        steps.append(
            StepResult(
                name="refresh_replay_blocked",
                status="ok" if replay_ok else "failed",
                duration_ms=0.0,
                detail=f"status={replay_refresh.status_code}",
            )
        )

        revoke = client.post("/api/auth/revoke-token", json={"token": access_token, "token_type": "access"})
        revoke_ok = revoke.status_code == 200
        steps.append(
            StepResult(
                name="access_revoked",
                status="ok" if revoke_ok else "failed",
                duration_ms=0.0,
                detail=f"status={revoke.status_code}",
            )
        )

        me = client.get("/api/auth/me", headers={"Authorization": f"Bearer {access_token}"})
        blocked = me.status_code == 401
        steps.append(
            StepResult(
                name="revoked_access_rejected",
                status="ok" if blocked else "failed",
                duration_ms=0.0,
                detail=f"status={me.status_code}",
            )
        )

    totals = summarize_steps(steps)
    overall = "pass" if totals["failed"] == 0 else "fail"
    finished = utc_now_iso()
    result = HarnessResult(
        harness="jwt_replay_attack",
        started_at=started,
        finished_at=finished,
        overall_status=overall,
        steps=steps,
        metrics={
            "login_success": any(s.name == "login" and s.status == "ok" for s in steps),
            "replay_blocked": any(s.name == "refresh_replay_blocked" and s.status == "ok" for s in steps),
            "revoked_access_rejected": any(s.name == "revoked_access_rejected" and s.status == "ok" for s in steps),
            **totals,
        },
    )
    payload = harness_to_dict(result)

    out_dir = ensure_dir(output_dir)
    write_json(out_dir / "jwt_replay_attack_result.json", payload)

    lines = [
        "# JWT Replay Chaos Summary",
        "",
        f"- Overall status: **{overall}**",
        "",
        "| Step | Status | Detail |",
        "|---|---|---|",
    ]
    for s in steps:
        lines.append(f"| {s.name} | {s.status} | {s.detail} |")
    write_markdown(out_dir / "jwt_replay_attack_summary.md", "\n".join(lines) + "\n")

    rows = "".join(f"<tr><td>{s.name}</td><td>{s.status}</td><td>{s.detail}</td></tr>" for s in steps)
    write_html(
        out_dir / "jwt_replay_attack_summary.html",
        title="JWT Replay Chaos Summary",
        body_html=(
            f"<p><strong>Overall:</strong> {overall}</p>"
            "<table><thead><tr><th>Step</th><th>Status</th><th>Detail</th></tr></thead>"
            f"<tbody>{rows}</tbody></table>"
        ),
    )

    return payload


def main() -> int:
    parser = argparse.ArgumentParser(description="JWT replay and revocation chaos harness")
    parser.add_argument("--output-dir", default="artifacts/chaos_tests")
    args = parser.parse_args()

    payload = run_harness(output_dir=Path(args.output_dir))
    print(payload["overall_status"])
    return 0 if payload["overall_status"] == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
