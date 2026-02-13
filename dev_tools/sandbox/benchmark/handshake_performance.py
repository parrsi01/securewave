#!/usr/bin/env python3
"""WireGuard handshake/profile issuance timing benchmark."""

from __future__ import annotations

import argparse
import json
import os
import sys
import tempfile
import time
import uuid
from pathlib import Path

# Ensure repo root is on sys.path when running as a script.
REPO_ROOT = Path(__file__).resolve().parents[3]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from utils.inprocess_testclient import InProcessTestClient

from dev_tools.sandbox.benchmark.common import ensure_dir, mean, percentile, utc_now_iso, write_csv


def compute_handshake_stats(latencies_ms: list[float]) -> dict:
    if not latencies_ms:
        return {
            "samples": 0,
            "avg_latency_ms": 0.0,
            "p50_latency_ms": 0.0,
            "p95_latency_ms": 0.0,
            "max_latency_ms": 0.0,
            "variance_ms2": 0.0,
        }
    avg = mean(latencies_ms)
    variance = sum((value - avg) ** 2 for value in latencies_ms) / len(latencies_ms)
    return {
        "samples": len(latencies_ms),
        "avg_latency_ms": round(avg, 3),
        "p50_latency_ms": round(percentile(latencies_ms, 50), 3),
        "p95_latency_ms": round(percentile(latencies_ms, 95), 3),
        "max_latency_ms": round(max(latencies_ms), 3),
        "variance_ms2": round(variance, 4),
    }


def _configure_test_env(db_file: Path) -> None:
    os.environ["TESTING"] = "true"
    os.environ["ENVIRONMENT"] = "development"
    os.environ["WG_AUTO_REGISTER_PEERS"] = "false"
    os.environ["DATABASE_URL"] = f"sqlite:///{db_file}"
    os.environ["ACCESS_TOKEN_SECRET"] = "benchmark-access-secret"
    os.environ["REFRESH_TOKEN_SECRET"] = "benchmark-refresh-secret"
    os.environ["REDIS_URL"] = "memory://"
    os.environ["BCRYPT_ROUNDS"] = "4"
    os.environ["SECUREWAVE_MTU_PROBE"] = "false"
    os.environ["LOG_LEVEL"] = "WARNING"
    os.environ["DB_ECHO"] = "false"


def run_benchmark(*, output_dir: Path, iterations: int) -> dict:
    out_dir = ensure_dir(output_dir)

    db_file = Path(tempfile.gettempdir()) / f"securewave_benchmark_handshake_{uuid.uuid4().hex}.db"
    _configure_test_env(db_file)

    import logging
    import database.session as db_session
    from database.session import create_tables, SessionLocal
    from main import app
    from models.user import User
    from models.vpn_server import VPNServer
    from services.hashing_service import hash_password
    from services.jwt_service import create_access_token

    # Silence SQL echo noise for benchmark runs (echo is enabled in non-production by default).
    try:
        db_session.engine.echo = False
    except Exception:
        pass
    logging.getLogger("sqlalchemy.engine").setLevel(logging.WARNING)

    create_tables()

    db = SessionLocal()
    try:
        server = db.query(VPNServer).first()
        if server is None:
            server = VPNServer(
                server_id="bench-ash-001",
                location="Ashburn",
                country="United States",
                country_code="US",
                city="Ashburn",
                region="Americas",
                hcloud_location="ash",
                public_ip="203.0.113.60",
                endpoint="203.0.113.60:51820",
                wg_public_key="dGVzdC1iZW5jaC1zZXJ2ZXIta2V5LTAxMjM0NTY3ODkwMTIzNDU2Nzg5",
                wg_private_key_encrypted="encrypted-bench-server-key",
                status="active",
                health_status="healthy",
                hcloud_server_state="running",
                performance_score=96.0,
                latency_ms=38.0,
            )
            db.add(server)
            db.commit()

        user = User(
            email=f"benchmark-user-{int(time.time())}@example.com",
            hashed_password=hash_password("BenchmarkPass123"),
            email_verified=True,
            is_active=True,
            subscription_status="active",
        )
        db.add(user)
        db.commit()
        db.refresh(user)

        access_token = create_access_token(user)
        headers = {"Authorization": f"Bearer {access_token}"}

        rows: list[dict] = []
        failures = 0
        with InProcessTestClient(app, raise_server_exceptions=False) as client:
            device_id = None
            for iteration in range(1, max(1, iterations) + 1):
                # Reuse the same device to avoid device-limit enforcement skewing benchmark runs.
                payload = {
                    "device_type": "linux",
                    "protocol": "wireguard",
                    "server_id": "bench-ash-001",
                }
                if device_id:
                    payload["device_id"] = device_id
                else:
                    payload["device_name"] = "handshake-bench"
                started = time.perf_counter()
                response = client.post("/api/vpn/profile", headers=headers, json=payload)
                latency_ms = (time.perf_counter() - started) * 1000
                status = "ok" if response.status_code == 200 else "failed"
                if status == "failed":
                    failures += 1
                elif device_id is None:
                    try:
                        body = response.json()
                        device_id = body.get("device_id")
                    except Exception:
                        device_id = None
                rows.append(
                    {
                        "timestamp": utc_now_iso(),
                        "iteration": iteration,
                        "latency_ms": round(latency_ms, 3),
                        "status_code": response.status_code,
                        "status": status,
                    }
                )

        write_csv(
            out_dir / "handshake_times.csv",
            rows,
            ["timestamp", "iteration", "latency_ms", "status_code", "status"],
        )

        latencies = [float(row["latency_ms"]) for row in rows if int(row["status_code"]) == 200]
        stats = compute_handshake_stats(latencies)
        payload = {
            "harness": "handshake_performance",
            "generated_at": utc_now_iso(),
            "overall_status": "pass" if failures == 0 and bool(rows) else "fail",
            "iterations": len(rows),
            "success_count": len(latencies),
            "failure_count": failures,
            "stats": stats,
        }
        (out_dir / "handshake_performance_result.json").write_text(json.dumps(payload, indent=2), encoding="utf-8")
        return payload
    finally:
        db.close()


def main() -> int:
    parser = argparse.ArgumentParser(description="Run repeated WireGuard handshake/profile benchmark")
    parser.add_argument("--output-dir", default="artifacts/benchmark")
    parser.add_argument("--iterations", type=int, default=60)
    args = parser.parse_args()

    payload = run_benchmark(output_dir=Path(args.output_dir), iterations=args.iterations)
    print(json.dumps(payload, indent=2))
    return 0 if payload["overall_status"] == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
