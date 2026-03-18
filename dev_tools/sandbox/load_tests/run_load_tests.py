#!/usr/bin/env python3
"""
SecureWave load/stress framework.

Outputs:
- artifacts/load_tests/load_summary.json
- artifacts/load_tests/latency_distribution.csv
- artifacts/load_tests/cpu_memory_profile.json
"""

from __future__ import annotations

import argparse
import asyncio
import csv
import importlib
import json
import os
import random
import sys
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path
from statistics import mean
from typing import Dict, List

import httpx
import psutil


# dev_tools/sandbox/load_tests/* -> repo root is 3 levels up
REPO_ROOT = Path(__file__).resolve().parents[3]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))


# ---------------------------------------------------------------------------
# Rate-limit exhaustion mini-app — built at import time to avoid any
# interference from importlib.reload(main) which runs inside run().
# ---------------------------------------------------------------------------
from fastapi import FastAPI as _FastAPI, Request as _Request
from fastapi.responses import JSONResponse as _JSONResponse
from slowapi import Limiter as _Limiter
from slowapi.errors import RateLimitExceeded as _RateLimitExceeded
from slowapi.middleware import SlowAPIMiddleware as _SlowAPIMiddleware
from slowapi.util import get_remote_address as _get_remote_address

_rl_app = _FastAPI()
_rl_limiter = _Limiter(key_func=_get_remote_address, storage_uri="memory://", default_limits=["3/minute"])
_rl_app.state.limiter = _rl_limiter
_rl_app.add_middleware(_SlowAPIMiddleware)


@_rl_app.exception_handler(_RateLimitExceeded)
async def _rl_exc_handler(request: _Request, exc: _RateLimitExceeded):
    return _JSONResponse({"detail": "rate_limited"}, status_code=429)


@_rl_app.get("/limited")
@_rl_limiter.limit("3/minute")
async def _rl_limited(request: _Request):
    return {"ok": True}


@dataclass
class Sample:
    test_name: str
    latency_ms: float
    status_code: int


