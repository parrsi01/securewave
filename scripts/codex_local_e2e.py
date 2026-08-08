#!/usr/bin/env python3
"""Run the credentialless SecureWave Codex-local authentication lane.

The lane uses a temporary SQLite database and the real FastAPI authentication
routes.  It never contacts a remote API, sends email, or enables demo/mock
authentication.  Evidence is written only to the external directory supplied
by the operator.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any

try:
    from cli_operation_common import ensure_external_path, redact_text, write_json_evidence
except ModuleNotFoundError:  # pragma: no cover - direct package invocation
    from scripts.cli_operation_common import ensure_external_path, redact_text, write_json_evidence


ROOT = Path(__file__).resolve().parents[1]
LOCAL_ENV = {
    "TESTING": "true",
    "ENVIRONMENT": "codex-local",
    "DEMO_MODE": "false",
    "WG_MOCK_MODE": "false",
    "EMAIL_PROVIDER": "local_capture",
    "FROM_EMAIL": "codex-local@invalid.example",
    "REDIS_URL": "memory://",
    "ALLOWED_HOSTS": "127.0.0.1,localhost",
    "SECRET_KEY": "codex-local-secret-000000000000000000000000000000",
    "ACCESS_TOKEN_SECRET": "codex-local-access-secret-000000000000000000000000",
    "REFRESH_TOKEN_SECRET": "codex-local-refresh-secret-000000000000000000000000",
    "BCRYPT_ROUNDS": "4",
    "SECUREWAVE_CLI_ENV_ONLY": "true",
    "EMAIL_VALIDATOR_CHECK_DELIVERABILITY": "false",
    "AUTO_CREATE_TABLES": "false",
    # Pydantic plugin discovery scans every installed distribution.  The
    # credentialless lane has no application plugins and must remain bounded.
    "PYDANTIC_DISABLE_PLUGINS": "1",
}


class LocalE2EError(RuntimeError):
    """Raised when the local lane cannot prove its contract."""

    def __init__(self, message: str, *, observations: dict[str, Any] | None = None):
        super().__init__(message)
        self.observations = observations or {}


_KNOWN_AUTH_ERROR_DETAILS = {
    "Invalid credentials": "invalid_credentials",
    "Please verify your email before logging in": "email_verification_required",
    "Invalid 2FA code": "invalid_2fa_code",
    "Login failed": "login_failed",
}


def _safe_response_observation(response: Any) -> dict[str, Any]:
    """Return only non-sensitive response metadata for local evidence."""

    try:
        payload = response.json()
    except ValueError:
        payload = None
    if not isinstance(payload, dict):
        return {
            "status": response.status_code,
            "body_type": type(payload).__name__,
            "body_keys": [],
            "detail_class": "non_object_json",
            "content_type": response.headers.get("content-type", ""),
        }
    detail = payload.get("detail")
    return {
        "status": response.status_code,
        "body_type": "object",
        "body_keys": sorted(str(key) for key in payload.keys()),
        "detail_class": _KNOWN_AUTH_ERROR_DETAILS.get(
            detail, "known_status_without_safe_detail" if detail is None else "unrecognized_detail"
        ),
    }


def _database_url(path: Path) -> str:
    return f"sqlite:///{path}"


def _run_migrations(database_url: str) -> dict[str, Any]:
    alembic = shutil.which("alembic")
    if not alembic:
        raise LocalE2EError("alembic CLI is unavailable")
    env = os.environ.copy()
    env["DATABASE_URL"] = database_url
    command = [alembic, "upgrade", "head"]
    completed = subprocess.run(
        command,
        cwd=ROOT,
        env=env,
        text=True,
        capture_output=True,
        check=False,
        timeout=180,
    )
    result = {
        "command": command,
        "exit_code": completed.returncode,
        "output": redact_text((completed.stdout + "\n" + completed.stderr).strip()),
    }
    if completed.returncode != 0:
        raise LocalE2EError("local SQLite migrations failed")
    return result


def _seed_users() -> dict[str, Any]:
    from datetime import datetime

    from database.session import SessionLocal
    # Register every relationship target before SQLAlchemy configures the User
    # mapper.  This mirrors the repository test bootstrap without importing
    # the test conftest or enabling its demo-mode environment.
    from models import (  # noqa: F401
        audit_log,
        email_log,
        gdpr,
        invoice,
        subscription,
        support_ticket,
        usage_analytics,
        user,
        vpn_connection,
        vpn_demo_session,
        vpn_server,
        vpn_usage_event,
        wireguard_peer,
    )
    from models.user import User
    from services.hashing_service import hash_password

    db = SessionLocal()
    try:
        verified = User(
            email="codex-verified@invalid.example",
            hashed_password=hash_password("CodexLocalPass123!"),
            email_verified=True,
            is_active=True,
            subscription_status="basic",
            created_at=datetime.utcnow(),
        )
        unverified = User(
            email="codex-unverified@invalid.example",
            hashed_password=hash_password("CodexLocalPass123!"),
            email_verified=False,
            is_active=True,
            subscription_status="basic",
            created_at=datetime.utcnow(),
        )
        db.add_all([verified, unverified])
        db.commit()
        db.refresh(verified)
        db.refresh(unverified)

        # Exercise the real verification-email service without exposing the
        # generated bearer token in process output or evidence.
        from services.auth_service import AuthService
        from services.enhanced_email_service import EnhancedEmailService

        verification_sent = AuthService(db).send_verification_email(unverified)
        enhanced_sent = EnhancedEmailService(db_session=db).send_email(
            to_email=unverified.email,
            subject="Codex-local email capture",
            html_content="<p>Codex-local payment-notification boundary check.</p>",
            text_content="Codex-local payment-notification boundary check.",
            category="codex-local",
        )
        return {
            "verified_user_seeded": bool(verified.id),
            "unverified_user_seeded": bool(unverified.id),
            "verification_email_capture_succeeded": verification_sent,
            "enhanced_email_capture_succeeded": enhanced_sent,
        }
    finally:
        db.close()


def _run_auth_contract() -> dict[str, Any]:
    from fastapi.testclient import TestClient

    from database.session import get_db
    from main import app

    # The routes depend on database.session.get_db.  Override only that
    # dependency so all requests share the local migration-backed database.
    app.dependency_overrides.clear()

    def override_get_db():
        from database.session import SessionLocal

        db = SessionLocal()
        try:
            yield db
        finally:
            db.close()

    app.dependency_overrides[get_db] = override_get_db
    observations: dict[str, Any] = {}
    try:
        with TestClient(
            app,
            base_url="http://127.0.0.1",
            raise_server_exceptions=False,
        ) as client:
            valid = client.post(
                "/api/auth/login",
                json={
                    "email": "codex-verified@invalid.example",
                    "password": "CodexLocalPass123!",
                },
            )
            observations["valid_login_status"] = valid.status_code
            if valid.status_code != 200:
                safe_error = _safe_response_observation(valid)
                observations["valid_login_error"] = safe_error
                raise LocalE2EError(
                    "seeded verified account did not authenticate "
                    f"status={safe_error['status']} detail_class={safe_error['detail_class']}",
                    observations=observations,
                )
            valid_payload = valid.json()
            access_token = valid_payload.get("access_token")
            refresh_token = valid_payload.get("refresh_token")
            if not access_token or not refresh_token:
                raise LocalE2EError("login did not return the expected token contract")

            auth_headers = {"Authorization": f"Bearer {access_token}"}
            me = client.get("/api/auth/me", headers=auth_headers)
            observations["me_status"] = me.status_code
            if me.status_code != 200:
                raise LocalE2EError("authenticated /me request failed")

            session = client.get("/api/auth/session", headers=auth_headers)
            observations["session_status"] = session.status_code
            if session.status_code != 200 or not session.json().get("authenticated"):
                raise LocalE2EError("authenticated session probe failed")

            refreshed = client.post(
                "/api/auth/refresh", json={"refresh_token": refresh_token}
            )
            observations["refresh_status"] = refreshed.status_code
            if refreshed.status_code != 200 or not refreshed.json().get("access_token"):
                raise LocalE2EError("refresh contract failed")

            logout = client.post(
                "/api/auth/logout",
                headers={"Authorization": f"Bearer {refreshed.json()['access_token']}"},
            )
            observations["logout_status"] = logout.status_code
            if logout.status_code != 200:
                raise LocalE2EError("logout contract failed")

            invalid = client.post(
                "/api/auth/login",
                json={
                    "email": "codex-verified@invalid.example",
                    "password": "incorrect-password",
                },
            )
            observations["invalid_password_status"] = invalid.status_code
            if invalid.status_code != 401:
                raise LocalE2EError("invalid password did not fail with 401")

            unverified = client.post(
                "/api/auth/login",
                json={
                    "email": "codex-unverified@invalid.example",
                    "password": "CodexLocalPass123!",
                },
            )
            observations["unverified_status"] = unverified.status_code
            if unverified.status_code != 403:
                raise LocalE2EError("unverified account did not fail closed with 403")
    finally:
        app.dependency_overrides.clear()
    return observations


def run_local_e2e(evidence_dir: Path) -> tuple[str, Path]:
    evidence_dir = ensure_external_path(str(evidence_dir), ROOT, "evidence_dir")
    evidence_dir.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="securewave-codex-local-") as temp_root:
        temp_path = Path(temp_root)
        database_path = temp_path / "securewave.db"
        capture_dir = evidence_dir / "email-capture"

        previous = {key: os.environ.get(key) for key in (*LOCAL_ENV, "DATABASE_URL", "SECUREWAVE_LOCAL_EMAIL_EVIDENCE_DIR", "WG_DATA_DIR")}
        try:
            os.environ.update(LOCAL_ENV)
            os.environ["DATABASE_URL"] = _database_url(database_path)
            os.environ["SECUREWAVE_LOCAL_EMAIL_EVIDENCE_DIR"] = str(capture_dir)
            os.environ["WG_DATA_DIR"] = str(temp_path / "wireguard")
            migrations = _run_migrations(os.environ["DATABASE_URL"])
            seed = _seed_users()
            auth = _run_auth_contract()
            capture_files = sorted(capture_dir.glob("*.json"))
            if not capture_files:
                raise LocalE2EError("local email provider did not write evidence")
            result = "LOCAL_AUTOMATION_READY"
            evidence = {
                "result": result,
                "environment": "codex-local",
                "network_access": "not used",
                "database": "temporary sqlite",
                "migrations": migrations,
                "seed": seed,
                "auth_contract": auth,
                "email_capture_file_count": len(capture_files),
                "secrets_persisted": False,
            }
            destination = write_json_evidence(evidence_dir, "local-e2e.json", evidence)
            return result, destination
        except LocalE2EError as exc:
            failure = {
                "result": "FAIL",
                "environment": "codex-local",
                "network_access": "not used",
                "database": "temporary sqlite",
                "failure": str(exc).split(" status=", 1)[0],
                "observations": exc.observations,
                "secrets_persisted": False,
            }
            write_json_evidence(evidence_dir, "local-e2e-failure.json", failure)
            raise
        finally:
            for key, value in previous.items():
                if value is None:
                    os.environ.pop(key, None)
                else:
                    os.environ[key] = value


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--evidence-dir", required=True, type=Path)
    args = parser.parse_args(argv)
    try:
        result, destination = run_local_e2e(args.evidence_dir)
    except Exception as exc:
        print(f"LOCAL_E2E_RESULT=FAIL:{type(exc).__name__}", file=sys.stderr)
        print("AUTOMATION_RESULT=FAIL", file=sys.stderr)
        return 3
    print(f"LOCAL_E2E_RESULT={result}")
    print(f"LOCAL_E2E_EVIDENCE={destination}")
    print("AUTOMATION_RESULT=READY_FOR_PHASE_0_REVIEW")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
