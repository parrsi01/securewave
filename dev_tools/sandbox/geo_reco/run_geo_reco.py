#!/usr/bin/env python3
"""
Generate geo recommendation artifacts (Barbados/EU corridor).

This is a local/offline harness: it seeds a tiny in-memory DB with a few
servers + RTT samples and runs the same recommendation logic used by the API.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from datetime import datetime
from pathlib import Path

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

# dev_tools/sandbox/geo_reco/* -> repo root is 3 levels up
REPO_ROOT = Path(__file__).resolve().parents[3]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from database.base import Base
from models.vpn_server import VPNServer
from models.vpn_server_rtt_sample import VPNServerRTTSample
from services.geo_recommendation import recommend_server


def _utc_now_iso() -> str:
    return datetime.utcnow().isoformat() + "Z"


def _seed_server(db, *, server_id: str, region: str, latency_ms: float, current_connections: int) -> VPNServer:
    server = VPNServer(
        server_id=server_id,
        location="Test",
        country="Testland",
        country_code="TT",
        city="Test City",
        region=region,
        hcloud_location="ash",
        public_ip="203.0.113.10",
        endpoint="203.0.113.10:51820",
        wg_public_key="dGVzdC1zZXJ2ZXItcHVibGljLWtleS1iYXNlNjQ=",
        wg_private_key_encrypted="encrypted-test-key",
        status="active",
        health_status="healthy",
        hcloud_server_state="running",
        max_connections=1000,
        current_connections=current_connections,
        performance_score=90.0,
        latency_ms=latency_ms,
    )
    db.add(server)
    db.commit()
    db.refresh(server)
    return server


def _seed_rtt_samples(db, *, server: VPNServer, values: list[float]) -> None:
    now = datetime.utcnow()
    for value in values:
        db.add(
            VPNServerRTTSample(
                vpn_server_id=server.id,
                observed_at=now,
                rtt_ms=float(value),
                source="harness",
            )
        )
    db.commit()


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate geo recommendation artifacts")
    parser.add_argument("--output-dir", default="artifacts/geo_reco", help="Base output directory")
    args = parser.parse_args()

    out_dir = Path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    # In-memory DB just for this harness.
    engine = create_engine(
        "sqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
        echo=False,
    )
    SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

    # Register all models.
    from models import (  # noqa: F401
        user,
        subscription,
        audit_log,
        vpn_server,
        vpn_server_rtt_sample,
        vpn_connection,
        wireguard_peer,
        gdpr,
        support_ticket,
        usage_analytics,
        invoice,
        email_log,
        auth_refresh_token,
        jwt_blacklist_token,
    )

    Base.metadata.create_all(bind=engine)

    db = SessionLocal()
    try:
        americas = _seed_server(db, server_id="us-east-1-001", region="Americas", latency_ms=60.0, current_connections=50)
        europe = _seed_server(db, server_id="eu-west-1-001", region="Europe", latency_ms=70.0, current_connections=120)
        asia = _seed_server(db, server_id="ap-east-1-001", region="Asia", latency_ms=120.0, current_connections=10)

        _seed_rtt_samples(db, server=americas, values=[40, 41, 42, 43, 44, 45])
        _seed_rtt_samples(db, server=europe, values=[55, 60, 65, 70, 75, 80])
        _seed_rtt_samples(db, server=asia, values=[120, 130, 140, 150, 160, 170])

        os.environ["SECUREWAVE_GEO_RECO_WRITE_ARTIFACTS"] = "true"
        os.environ["SECUREWAVE_GEO_RECO_RTT_MIN_SAMPLES"] = "5"
        os.environ["SECUREWAVE_GEO_RECO_RTT_WINDOW_SECONDS"] = str(60 * 60)

        results = {"generated_at": _utc_now_iso(), "runs": []}
        for hint in ("barbados", "europe"):
            run_dir = out_dir / hint
            os.environ["SECUREWAVE_GEO_RECO_ARTIFACT_DIR"] = str(run_dir)
            payload = recommend_server(db, user_tier="premium", user_region_hint=hint, include_candidates=True)
            results["runs"].append({"hint": hint, "recommended_server_id": payload.get("recommended_server_id")})

        (out_dir / "geo_reco_report.json").write_text(json.dumps(results, indent=2) + "\n", encoding="utf-8")
        print(json.dumps(results, indent=2))
        return 0
    finally:
        db.close()


if __name__ == "__main__":
    raise SystemExit(main())