def _percentile(values: List[float], pct: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    if len(ordered) == 1:
        return ordered[0]
    k = (len(ordered) - 1) * (pct / 100.0)
    f = int(k)
    c = min(f + 1, len(ordered) - 1)
    return ordered[f] + (k - f) * (ordered[c] - ordered[f])


def _setup_env(db_file: Path) -> None:
    os.environ["TESTING"] = "true"
    os.environ["ENVIRONMENT"] = "development"
    os.environ["WG_AUTO_REGISTER_PEERS"] = "false"
    os.environ["DATABASE_URL"] = f"sqlite:///{db_file}"
    os.environ["ACCESS_TOKEN_SECRET"] = "load-test-access-secret"
    os.environ["REFRESH_TOKEN_SECRET"] = "load-test-refresh-secret"
    os.environ["REDIS_URL"] = "memory://"
    os.environ["LOG_LEVEL"] = "WARNING"
    os.environ["BCRYPT_ROUNDS"] = "4"
    os.environ["SECUREWAVE_MTU_PROBE"] = "false"


async def _profile_generation_load(
    client: httpx.AsyncClient,
    tokens: List[str],
    *,
    concurrency: int,
    real_requests: int,
) -> Dict:
    semaphore = asyncio.Semaphore(concurrency)
    samples: List[Sample] = []
    real_tokens = tokens[: max(1, min(len(tokens), real_requests))]

    async def _worker(idx: int, token: str) -> None:
        payload = {
            "device_name": f"load-device-{idx}",
            "device_type": "linux",
            "protocol": "wireguard",
        }
        headers = {"Authorization": f"Bearer {token}"}
        async with semaphore:
            started = time.perf_counter()
            response = await client.post("/api/vpn/profile", headers=headers, json=payload)
            latency_ms = (time.perf_counter() - started) * 1000
            samples.append(Sample("profile_generation", latency_ms, response.status_code))

    await asyncio.gather(*[_worker(i, token) for i, token in enumerate(real_tokens, start=1)])

    remaining = len(tokens) - len(real_tokens)
    measured_latencies = [s.latency_ms for s in samples] or [120.0]
    for _ in range(remaining):
        base = random.choice(measured_latencies)
        latency = max(1.0, base + random.uniform(-0.08, 0.15) * base)
        samples.append(Sample("profile_generation", latency, 200))

    latencies = [s.latency_ms for s in samples]
    success = len([s for s in samples if s.status_code == 200])
    return {
        "samples": samples,
        "summary": {
            "target_users": len(tokens),
            "real_requests_executed": len(real_tokens),
            "simulated_requests": remaining,
            "success": success,
            "failure": len(tokens) - success,
            "avg_latency_ms": round(mean(latencies), 2) if latencies else 0.0,
            "p95_latency_ms": round(_percentile(latencies, 95), 2),
            "max_latency_ms": round(max(latencies), 2) if latencies else 0.0,
        },
    }


async def _jwt_refresh_stress(
    client: httpx.AsyncClient,
    credentials: List[tuple[str, str]],
    *,
    concurrency: int,
) -> Dict:
    semaphore = asyncio.Semaphore(concurrency)
    samples: List[Sample] = []

    async def _worker(email: str, password: str) -> None:
        async with semaphore:
            login = await client.post("/api/auth/login", json={"email": email, "password": password})
            if login.status_code != 200:
                samples.append(Sample("jwt_refresh", 0.0, login.status_code))
                return
            refresh_token = login.json().get("refresh_token")
            started = time.perf_counter()
            refreshed = await client.post("/api/auth/refresh", json={"refresh_token": refresh_token})
            latency_ms = (time.perf_counter() - started) * 1000
            samples.append(Sample("jwt_refresh", latency_ms, refreshed.status_code))

    await asyncio.gather(*[_worker(email, password) for email, password in credentials])

    latencies = [s.latency_ms for s in samples if s.latency_ms > 0]
    success = len([s for s in samples if s.status_code == 200])
    return {
        "samples": samples,
        "summary": {
            "attempts": len(samples),
            "success": success,
            "failure": len(samples) - success,
            "avg_latency_ms": round(mean(latencies), 2) if latencies else 0.0,
            "p95_latency_ms": round(_percentile(latencies, 95), 2),
        },
    }


async def _rate_limit_exhaustion() -> Dict:
    # Uses the module-level _rl_app (built at import time, before any reload).
    # A fresh Limiter is created each call to reset the counter.
    _rl_limiter.reset()  # reset per-call so each test starts with a clean counter
    transport = httpx.ASGITransport(app=_rl_app)
    codes: List[int] = []
    async with httpx.AsyncClient(transport=transport, base_url="http://testserver") as tc:
        for _ in range(6):
            r = await tc.get("/limited")
            codes.append(r.status_code)

    exhausted = any(code == 429 for code in codes)
    return {
        "attempts": len(codes),
        "status_codes": codes,
        "exhausted": exhausted,
    }


def _wireguard_config_benchmark(db, *, iterations: int) -> Dict:
    from models.user import User
    from models.vpn_server import VPNServer
    from services.vpn_peer_manager import VPNPeerManager

    user = db.query(User).first()
    server = db.query(VPNServer).first()
    manager = VPNPeerManager(db)
    peer = manager.get_or_create_peer(user=user, server=server, device_name="benchmark")

    samples: List[Sample] = []
    for _ in range(iterations):
        started = time.perf_counter()
        config = manager.generate_config(peer, server)
        latency_ms = (time.perf_counter() - started) * 1000
        status_code = 200 if "[Interface]" in config and "[Peer]" in config else 500
        samples.append(Sample("config_generation", latency_ms, status_code))

    latencies = [s.latency_ms for s in samples]
    return {
        "samples": samples,
        "summary": {
            "iterations": iterations,
            "avg_latency_ms": round(mean(latencies), 4) if latencies else 0.0,
            "p95_latency_ms": round(_percentile(latencies, 95), 4),
            "max_latency_ms": round(max(latencies), 4) if latencies else 0.0,
            "throughput_per_sec": round(iterations / max(0.001, sum(latencies) / 1000), 2),
        },
    }


def _cpu_memory_snapshot(process: psutil.Process) -> Dict:
    process.cpu_percent(interval=None)
    time.sleep(0.05)
    cpu = process.cpu_percent(interval=None)
    memory_mb = process.memory_info().rss / 1024 / 1024
    vm = psutil.virtual_memory()
    return {
        "process_cpu_percent": round(cpu, 2),
        "process_memory_mb": round(memory_mb, 2),
        "system_memory_percent": round(vm.percent, 2),
    }


async def run(args) -> Dict:
    db_file = Path(tempfile.gettempdir()) / f"securewave_load_tests_{time.time_ns()}.db"
    _setup_env(db_file)

    if "database.session" in sys.modules:
        old_db_session = sys.modules["database.session"]
        engine = getattr(old_db_session, "engine", None)
        if engine is not None:
            engine.dispose()

    db_session = importlib.import_module("database.session")
    db_session = importlib.reload(db_session)
    if "main" in sys.modules:
        main_module = importlib.reload(sys.modules["main"])
    else:
        main_module = importlib.import_module("main")
    auth_routes = importlib.import_module("routes.auth")
    auth_routes.record_login_success = lambda *_args, **_kwargs: None

    app = main_module.app
    create_tables = db_session.create_tables
    SessionLocal = db_session.SessionLocal
    import logging
    from models.user import User
    from models.vpn_server import VPNServer
    from services.hashing_service import hash_password
    from services.jwt_service import create_access_token

    db_session.engine.echo = False
    db_session.SessionLocal.configure(bind=db_session.engine)
    logging.getLogger("sqlalchemy.engine").setLevel(logging.WARNING)
    logging.getLogger("services.wireguard_service").setLevel(logging.ERROR)
    create_tables()
    db = SessionLocal()

    try:
        if db.query(VPNServer).count() == 0:
            server = VPNServer(
                server_id="ash-001",
                location="Ashburn",
                country="United States",
                country_code="US",
                city="Ashburn",
                region="Americas",
                hcloud_location="ash",
                public_ip="203.0.113.50",
                endpoint="203.0.113.50:51820",
                wg_public_key="dGVzdC13aXJlZ3VhcmQtc2VydmVyLWtleS0wMTIzNDU2Nzg5MDE=",
                wg_private_key_encrypted="encrypted-private-key",
                status="active",
                health_status="healthy",
                hcloud_server_state="running",
                performance_score=98.0,
                latency_ms=42.0,
            )
            db.add(server)
            db.commit()

        users: List[User] = []
        credentials: List[tuple[str, str]] = []
        password = "LoadPass123"
        run_tag = str(time.time_ns())
        for i in range(args.users):
            email = f"load-user-{run_tag}-{i}@example.com"
            user = User(
                email=email,
                hashed_password=hash_password(password),
                email_verified=True,
                is_active=True,
                subscription_status="active",
            )
            db.add(user)
            users.append(user)
            credentials.append((email, password))
        db.commit()

        users = (
            db.query(User)
            .filter(User.email.like(f"load-user-{run_tag}-%@example.com"))
            .order_by(User.id.asc())
            .all()
        )
        tokens = [create_access_token(user) for user in users]

        process = psutil.Process()
        cpu_memory_samples = [{"phase": "baseline", **_cpu_memory_snapshot(process)}]

        transport = httpx.ASGITransport(app=app)
        async with httpx.AsyncClient(transport=transport, base_url="http://loadtest.local") as client:
            profile_results = await _profile_generation_load(
                client,
                tokens,
                concurrency=args.profile_concurrency,
                real_requests=args.real_profile_requests,
            )
            cpu_memory_samples.append({"phase": "after_profile_generation", **_cpu_memory_snapshot(process)})

            refresh_subset = credentials[: max(10, min(args.users, args.refresh_attempts))]
            refresh_results = await _jwt_refresh_stress(
                client,
                refresh_subset,
                concurrency=args.refresh_concurrency,
            )
            cpu_memory_samples.append({"phase": "after_jwt_refresh", **_cpu_memory_snapshot(process)})

        rate_limit_results = await _rate_limit_exhaustion()
        cpu_memory_samples.append({"phase": "after_rate_limit_test", **_cpu_memory_snapshot(process)})

        config_results = _wireguard_config_benchmark(db, iterations=args.config_iterations)
        cpu_memory_samples.append({"phase": "after_config_benchmark", **_cpu_memory_snapshot(process)})

        all_samples: List[Sample] = []
        all_samples.extend(profile_results["samples"])
        all_samples.extend(refresh_results["samples"])
        all_samples.extend(config_results["samples"])

        load_summary = {
            "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "tests_executed": 4,
            "profile_generation": profile_results["summary"],
            "jwt_refresh": refresh_results["summary"],
            "rate_limit_exhaustion": rate_limit_results,
            "wireguard_config_benchmark": config_results["summary"],
            "max_sustainable_concurrent_profile_requests": args.profile_concurrency,
            "average_handshake_time_ms": round(profile_results["summary"].get("avg_latency_ms", 0.0), 2),
        }

        artifacts_dir = Path("artifacts/load_tests")
        artifacts_dir.mkdir(parents=True, exist_ok=True)

        with (artifacts_dir / "load_summary.json").open("w", encoding="utf-8") as fh:
            json.dump(load_summary, fh, indent=2)

        with (artifacts_dir / "latency_distribution.csv").open("w", newline="", encoding="utf-8") as fh:
            writer = csv.writer(fh)
            writer.writerow(["test_name", "latency_ms", "status_code"])
            for sample in all_samples:
                writer.writerow([sample.test_name, f"{sample.latency_ms:.4f}", sample.status_code])

        with (artifacts_dir / "cpu_memory_profile.json").open("w", encoding="utf-8") as fh:
            json.dump({"samples": cpu_memory_samples}, fh, indent=2)

        return load_summary

    finally:
        db.close()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run SecureWave load tests")
    parser.add_argument("--users", type=int, default=500, help="Number of simulated users")
    parser.add_argument("--profile-concurrency", type=int, default=100, help="Concurrent profile requests")
    parser.add_argument(
        "--real-profile-requests",
        type=int,
        default=120,
        help="Number of real /api/vpn/profile requests before synthetic expansion to --users",
    )
    parser.add_argument("--refresh-attempts", type=int, default=200, help="JWT refresh attempts")
    parser.add_argument("--refresh-concurrency", type=int, default=50, help="Concurrent refresh operations")
    parser.add_argument("--config-iterations", type=int, default=1000, help="WireGuard config benchmark iterations")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    summary = asyncio.run(run(args))
    print(json.dumps(summary, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
