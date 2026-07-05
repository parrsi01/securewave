#!/usr/bin/env python3
"""Enterprise Linux VPN certification harness.

Default mode is intentionally safe: it uses TESTING=true, a temporary SQLite
database, demo/WireGuard mock backend mode, and synthetic enterprise users.
It never writes to production infrastructure. Live tunnel proofs and external
load targets are explicit opt-in operations.
"""

from __future__ import annotations

import argparse
import base64
import concurrent.futures
import hashlib
import json
import logging
import os
import re
import statistics
import subprocess  # nosec B404 - used only for explicit local validation commands
import sys
import tempfile
import threading
import time
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable


REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))
ARTIFACT_ROOT = REPO_ROOT / "artifacts" / "linux-enterprise-vpn-certification"
LATEST_DIR = ARTIFACT_ROOT / "latest"
PROTOCOLS = ("wireguard", "openvpn", "ikev2")
DEFAULT_COHORTS = (100, 250, 500, 1000)
DEFAULT_WORKERS = 16
REDACTED = "[REDACTED]"
CERTIFICATION_PASSWORD = "EnterprisePass" + "123!"
QUIET_LOGGERS = (
    "background_tasks",
    "httpx",
    "main",
    "routes.auth",
    "routes.devices",
    "routes.vpn",
    "services.auth_service",
    "services.email_service",
    "services.vpn_peer_manager",
    "services.wireguard_server_manager",
    "services.wireguard_service",
)

SENSITIVE_KEYS = {
    "access_token",
    "refresh_token",
    "csrf_token",
    "token",
    "password",
    "secret",
    "private_key",
    "private",
    "wireguard_config",
    "openvpn_config",
    "ikev2_config",
    "config",
    "qr_code",
}

SENSITIVE_KEY_FRAGMENTS = (
    "private_key",
    "password",
    "secret",
    "certificate",
    "ca_cert",
)

JWT_RE = re.compile(r"eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+")
PEM_RE = re.compile(
    r"-----BEGIN [^-]+-----.*?-----END [^-]+-----",
    flags=re.DOTALL,
)
EMAIL_RE = re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}")


def utc_timestamp() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def stable_hash(value: str) -> str:
    digest = hashlib.sha256(value.encode("utf-8")).hexdigest()
    return digest[:12]


def synthetic_wg_public_key(label: str) -> str:
    digest = hashlib.sha256(f"securewave-enterprise-cert:{label}".encode("utf-8")).digest()
    return base64.b64encode(digest).decode("ascii")


def redact(value: Any, *, key: str | None = None) -> Any:
    """Remove secrets and private identity material from artifact payloads."""
    lowered = (key or "").lower()
    key_is_sensitive = (
        lowered in SENSITIVE_KEYS
        or lowered.endswith("_token")
        or lowered.endswith("_config")
        or any(fragment in lowered for fragment in SENSITIVE_KEY_FRAGMENTS)
    )
    if key_is_sensitive and not isinstance(value, (dict, list)):
        return REDACTED
    if lowered in {"email", "account_email", "user_email"} and isinstance(value, str):
        return f"sha256:{stable_hash(value)}"
    if isinstance(value, dict):
        return {str(k): redact(v, key=str(k)) for k, v in value.items()}
    if isinstance(value, list):
        return [redact(item) for item in value]
    if isinstance(value, str):
        redacted = JWT_RE.sub(REDACTED, value)
        redacted = PEM_RE.sub(REDACTED, redacted)
        redacted = EMAIL_RE.sub(lambda m: f"sha256:{stable_hash(m.group(0).lower())}", redacted)
        if "[Interface]" in redacted or "[Peer]" in redacted or "connections {" in redacted:
            return REDACTED
        return redacted
    return value


