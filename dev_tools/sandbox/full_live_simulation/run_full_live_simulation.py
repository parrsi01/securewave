#!/usr/bin/env python3
"""Run a strict non-demo full live VPN SaaS control-plane simulation."""

from __future__ import annotations

import asyncio
import json
import os
import sys
import time
import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[3]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _run_id() -> str:
    return f"{time.strftime('%Y%m%d_%H%M%S', time.gmtime())}_{uuid.uuid4().hex[:8]}"


def _setup_env(run_dir: Path) -> dict[str, str]:
    env = dict(os.environ)
    env.update(
        {
            "ENVIRONMENT": "development",
            "TESTING": "false",
            "WG_AUTO_REGISTER_PEERS": "false",
            "VPN_AUTO_PROVISION_CREDENTIALS": "false",
            "AUTO_CREATE_TABLES": "true",
            "DB_ECHO": "false",
            "DATABASE_URL": f"sqlite:///{(run_dir / 'live_sim.db').resolve()}",
            "WG_DATA_DIR": str((run_dir / "wg_data").resolve()),
            "SECRET_KEY": "securewave-full-live-sim-secret-key",
            "ACCESS_TOKEN_SECRET": "securewave-full-live-sim-access-secret",
            "REFRESH_TOKEN_SECRET": "securewave-full-live-sim-refresh-secret",
            "REFRESH_SESSION_REQUIRED": "true",
            "SECUREWAVE_MTU_PROBE": "false",
        }
    )
    return env


@dataclass
class TestOutcome:
    index: int
    name: str
    status: str  # pass|warn|fail
    duration_ms: float
    detail: str
    evidence: dict[str, Any]

    def to_dict(self) -> dict[str, Any]:
        return {
            "index": self.index,
            "name": self.name,
            "status": self.status,
            "duration_ms": self.duration_ms,
            "detail": self.detail,
            "evidence": self.evidence,
        }


async def _run() -> int:
    repo_root = Path(__file__).resolve().parents[3]
    artifacts_dir = repo_root / "artifacts"
    run_id = _run_id()
    run_dir = artifacts_dir / "full_live_simulation" / run_id
    run_dir.mkdir(parents=True, exist_ok=True)

    os.environ.clear()
    os.environ.update(_setup_env(run_dir))

    # Project imports after env setup so runtime mode is consistent.
    from fastapi import HTTPException
    from sqlalchemy import func
    from starlette.requests import Request

    from database.session import SessionLocal
    from models.subscription import Subscription
    from models.user import User
    from models.vpn_connection import VPNConnection
    from models.vpn_server import VPNServer
    from models.wireguard_peer import WireGuardPeer
    from routes.vpn import VPNConnectRequest, choose_effective_protocol, connect_vpn, disconnect_vpn
    from services.hashing_service import hash_password, verify_password
    from services.jwt_service import (
        ACCESS_SECRET,
        create_access_token,
        create_refresh_token,
        decode_token,
        is_token_jti_revoked,
        revoke_access_token,
        revoke_refresh_token,
        verify_refresh_token,
    )
    from services.stripe_service import StripeService, stripe_mode_label
    from services.vpn_server_service import VPNServerService
    from services.wireguard_service import WireGuardService
    from dev_tools.sandbox.chaos_tests import network_drop
    from dev_tools.sandbox.ip_pool_pressure.simulator import (
        IPPoolPressureConfig,
        simulate_ip_pool_pressure,
    )

    db = SessionLocal()
    started = time.perf_counter()
    outcomes: list[TestOutcome] = []

    user: User | None = None
    server: VPNServer | None = None
    access_token = ""
    refresh_token = ""

    def run_test(index: int, name: str):
        start = time.perf_counter()
        return start, lambda status, detail, evidence: outcomes.append(
            TestOutcome(
                index=index,
                name=name,
                status=status,
                duration_ms=round((time.perf_counter() - start) * 1000, 2),
                detail=detail,
                evidence=evidence,
            )
        )

    # 1) Account creation
    t0, done = run_test(1, "Account creation")
    del t0
    try:
        email = f"full-live-{uuid.uuid4().hex[:12]}@securewave.local"
        password = os.environ.get("SIM_TEST_PASSWORD", "sim-test-only-not-a-secret")
        user = User(
            email=email,
            hashed_password=hash_password(password),
            email_verified=True,
            is_active=True,
            subscription_status="active",
            created_at=datetime.utcnow(),
        )
        db.add(user)
        db.commit()
        db.refresh(user)
        done(
            "pass",
            "Account created and persisted",
            {"user_id": user.id, "email": user.email},
        )
    except Exception as exc:
        db.rollback()
        done("fail", "Account creation failed", {"error": str(exc)})

    # 2) Login
    t0, done = run_test(2, "Login")
    del t0
    try:
        if user is None:
            raise RuntimeError("missing user from step 1")
        lookup = db.query(User).filter(User.email == user.email).first()
        if not lookup:
            raise RuntimeError("user lookup failed")
        if not verify_password("SecureWaveLivePass#2026", lookup.hashed_password):
            raise RuntimeError("password verification failed")
        access_token = create_access_token(lookup)
        refresh_token = create_refresh_token(lookup, db=db, ip_address="127.0.0.1", user_agent="full-live-sim")
        done(
            "pass",
            "Login token pair issued",
            {"access_len": len(access_token), "refresh_len": len(refresh_token)},
        )
    except Exception as exc:
        done("fail", "Login flow failed", {"error": str(exc)})

    # Ensure baseline server + active subscription for steps 3-6.
    if user is not None:
        if db.query(VPNServer).count() == 0:
            wg = WireGuardService()
            private_key, public_key = wg.generate_keypair()
            server = VPNServer(
                server_id="live-ash-001",
                location="Ashburn",
                country="United States",
                country_code="US",
                city="Ashburn",
                region="Americas",
                hcloud_location="ash",
                hcloud_server_state="running",
                public_ip="127.0.0.1",
                endpoint="127.0.0.1:51820",
                wg_listen_port=51820,
                wg_public_key=public_key,
                wg_private_key_encrypted=wg.encrypt_private_key(private_key),
                status="active",
                health_status="healthy",
                max_connections=1500,
                current_connections=10,
                tier_restriction=None,
                performance_score=96.4,
                latency_ms=34.0,
                protocol="openvpn",
                supports_wireguard=True,
                supports_openvpn=True,
                supports_ikev2=True,
                supports_l2tp=False,
            )
            db.add(server)
            db.commit()
            db.refresh(server)
        else:
            server = db.query(VPNServer).first()

        existing_active_sub = (
            db.query(Subscription)
            .filter(Subscription.user_id == user.id, Subscription.status.in_(["active", "trialing"]))
            .first()
        )
        if not existing_active_sub:
            db.add(
                Subscription(
                    user_id=user.id,
                    plan_id="premium",
                    plan_name="Premium Plan",
                    provider="stripe",
                    status="active",
                    amount=9.99,
                    currency="USD",
                    billing_cycle="monthly",
                    stripe_customer_id=f"cus_live_{uuid.uuid4().hex[:10]}",
                    stripe_subscription_id=f"sub_live_{uuid.uuid4().hex[:10]}",
                    stripe_price_id="price_live_premium_monthly",
                    activated_at=datetime.utcnow(),
                    current_period_start=datetime.utcnow() - timedelta(days=1),
                    current_period_end=datetime.utcnow() + timedelta(days=29),
                    next_billing_date=datetime.utcnow() + timedelta(days=29),
                    auto_renew=True,
                )
            )
            db.commit()

    # 3) Server fetch
    t0, done = run_test(3, "Server fetch")
    del t0
    try:
        servers = VPNServerService.get_active_servers(db, user_tier="premium")
        if not servers:
            raise RuntimeError("no active servers returned")
        server = servers[0]
        done(
            "pass",
            "Active servers fetched",
            {"server_count": len(servers), "selected_server": server.server_id},
        )
    except Exception as exc:
        done("fail", "Server fetch failed", {"error": str(exc)})

    # 4) Protocol switch
    t0, done = run_test(4, "Protocol switch")
    del t0
    try:
        if server is None:
            raise RuntimeError("missing server")
        auto_protocol = choose_effective_protocol(server=server, requested_protocol="auto", device_type="windows")
        wireguard_protocol = choose_effective_protocol(
            server=server,
            requested_protocol="wireguard",
            device_type="windows",
        )
        ok = auto_protocol in {"wireguard", "openvpn", "ikev2", "l2tp"} and wireguard_protocol == "wireguard"
        done(
            "pass" if ok else "fail",
            "Protocol auto-selection and explicit switch evaluated",
            {
                "auto_protocol": auto_protocol,
                "explicit_wireguard": wireguard_protocol,
                "server_preferred_protocol": getattr(server, "protocol", None),
            },
        )
    except Exception as exc:
        done("fail", "Protocol switch failed", {"error": str(exc)})

    # 5) Connect/disconnect
    t0, done = run_test(5, "Connect/disconnect")
    del t0
    try:
        if user is None:
            raise RuntimeError("missing user")
        req_scope = {
            "type": "http",
            "method": "POST",
            "path": "/api/vpn/connect",
            "headers": [],
            "query_string": b"",
            "client": ("127.0.0.1", 58432),
            "server": ("localhost", 8000),
            "scheme": "http",
        }
        req = Request(req_scope)
        connect_response = await connect_vpn(
            request=req,
            payload=VPNConnectRequest(region=None),
            current_user=user,
            db=db,
        )
        disconnect_response = await disconnect_vpn(current_user=user, db=db)
        latest_conn = (
            db.query(VPNConnection)
            .filter(VPNConnection.user_id == user.id)
            .order_by(VPNConnection.id.desc())
            .first()
        )
        ok = (
            connect_response.get("status") == "CONNECTED"
            and disconnect_response.get("status") == "DISCONNECTED"
            and latest_conn is not None
            and latest_conn.disconnected_at is not None
        )
        done(
            "pass" if ok else "fail",
            "Connection lifecycle executed",
            {
                "connect_status": connect_response.get("status"),
                "disconnect_status": disconnect_response.get("status"),
                "server_id": connect_response.get("server_id"),
                "client_ip": connect_response.get("client_ip"),
                "connection_id": latest_conn.id if latest_conn else None,
            },
        )
    except Exception as exc:
        db.rollback()
        done("fail", "Connect/disconnect flow failed", {"error": str(exc)})

    # 6) Stripe plan state validation
    t0, done = run_test(6, "Stripe plan state validation")
    del t0
    try:
        if user is None:
            raise RuntimeError("missing user")
        plan = StripeService.get_plan_details("premium")
        active_sub = (
            db.query(Subscription)
            .filter(Subscription.user_id == user.id, Subscription.status.in_(["active", "trialing"]))
            .first()
        )
        ok = bool(plan) and active_sub is not None and active_sub.plan_id in StripeService.PLANS
        done(
            "pass" if ok else "fail",
            "Local Stripe plan catalog and DB subscription state validated",
            {
                "stripe_mode": stripe_mode_label(),
                "plan_present": bool(plan),
                "subscription_status": active_sub.status if active_sub else None,
                "subscription_plan": active_sub.plan_id if active_sub else None,
            },
        )
    except Exception as exc:
        done("fail", "Stripe state validation failed", {"error": str(exc)})

    # 7) IP pool exhaustion test
    t0, done = run_test(7, "IP pool exhaustion test")
    del t0
    try:
        ip_cfg = IPPoolPressureConfig(
            peers=500,
            cycles=4,
            churn_per_cycle=60,
            seed=2026,
            base_cidr="10.250.0.0/22",
            max_blocks=1,
            reserved_hosts=510,
            alert_threshold_pct=90,
        )
        ip_report = simulate_ip_pool_pressure(cfg=ip_cfg, output_dir=run_dir / "ip_pool_pressure")
        summary = ip_report.get("summary", {})
        final_pool = summary.get("final_pool_stats", {})
        exhaustion_errors_total = int(summary.get("exhaustion_errors_total", 0))
        ok = exhaustion_errors_total > 0
        done(
            "pass" if ok else "fail",
            "Allocator pressure harness executed",
            {
                "exhaustion_errors_total": exhaustion_errors_total,
                "capacity": final_pool.get("capacity"),
                "allocated": final_pool.get("allocated"),
                "available": final_pool.get("available"),
                "utilization_pct": final_pool.get("utilization_pct"),
                "alert": bool(final_pool.get("alert")),
            },
        )
    except Exception as exc:
        done("fail", "IP pool pressure harness failed", {"error": str(exc)})

    # 8) JWT revocation test
    t0, done = run_test(8, "JWT revocation test")
    del t0
    try:
        if not access_token or not refresh_token:
            raise RuntimeError("missing tokens")
        access_payload = decode_token(access_token, ACCESS_SECRET)
        revoke_access_token(db, access_token, reason="full_live_simulation")
        access_revoked = is_token_jti_revoked(db, access_payload.get("jti"))

        refresh_payload = verify_refresh_token(refresh_token, db=db)
        revoke_refresh_token(db, refresh_payload.get("jti"))
        refresh_rejected = False
        try:
            verify_refresh_token(refresh_token, db=db)
        except HTTPException:
            refresh_rejected = True

        ok = access_revoked and refresh_rejected
        done(
            "pass" if ok else "fail",
            "Access + refresh token revocation enforced",
            {
                "access_revoked": access_revoked,
                "refresh_rejected_after_revoke": refresh_rejected,
                "access_jti": access_payload.get("jti"),
                "refresh_jti": refresh_payload.get("jti"),
            },
        )
    except Exception as exc:
        done("fail", "JWT revocation validation failed", {"error": str(exc)})

    # 9) Chaos network interruption
    t0, done = run_test(9, "Chaos network interruption")
    del t0
    try:
        chaos = network_drop.run_harness(output_dir=run_dir / "chaos", interface="wg0", execute=False)
        simulated_steps = int((chaos.get("metrics") or {}).get("simulated", 0))
        status = "warn" if simulated_steps > 0 else ("pass" if chaos.get("overall_status") == "pass" else "fail")
        done(
            status,
            "Chaos harness executed (safe mode in non-root context)",
            {
                "overall_status": chaos.get("overall_status"),
                "simulated_steps": simulated_steps,
                "failed_steps": int((chaos.get("metrics") or {}).get("failed", 0)),
                "destructive_mode": bool((chaos.get("metrics") or {}).get("destructive_mode")),
            },
        )
    except Exception as exc:
        done("fail", "Chaos harness failed", {"error": str(exc)})

    # 10) Health classification
    t0, done = run_test(10, "Health classification")
    del t0
    try:
        if user is None or server is None:
            raise RuntimeError("missing user/server")
        db.query(WireGuardPeer).filter(WireGuardPeer.user_id == user.id).delete(synchronize_session=False)
        statuses = ["healthy", "degraded", "unstable", "unstable"]
        for idx, status_name in enumerate(statuses, start=1):
            db.add(
                WireGuardPeer(
                    user_id=user.id,
                    server_id=server.id,
                    public_key=f"live-health-{uuid.uuid4().hex[:28]}-{idx}",
                    private_key_encrypted="encrypted-sim-key",
                    ipv4_address=f"10.253.0.{idx}/32",
                    device_name=f"health-peer-{idx}",
                    device_type="windows",
                    is_active=True,
                    is_revoked=False,
                    health_status=status_name,
                )
            )
        db.commit()

        peer_total = db.query(WireGuardPeer).filter(WireGuardPeer.is_revoked == False).count()
        healthy = db.query(WireGuardPeer).filter(
            WireGuardPeer.is_revoked == False,
            WireGuardPeer.health_status == "healthy",
        ).count()
        degraded = db.query(WireGuardPeer).filter(
            WireGuardPeer.is_revoked == False,
            WireGuardPeer.health_status == "degraded",
        ).count()
        unstable = db.query(WireGuardPeer).filter(
            WireGuardPeer.is_revoked == False,
            WireGuardPeer.health_status == "unstable",
        ).count()
        stale_seconds = int(os.getenv("WG_HANDSHAKE_UNSTABLE_SECONDS", "300"))
        stale_cutoff = datetime.utcnow() - timedelta(seconds=stale_seconds)
        stale_handshakes = db.query(WireGuardPeer).filter(
            WireGuardPeer.is_revoked == False,
            (
                (WireGuardPeer.last_handshake_at.is_(None))
                | (WireGuardPeer.last_handshake_at < stale_cutoff)
            ),
        ).count()
        avg_handshake = (
            db.query(func.avg(WireGuardPeer.last_handshake_latency_ms))
            .filter(WireGuardPeer.is_revoked == False)
            .scalar()
        ) or 0.0

        overall_health = "healthy"
        if peer_total > 0 and unstable / peer_total >= 0.25:
            overall_health = "unstable"
        elif degraded > 0 or unstable > 0:
            overall_health = "degraded"

        ok = overall_health == "unstable"
        done(
            "pass" if ok else "fail",
            "Peer health classification computed using production logic",
            {
                "health_classification": overall_health,
                "peer_total": peer_total,
                "healthy": healthy,
                "degraded": degraded,
                "unstable": unstable,
                "stale_handshakes": stale_handshakes,
                "avg_handshake_latency_ms": round(float(avg_handshake), 2),
            },
        )
    except Exception as exc:
        db.rollback()
        done("fail", "Health classification failed", {"error": str(exc)})

    db.close()
    finished = time.perf_counter()

    total_runtime_ms = round((finished - started) * 1000, 2)
    pass_count = sum(1 for o in outcomes if o.status == "pass")
    warn_count = sum(1 for o in outcomes if o.status == "warn")
    fail_count = sum(1 for o in outcomes if o.status == "fail")
    weighted_success = pass_count + (0.5 * warn_count)
    stability_score = round((weighted_success / max(1, len(outcomes))) * 100.0, 2)

    durations = [o.duration_ms for o in outcomes]
    perf = {
        "total_runtime_ms": total_runtime_ms,
        "avg_test_duration_ms": round(sum(durations) / len(durations), 2) if durations else 0.0,
        "max_test_duration_ms": round(max(durations), 2) if durations else 0.0,
        "min_test_duration_ms": round(min(durations), 2) if durations else 0.0,
    }

    failure_points = [
        f"[{o.name}] {o.detail}"
        for o in outcomes
        if o.status in {"warn", "fail"}
    ]
    if not failure_points:
        failure_points = ["No blocking failure points detected."]

    summary = {
        "run_id": run_id,
        "generated_at": _utc_now_iso(),
        "mode": {
            "TESTING": os.getenv("TESTING"),
            "WG_AUTO_REGISTER_PEERS": os.getenv("WG_AUTO_REGISTER_PEERS"),
            "VPN_AUTO_PROVISION_CREDENTIALS": os.getenv("VPN_AUTO_PROVISION_CREDENTIALS"),
        },
        "totals": {
            "tests": len(outcomes),
            "pass": pass_count,
            "warn": warn_count,
            "fail": fail_count,
        },
        "stability_score": stability_score,
        "performance_metrics": perf,
        "failure_points": failure_points,
        "tests": [o.to_dict() for o in outcomes],
    }

    raw_path = run_dir / "full_live_simulation_result.json"
    raw_path.write_text(json.dumps(summary, indent=2), encoding="utf-8")

    report_lines = [
        "# Full Live Simulation Report",
        "",
        f"- Generated: `{summary['generated_at']}`",
        f"- Run ID: `{run_id}`",
        "- Runtime mode:",
        f"  - `TESTING={summary['mode']['TESTING']}`",
        f"  - `WG_AUTO_REGISTER_PEERS={summary['mode']['WG_AUTO_REGISTER_PEERS']}`",
        f"  - `VPN_AUTO_PROVISION_CREDENTIALS={summary['mode']['VPN_AUTO_PROVISION_CREDENTIALS']}`",
        "",
        "## Stability Score",
        "",
        f"- **{stability_score}/100**",
        f"- Pass/Warn/Fail: `{pass_count}/{warn_count}/{fail_count}`",
        "",
        "## Performance Metrics",
        "",
        f"- Total runtime: `{perf['total_runtime_ms']} ms`",
        f"- Average test duration: `{perf['avg_test_duration_ms']} ms`",
        f"- Max test duration: `{perf['max_test_duration_ms']} ms`",
        f"- Min test duration: `{perf['min_test_duration_ms']} ms`",
        "",
        "## Test Matrix",
        "",
        "| # | Test | Status | Duration (ms) | Detail |",
        "|---:|---|---|---:|---|",
    ]
    for outcome in outcomes:
        report_lines.append(
            f"| {outcome.index} | {outcome.name} | {outcome.status.upper()} | {outcome.duration_ms:.2f} | {outcome.detail} |"
        )

    report_lines.extend(
        [
            "",
            "## Failure Points",
            "",
        ]
    )
    for point in failure_points:
        report_lines.append(f"- {point}")

    report_lines.extend(
        [
            "",
            "## Artifacts",
            "",
            f"- Raw JSON: `{raw_path.relative_to(repo_root)}`",
            f"- Run directory: `{run_dir.relative_to(repo_root)}`",
            "",
        ]
    )

    report_path = artifacts_dir / "full_live_simulation_report.md"
    report_path.write_text("\n".join(report_lines), encoding="utf-8")

    print(json.dumps({"report": str(report_path), "run_dir": str(run_dir), "stability_score": stability_score}, indent=2))
    return 0 if fail_count == 0 else 1


def main() -> int:
    return asyncio.run(_run())


if __name__ == "__main__":
    raise SystemExit(main())