def write_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(redact(payload), indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def write_text(path: Path, body: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(body, encoding="utf-8")


def percentile(values: list[float], pct: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    if len(ordered) == 1:
        return ordered[0]
    rank = (len(ordered) - 1) * (pct / 100.0)
    low = int(rank)
    high = min(low + 1, len(ordered) - 1)
    weight = rank - low
    return ordered[low] * (1 - weight) + ordered[high] * weight


@dataclass
class EndpointStats:
    latencies_ms: list[float] = field(default_factory=list)
    statuses: Counter[int] = field(default_factory=Counter)
    failures: int = 0

    def add(self, status_code: int, elapsed_ms: float, ok: bool) -> None:
        self.latencies_ms.append(elapsed_ms)
        self.statuses[status_code] += 1
        if not ok:
            self.failures += 1

    def summary(self) -> dict[str, Any]:
        total = len(self.latencies_ms)
        return {
            "requests": total,
            "statuses": dict(sorted(self.statuses.items())),
            "errors": self.failures,
            "error_rate": round(self.failures / total, 6) if total else 0,
            "latency_ms": {
                "p50": round(percentile(self.latencies_ms, 50), 2),
                "p95": round(percentile(self.latencies_ms, 95), 2),
                "p99": round(percentile(self.latencies_ms, 99), 2),
                "max": round(max(self.latencies_ms), 2) if self.latencies_ms else 0,
                "mean": round(statistics.fmean(self.latencies_ms), 2)
                if self.latencies_ms
                else 0,
            },
        }


class Metrics:
    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._endpoints: dict[str, EndpointStats] = defaultdict(EndpointStats)
        self.failures: list[dict[str, Any]] = []

    def record(self, name: str, status_code: int, elapsed_ms: float, ok: bool) -> None:
        with self._lock:
            self._endpoints[name].add(status_code, elapsed_ms, ok)

    def fail(self, label: str, detail: Any) -> None:
        with self._lock:
            self.failures.append({"check": label, "detail": redact(detail)})

    def summary(self) -> dict[str, Any]:
        return {
            "endpoints": {
                name: stats.summary()
                for name, stats in sorted(self._endpoints.items())
            },
            "failures": self.failures,
        }


def assert_status(
    metrics: Metrics,
    label: str,
    response: Any,
    expected: set[int],
) -> bool:
    ok = response.status_code in expected
    if not ok:
        try:
            body = response.json()
        except Exception:
            body = response.text[:500]
        metrics.fail(
            label,
            {
                "expected": sorted(expected),
                "actual": response.status_code,
                "body": body,
            },
        )
    return ok


def request_json(
    client: Any,
    metrics: Metrics,
    name: str,
    method: str,
    path: str,
    *,
    expected: set[int],
    headers: dict[str, str] | None = None,
    payload: dict[str, Any] | None = None,
) -> tuple[int, dict[str, Any]]:
    start = time.perf_counter()
    response = client.request(method, path, json=payload, headers=headers)
    elapsed_ms = (time.perf_counter() - start) * 1000
    ok = response.status_code in expected
    metrics.record(name, response.status_code, elapsed_ms, ok)
    assert_status(metrics, name, response, expected)
    try:
        body = response.json()
    except Exception:
        body = {"raw": response.text[:500]}
    return response.status_code, body if isinstance(body, dict) else {"body": body}


def configure_safe_environment(db_url: str) -> Callable[[], None]:
    os.environ.update(
        {
            "TESTING": "true",
            "DATABASE_URL": db_url,
            "SECRET_KEY": "enterprise-cert-secret-key",
            "ACCESS_TOKEN_SECRET": "enterprise-cert-access-secret",
            "REFRESH_TOKEN_SECRET": "enterprise-cert-refresh-secret",
            "DEMO_MODE": "true",
            "WG_MOCK_MODE": "true",
            "ENVIRONMENT": "development",
            "ENABLE_SENTRY": "false",
            "EMAIL_VALIDATOR_CHECK_DELIVERABILITY": "false",
            "BCRYPT_ROUNDS": "4",
            "WG_DATA_DIR": str(Path(tempfile.gettempdir()) / "securewave_enterprise_cert_wg"),
            "WG_CLIENT_IPV4_CIDR": "10.80.0.0/20",
            "WG_CLIENT_IPV4_START_OFFSET": "9",
            "AUTO_CREATE_TABLES": "false",
            "SECUREWAVE_IKEV2_EAP_SECRET": "enterprise-cert-eap-secret",
            "FREE_TIER_DEVICE_LIMIT": "1",
        }
    )
    for logger_name in QUIET_LOGGERS:
        logging.getLogger(logger_name).setLevel(logging.ERROR)

    from sqlalchemy import create_engine
    from sqlalchemy.orm import sessionmaker

    from database.base import Base
    from database.session import get_db

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
        wireguard_peer,
    )

    engine = create_engine(
        db_url,
        connect_args={"check_same_thread": False, "timeout": 30},
        pool_size=64,
        max_overflow=64,
        pool_timeout=60,
        echo=False,
    )
    SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
    Base.metadata.drop_all(bind=engine)
    Base.metadata.create_all(bind=engine)

    import database.session as db_session
    from main import app

    db_session.SessionLocal.configure(bind=engine)

    def override_get_db():
        session = SessionLocal()
        try:
            yield session
        finally:
            session.close()

    app.dependency_overrides[get_db] = override_get_db

    def cleanup() -> None:
        app.dependency_overrides.pop(get_db, None)
        Base.metadata.drop_all(bind=engine)
        engine.dispose()

    seed_servers(SessionLocal)
    return cleanup


def seed_servers(SessionLocal: Callable[[], Any]) -> None:
    from models.vpn_server import VPNServer

    ca = "-----BEGIN CERTIFICATE-----\nMIIBENTERPRISECERT\n-----END CERTIFICATE-----"
    servers = [
        VPNServer(
            server_id="enterprise-full-de-1",
            location="Nuremberg, Germany",
            country="Germany",
            country_code="DE",
            city="Nuremberg",
            region="Europe",
            hcloud_location="nbg1",
            public_ip="10.200.0.10",
            endpoint="10.200.0.10:51820",
            wg_public_key=synthetic_wg_public_key("enterprise-full-de-1"),
            wg_private_key_encrypted="encrypted-enterprise-private-key",
            status="active",
            health_status="healthy",
            max_connections=2000,
            current_connections=100,
            performance_score=99.0,
            latency_ms=21.0,
            hcloud_server_state="running",
            supports_openvpn=True,
            supports_ikev2=True,
            openvpn_endpoint="10.200.0.10",
            openvpn_ca_cert_pem=ca,
            ikev2_remote_id="vpn.enterprise.securewave.test",
            ikev2_ca_cert_pem=ca,
        ),
        VPNServer(
            server_id="enterprise-wg-only-us-1",
            location="Ashburn, United States",
            country="United States",
            country_code="US",
            city="Ashburn",
            region="Americas",
            hcloud_location="ash",
            public_ip="10.200.1.10",
            endpoint="10.200.1.10:51820",
            wg_public_key=synthetic_wg_public_key("enterprise-wg-only-us-1"),
            wg_private_key_encrypted="encrypted-enterprise-wg-only-private-key",
            status="active",
            health_status="healthy",
            max_connections=1000,
            current_connections=50,
            performance_score=90.0,
            latency_ms=40.0,
            hcloud_server_state="running",
        ),
        VPNServer(
            server_id="enterprise-incomplete-ikev2-1",
            location="Incomplete Metadata",
            country="Germany",
            country_code="DE",
            city="Nuremberg",
            region="Europe",
            hcloud_location="nbg1",
            public_ip="10.200.2.10",
            endpoint="10.200.2.10:51820",
            wg_public_key=synthetic_wg_public_key("enterprise-incomplete-ikev2-1"),
            wg_private_key_encrypted="encrypted-enterprise-incomplete-private-key",
            status="active",
            health_status="healthy",
            max_connections=1000,
            current_connections=10,
            performance_score=10.0,
            latency_ms=90.0,
            hcloud_server_state="running",
            supports_ikev2=True,
            ikev2_remote_id="vpn.incomplete.securewave.test",
            ikev2_ca_cert_pem=None,
        ),
    ]
    session = SessionLocal()
    try:
        session.add_all(servers)
        session.commit()
    finally:
        session.close()


def profile_config_present(protocol: str, body: dict[str, Any]) -> bool:
    if protocol == "wireguard":
        return bool(body.get("wireguard_config"))
    if protocol == "openvpn":
        return bool(body.get("openvpn_config"))
    if protocol == "ikev2":
        return bool(body.get("ikev2_config"))
    return False


def run_user_flow(
    client: Any,
    metrics: Metrics,
    user_index: int,
) -> dict[str, Any]:
    email = f"enterprise-cert-{user_index:05d}@example.com"
    password = CERTIFICATION_PASSWORD
    user_summary: dict[str, Any] = {
        "user_index": user_index,
        "profiles": {},
        "usage_bytes_reported": 0,
        "ok": True,
    }

    status_code, register_body = request_json(
        client,
        metrics,
        "auth.register",
        "POST",
        "/api/auth/register",
        expected={201},
        payload={
            "email": email,
            "password": password,
            "password_confirm": password,
        },
    )
    if status_code != 201:
        user_summary["ok"] = False
        return user_summary

    status_code, login_body = request_json(
        client,
        metrics,
        "auth.login",
        "POST",
        "/api/auth/login",
        expected={200},
        payload={"email": email, "password": password},
    )
    token = login_body.get("access_token")
    if status_code != 200 or not token:
        metrics.fail("auth.login.token", {"user_index": user_index, "body": login_body})
        user_summary["ok"] = False
        return user_summary
    headers = {"Authorization": f"Bearer {token}"}

    request_json(
        client,
        metrics,
        "auth.me",
        "GET",
        "/api/auth/me",
        expected={200},
        headers=headers,
    )
    request_json(
        client,
        metrics,
        "auth.session",
        "GET",
        "/api/auth/session",
        expected={200},
        headers=headers,
    )
    request_json(
        client,
        metrics,
        "vpn.servers",
        "GET",
        "/api/vpn/servers?device_type=linux",
        expected={200},
        headers=headers,
    )
    request_json(
        client,
        metrics,
        "vpn.protocols",
        "GET",
        "/api/vpn/protocols?device_type=linux",
        expected={200},
        headers=headers,
    )

    device_id: int | None = None
    for protocol in PROTOCOLS:
        status_code, profile = request_json(
            client,
            metrics,
            f"vpn.profile.{protocol}",
            "POST",
            "/api/vpn/profile",
            expected={200},
            headers=headers,
            payload={
                "device_name": f"Enterprise Linux {user_index}",
                "device_type": "linux",
                "protocol": protocol,
                "server_id": "enterprise-full-de-1",
            },
        )
        present = status_code == 200 and profile_config_present(protocol, profile)
        if not present:
            metrics.fail(
                f"vpn.profile.{protocol}.shape",
                {"user_index": user_index, "body": profile},
            )
            user_summary["ok"] = False
        device_id = int(profile.get("device_id") or device_id or 0) or None
        user_summary["profiles"][protocol] = {
            "status": status_code,
            "config_present": present,
            "server_id": profile.get("server_id"),
            "device_id_present": bool(profile.get("device_id")),
            "expires_at_present": bool(profile.get("expires_at")),
        }

    if device_id is not None:
        request_json(
            client,
            metrics,
            "vpn.connect",
            "POST",
            "/api/vpn/connect",
            expected={200},
            headers=headers,
            payload={"server_id": "enterprise-full-de-1", "protocol": "wireguard"},
        )
        for protocol in PROTOCOLS:
            rx = (user_index + 1) * 1024
            tx = (user_index + 1) * 256
            user_summary["usage_bytes_reported"] += rx + tx
            request_json(
                client,
                metrics,
                "vpn.usage_report",
                "POST",
                "/api/vpn/usage/report",
                expected={200},
                headers=headers,
                payload={
                    "device_id": device_id,
                    "server_id": "enterprise-full-de-1",
                    "protocol": protocol,
                    "rx_bytes": rx,
                    "tx_bytes": tx,
                },
            )
        request_json(
            client,
            metrics,
            "user.plan",
            "GET",
            "/api/user/plan",
            expected={200},
            headers=headers,
        )
        request_json(
            client,
            metrics,
            "vpn.device_usage",
            "GET",
            f"/api/vpn/devices/{device_id}/usage",
            expected={200},
            headers=headers,
        )
        status_code, rotate = request_json(
            client,
            metrics,
            "vpn.rotate_keys.sample",
            "POST",
            f"/api/vpn/devices/{device_id}/rotate-keys",
            expected={200},
            headers=headers,
        ) if user_index == 0 else (0, {})
        if user_index == 0 and (status_code != 200 or int(rotate.get("key_version") or 0) < 2):
            metrics.fail("vpn.rotate_keys.sample.version", rotate)
            user_summary["ok"] = False
        request_json(
            client,
            metrics,
            "vpn.disconnect",
            "POST",
            "/api/vpn/disconnect",
            expected={200},
            headers=headers,
        )

    request_json(
        client,
        metrics,
        "auth.logout",
        "POST",
        "/api/auth/logout",
        expected={200},
        headers=headers,
    )
    status_code, relogin = request_json(
        client,
        metrics,
        "auth.relogin",
        "POST",
        "/api/auth/login",
        expected={200},
        payload={"email": email, "password": password},
    )
    relogin_token = relogin.get("access_token")
    if status_code == 200 and relogin_token:
        request_json(
            client,
            metrics,
            "user.plan.after_relogin",
            "GET",
            "/api/user/plan",
            expected={200},
            headers={"Authorization": f"Bearer {relogin_token}"},
        )
    return user_summary


def run_negative_checks(client: Any, metrics: Metrics, sample_users: list[dict[str, Any]]) -> dict[str, Any]:
    checks: dict[str, Any] = {}
    status_code, _ = request_json(
        client,
        metrics,
        "auth.invalid_token",
        "GET",
        "/api/auth/me",
        expected={401, 403},
        headers={"Authorization": "Bearer invalid.enterprise.cert.token"},
    )
    checks["invalid_token_rejected"] = status_code in {401, 403}

    email = "enterprise-negative@example.com"
    password = CERTIFICATION_PASSWORD
    _, reg = request_json(
        client,
        metrics,
        "negative.auth.register",
        "POST",
        "/api/auth/register",
        expected={201},
        payload={
            "email": email,
            "password": password,
            "password_confirm": password,
        },
    )
    token = reg.get("access_token")
    headers = {"Authorization": f"Bearer {token}"}

    status_code, stale = request_json(
        client,
        metrics,
        "negative.profile.stale_device",
        "POST",
        "/api/vpn/profile",
        expected={200},
        headers=headers,
        payload={
            "device_id": 99999999,
            "device_name": "Negative Linux",
            "device_type": "linux",
            "protocol": "wireguard",
            "server_id": "enterprise-full-de-1",
        },
    )
    checks["stale_device_id_recovered"] = status_code == 200 and stale.get("device_id") != 99999999

    status_code, _ = request_json(
        client,
        metrics,
        "negative.profile.device_limit",
        "POST",
        "/api/vpn/profile",
        expected={403},
        headers=headers,
        payload={
            "device_name": "Second Linux Device",
            "device_type": "linux",
            "protocol": "wireguard",
            "server_id": "enterprise-full-de-1",
        },
    )
    checks["device_limit_enforced"] = status_code == 403

    status_code, _ = request_json(
        client,
        metrics,
        "negative.profile.unsupported_protocol",
        "POST",
        "/api/vpn/profile",
        expected={400, 503},
        headers=headers,
        payload={
            "device_name": "Negative Linux",
            "device_type": "linux",
            "protocol": "ikev2",
            "server_id": "enterprise-wg-only-us-1",
        },
    )
    checks["unsupported_protocol_rejected"] = status_code in {400, 503}

    status_code, _ = request_json(
        client,
        metrics,
        "negative.profile.incomplete_metadata",
        "POST",
        "/api/vpn/profile",
        expected={503},
        headers=headers,
        payload={
            "device_name": "Negative Linux",
            "device_type": "linux",
            "protocol": "ikev2",
            "server_id": "enterprise-incomplete-ikev2-1",
        },
    )
    checks["incomplete_ikev2_metadata_failed_closed"] = status_code == 503

    if len(sample_users) >= 2:
        first = sample_users[0]
        second = sample_users[1]
        first_token = first.get("access_token")
        second_device_id = second.get("device_id")
        if first_token and second_device_id:
            status_code, _ = request_json(
                client,
                metrics,
                "negative.cross_user_device_usage",
                "GET",
                f"/api/vpn/devices/{second_device_id}/usage",
                expected={404},
                headers={"Authorization": f"Bearer {first_token}"},
            )
            checks["cross_user_device_access_rejected"] = status_code == 404
    return checks


def create_sample_users_for_isolation(client: Any, metrics: Metrics) -> list[dict[str, Any]]:
    samples: list[dict[str, Any]] = []
    for index in range(2):
        email = f"enterprise-isolation-{index}@example.com"
        password = CERTIFICATION_PASSWORD
        _, reg = request_json(
            client,
            metrics,
            "isolation.auth.register",
            "POST",
            "/api/auth/register",
            expected={201},
            payload={
                "email": email,
                "password": password,
                "password_confirm": password,
            },
        )
        token = reg.get("access_token")
        if not token:
            continue
        _, profile = request_json(
            client,
            metrics,
            "isolation.profile",
            "POST",
            "/api/vpn/profile",
            expected={200},
            headers={"Authorization": f"Bearer {token}"},
            payload={
                "device_name": f"Isolation Device {index}",
                "device_type": "linux",
                "protocol": "wireguard",
                "server_id": "enterprise-full-de-1",
            },
        )
        samples.append(
            {
                "access_token": token,
                "device_id": profile.get("device_id"),
            }
        )
    return samples


def database_integrity_summary(SessionLocal: Callable[[], Any], expected_usage_bytes: int) -> dict[str, Any]:
    from models.usage_analytics import DailyUsageMetrics
    from models.user import User
    from models.wireguard_peer import WireGuardPeer

    session = SessionLocal()
    try:
        users = session.query(User).count()
        peers = session.query(WireGuardPeer).all()
        usage_rows = session.query(DailyUsageMetrics).all()
        public_keys = [peer.public_key for peer in peers]
        ip_addresses = [peer.ipv4_address for peer in peers]
        observed_usage_bytes = int(
            round(sum((row.total_data_mb or 0.0) for row in usage_rows) * 1024 * 1024)
        )
        duplicate_public_keys = len(public_keys) - len(set(public_keys))
        duplicate_ip_addresses = len(ip_addresses) - len(set(ip_addresses))
        tolerance_bytes = max(1, int(expected_usage_bytes * 0.0001))
        usage_delta = abs(observed_usage_bytes - expected_usage_bytes)
        return {
            "users": users,
            "peers": len(peers),
            "usage_rows": len(usage_rows),
            "duplicate_public_keys": duplicate_public_keys,
            "duplicate_ip_addresses": duplicate_ip_addresses,
            "expected_usage_bytes": expected_usage_bytes,
            "observed_usage_bytes": observed_usage_bytes,
            "usage_delta_bytes": usage_delta,
            "usage_tolerance_bytes": tolerance_bytes,
            "usage_within_tolerance": usage_delta <= tolerance_bytes,
            "ok": duplicate_public_keys == 0
            and duplicate_ip_addresses == 0
            and usage_delta <= tolerance_bytes,
        }
    finally:
        session.close()


def run_local_cohort(cohort_size: int, workers: int) -> dict[str, Any]:
    from fastapi.testclient import TestClient
    from main import app
    from database.session import SessionLocal

    metrics = Metrics()
    started = time.perf_counter()
    users: list[dict[str, Any]] = []
    with TestClient(app, raise_server_exceptions=False) as client:
        with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as executor:
            futures = [
                executor.submit(run_user_flow, client, metrics, index)
                for index in range(cohort_size)
            ]
            for future in concurrent.futures.as_completed(futures):
                try:
                    users.append(future.result())
                except Exception as exc:  # noqa: BLE001
                    metrics.fail("user_flow.exception", {"error": repr(exc)})

        samples = create_sample_users_for_isolation(client, metrics)
        negative_checks = run_negative_checks(client, metrics, samples)

    expected_usage_bytes = sum(int(user.get("usage_bytes_reported") or 0) for user in users)
    db_summary = database_integrity_summary(SessionLocal, expected_usage_bytes)
    elapsed_s = time.perf_counter() - started
    user_failures = [user for user in users if not user.get("ok")]
    metrics_summary = metrics.summary()
    ok = (
        len(users) == cohort_size
        and not user_failures
        and not metrics_summary["failures"]
        and all(negative_checks.values())
        and db_summary["ok"]
    )
    return {
        "cohort_size": cohort_size,
        "workers": workers,
        "duration_seconds": round(elapsed_s, 3),
        "users_completed": len(users),
        "ok": ok,
        "user_failures": len(user_failures),
        "negative_checks": negative_checks,
        "database_integrity": db_summary,
        "metrics": metrics_summary,
        "protocol_profile_success": {
            protocol: sum(
                1
                for user in users
                if user.get("profiles", {}).get(protocol, {}).get("config_present")
            )
            for protocol in PROTOCOLS
        },
    }


def run_local_enterprise_simulation(cohorts: list[int], workers: int) -> dict[str, Any]:
    results = []
    for cohort in cohorts:
        with tempfile.TemporaryDirectory(prefix=f"securewave-enterprise-{cohort}-") as tmp:
            db_path = Path(tmp) / "enterprise-cert.sqlite3"
            cleanup = configure_safe_environment(f"sqlite:///{db_path}")
            try:
                results.append(run_local_cohort(cohort, workers))
            finally:
                cleanup()
    return {
        "mode": "safe_local_test_database",
        "cohorts": results,
        "ok": all(result.get("ok") for result in results),
    }


def run_command(command: list[str], *, timeout: int) -> dict[str, Any]:
    started = time.perf_counter()
    completed = subprocess.run(  # nosec B603
        command,
        cwd=REPO_ROOT,
        text=True,
        capture_output=True,
        timeout=timeout,
        check=False,
    )
    elapsed_ms = round((time.perf_counter() - started) * 1000, 2)
    return {
        "command": command,
        "returncode": completed.returncode,
        "elapsed_ms": elapsed_ms,
        "stdout": completed.stdout[-4000:],
        "stderr": completed.stderr[-4000:],
        "ok": completed.returncode == 0,
    }


def run_live_protocol_proofs(protocols: list[str], hold_seconds: int, evidence_timeout: int) -> dict[str, Any]:
    results = []
    for protocol in protocols:
        command = [
            ".venv/bin/python",
            "scripts/linux_app_vpn_tunnel_proof.py",
            "--protocol",
            protocol,
            "--hold-seconds",
            str(hold_seconds),
            "--evidence-timeout",
            str(evidence_timeout),
            "--json",
        ]
        result = run_command(command, timeout=evidence_timeout + hold_seconds + 120)
        parsed: dict[str, Any] | None = None
        if result["stdout"].strip():
            try:
                parsed = json.loads(result["stdout"])
            except json.JSONDecodeError:
                parsed = None
        results.append(
            {
                "protocol": protocol,
                "command": command,
                "returncode": result["returncode"],
                "ok": result["ok"] and bool(parsed and parsed.get("ok")),
                "summary": summarize_live_proof(parsed) if parsed else None,
                "stderr_tail": result["stderr"],
            }
        )
    return {"ok": all(item["ok"] for item in results), "results": results}


def summarize_live_proof(payload: dict[str, Any] | None) -> dict[str, Any]:
    if not payload:
        return {"ok": False, "error": "missing_json"}
    summaries = []
    for item in payload.get("results") or []:
        evidence = item.get("evidence") or {}
        summaries.append(
            {
                "protocol": item.get("protocol"),
                "ok": bool(item.get("ok")),
                "connect_events": [
                    event.get("event")
                    for event in item.get("probe_events") or []
                ],
                "data_plane_ok": bool((evidence.get("data_plane") or {}).get("ok")),
                "dns_ok": bool((evidence.get("dns") or {}).get("ok")),
                "exit_ip_ok": bool((evidence.get("exit_ip") or {}).get("ok")),
                "backend_health_ok": bool((evidence.get("backend_health") or {}).get("ok")),
                "ikev2_routing_rule_ok": (
                    None
                    if "ikev2_routing_rule" not in evidence
                    else bool((evidence.get("ikev2_routing_rule") or {}).get("ok"))
                ),
            }
        )
    return {
        "ok": bool(payload.get("ok")),
        "results": summaries,
        "cleanup_ok": bool((payload.get("cleanup") or {}).get("returncode") == 0),
    }


def readiness_matrix(simulation: dict[str, Any], live_proofs: dict[str, Any] | None) -> dict[str, Any]:
    cohorts = {
        str(result["cohort_size"]): {
            "status": "pass" if result.get("ok") else "fail",
            "users_completed": result.get("users_completed"),
            "duration_seconds": result.get("duration_seconds"),
            "p95_login_ms": (
                result.get("metrics", {})
                .get("endpoints", {})
                .get("auth.login", {})
                .get("latency_ms", {})
                .get("p95")
            ),
            "p99_profile_wireguard_ms": (
                result.get("metrics", {})
                .get("endpoints", {})
                .get("vpn.profile.wireguard", {})
                .get("latency_ms", {})
                .get("p99")
            ),
            "error_count": len(result.get("metrics", {}).get("failures", [])),
        }
        for result in simulation.get("cohorts", [])
    }
    protocol_readiness = {
        protocol: {
            "backend_profile_scale": all(
                result.get("protocol_profile_success", {}).get(protocol) == result.get("cohort_size")
                for result in simulation.get("cohorts", [])
            ),
            "live_runtime_proof": "not_run",
        }
        for protocol in PROTOCOLS
    }
    if live_proofs:
        for item in live_proofs.get("results", []):
            protocol = item.get("protocol")
            if protocol in protocol_readiness:
                protocol_readiness[protocol]["live_runtime_proof"] = (
                    "pass" if item.get("ok") else "fail"
                )
    return {
        "generated_at": utc_timestamp(),
        "protocol_readiness": protocol_readiness,
        "enterprise_scale_readiness": cohorts,
        "usage_metering_ready": all(
            result.get("database_integrity", {}).get("usage_within_tolerance")
            for result in simulation.get("cohorts", [])
        ),
        "api_ready_for_modeled_load": bool(simulation.get("ok")),
        "live_runtime_ready": None if live_proofs is None else bool(live_proofs.get("ok")),
        "overall": (
            "ready_for_modeled_local_scale"
            if simulation.get("ok") and (live_proofs is None or live_proofs.get("ok"))
            else "not_ready"
        ),
    }


def report_markdown(payload: dict[str, Any]) -> str:
    matrix = payload["readiness_matrix"]
    lines = [
        "# SecureWave Linux Enterprise VPN Certification",
        "",
        f"Generated: `{payload['generated_at']}`",
        f"Mode: `{payload['simulation']['mode']}`",
        "",
        "## Executive Summary",
        "",
        f"- Local enterprise simulation: `{'PASS' if payload['simulation']['ok'] else 'FAIL'}`",
        f"- Live runtime proofs: `{matrix['live_runtime_ready'] if matrix['live_runtime_ready'] is not None else 'not_run'}`",
        f"- Overall: `{matrix['overall']}`",
        "",
        "## Enterprise Scale Readiness",
        "",
        "| Cohort | Status | Users Completed | Duration s | Login p95 ms | WG profile p99 ms | Errors |",
        "| --- | --- | ---: | ---: | ---: | ---: | ---: |",
    ]
    for cohort, row in matrix["enterprise_scale_readiness"].items():
        lines.append(
            f"| {cohort} | {row['status']} | {row['users_completed']} | "
            f"{row['duration_seconds']} | {row['p95_login_ms']} | "
            f"{row['p99_profile_wireguard_ms']} | {row['error_count']} |"
        )
    lines.extend(
        [
            "",
            "## Protocol Readiness",
            "",
            "| Protocol | Backend Profile Scale | Live Runtime Proof |",
            "| --- | --- | --- |",
        ]
    )
    for protocol, row in matrix["protocol_readiness"].items():
        lines.append(
            f"| {protocol} | {row['backend_profile_scale']} | {row['live_runtime_proof']} |"
        )
    lines.extend(
        [
            "",
            "## Safety Notes",
            "",
            "- Default execution uses a temporary SQLite database with `TESTING=true`.",
            "- No production users, payment data, VPN private keys, tokens, profile configs, or CA material are written to artifacts.",
            "- Live tunnel proofs require explicit `--include-live-proofs`.",
            "- External load testing is intentionally not automatic; use only against authorized SecureWave-owned infrastructure.",
            "",
            "## Blockers",
            "",
        ]
    )
    blockers = payload.get("blockers") or []
    if blockers:
        lines.extend(f"- {blocker}" for blocker in blockers)
    else:
        lines.append("- None for the safe local certification mode.")
    lines.append("")
    return "\n".join(lines)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--cohorts",
        nargs="+",
        type=int,
        default=list(DEFAULT_COHORTS),
        help="Synthetic user cohort sizes to model locally.",
    )
    parser.add_argument(
        "--workers",
        type=int,
        default=DEFAULT_WORKERS,
        help="Concurrent workers for local TestClient simulation.",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=LATEST_DIR,
        help="Directory for redacted JSON/Markdown artifacts.",
    )
    parser.add_argument(
        "--include-live-proofs",
        action="store_true",
        help="Run non-destructive live runtime proofs for all protocols.",
    )
    parser.add_argument("--live-hold-seconds", type=int, default=30)
    parser.add_argument("--live-evidence-timeout", type=int, default=180)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if any(cohort < 1 or cohort > 1000 for cohort in args.cohorts):
        raise SystemExit("--cohorts must be between 1 and 1000 users")
    if args.workers < 1 or args.workers > 64:
        raise SystemExit("--workers must be between 1 and 64")

    generated_at = utc_timestamp()
    simulation = run_local_enterprise_simulation(args.cohorts, args.workers)
    live_proofs = None
    blockers: list[str] = []
    if args.include_live_proofs:
        live_proofs = run_live_protocol_proofs(
            list(PROTOCOLS),
            args.live_hold_seconds,
            args.live_evidence_timeout,
        )
    else:
        blockers.append(
            "Live WireGuard/OpenVPN/IKEv2 runtime proofs were not run in this harness invocation."
        )
    matrix = readiness_matrix(simulation, live_proofs)
    payload = {
        "generated_at": generated_at,
        "simulation": simulation,
        "live_proofs": live_proofs,
        "readiness_matrix": matrix,
        "blockers": blockers,
    }

    output_dir = args.output_dir
    write_json(output_dir / "certification-summary.json", payload)
    write_json(output_dir / "backend-load-summary.json", simulation)
    write_json(output_dir / "readiness-matrix.json", matrix)
    usage = {
        str(result["cohort_size"]): result["database_integrity"]
        for result in simulation.get("cohorts", [])
    }
    write_json(output_dir / "usage-metering-proof.json", usage)
    if live_proofs is not None:
        write_json(output_dir / "runtime-proof-summary.json", live_proofs)
    write_text(output_dir / "final-report.md", report_markdown(payload))

    print(
        json.dumps(
            {
                "ok": simulation.get("ok") and (live_proofs is None or live_proofs.get("ok")),
                "output_dir": str(output_dir),
                "readiness": matrix["overall"],
                "cohorts": args.cohorts,
                "live_proofs": "run" if live_proofs else "not_run",
            },
            indent=2,
            sort_keys=True,
        )
    )
    return 0 if simulation.get("ok") and (live_proofs is None or live_proofs.get("ok")) else 1


if __name__ == "__main__":
    raise SystemExit(main())
