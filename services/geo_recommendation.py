"""
Geo + reliability aware server recommendation.

Used by:
- GET /api/vpn/recommended-server

Inputs:
- geo_latency_probe report (if present) to anchor Barbados/EU corridor preferences
- rolling RTT history (DB samples) for recent latency stability
- current server load + health status + recent failures
"""

from __future__ import annotations

import json
import os
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional

from sqlalchemy.orm import Session

from models.vpn_server import VPNServer
from services.latency_optimizer import BaselineLatency, get_latency_optimizer
from services.rtt_history import RTTRollup, get_rtt_rollup
from services.vpn_server_service import VPNServerService


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _env_bool(name: str, default: bool = False) -> bool:
    raw = os.getenv(name)
    if raw is None:
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on"}


def _safe_float(raw: Any, default: float) -> float:
    try:
        return float(raw)
    except Exception:
        return default


@dataclass(frozen=True)
class GeoRecoBaselines:
    barbados_ms: float
    europe_ms: float
    source: str
    report_path: Optional[str] = None
    report_generated_at: Optional[str] = None

    def as_latency_optimizer_baselines(self) -> BaselineLatency:
        return BaselineLatency(
            barbados_ms=float(self.barbados_ms),
            frankfurt_ms=float(self.europe_ms),
            source=self.source,
        )


@dataclass(frozen=True)
class ScoredServer:
    server_id: str
    score: float
    rtt_ms: float
    rtt_source: str
    rtt_samples: int
    load_percent: float
    health_status: str
    consecutive_health_failures: int
    region: str | None


def _load_geo_latency_report(path: Path) -> Optional[dict]:
    try:
        if not path.exists():
            return None
        data = json.loads(path.read_text(encoding="utf-8"))
        if isinstance(data, dict) and data.get("harness") == "geo_latency_probe":
            return data
        return None
    except Exception:
        return None


def _baselines_from_geo_report(report: dict, *, report_path: str) -> Optional[GeoRecoBaselines]:
    summary = report.get("summary")
    if not isinstance(summary, list):
        return None

    barbados = None
    europe = None
    for row in summary:
        if not isinstance(row, dict):
            continue
        name = str(row.get("region", "")).strip().lower()
        avg_ms = row.get("avg_ms")
        if avg_ms is None:
            continue
        if name == "barbados":
            barbados = _safe_float(avg_ms, None)
        elif name in {"europe", "eu"}:
            europe = _safe_float(avg_ms, None)

    if barbados is None or europe is None:
        return None

    return GeoRecoBaselines(
        barbados_ms=float(barbados),
        europe_ms=float(europe),
        source="geo_latency_probe",
        report_path=report_path,
        report_generated_at=str(report.get("generated_at") or ""),
    )


def _fallback_baselines() -> GeoRecoBaselines:
    barbados = _safe_float(os.getenv("BARBADOS_BASELINE_MS", "95.0"), 95.0)
    europe = _safe_float(os.getenv("EUROPE_BASELINE_MS", os.getenv("FRANKFURT_BASELINE_MS", "130.0")), 130.0)
    return GeoRecoBaselines(barbados_ms=barbados, europe_ms=europe, source="env_fallback")


def load_baselines() -> GeoRecoBaselines:
    report_path = Path(
        os.getenv("SECUREWAVE_GEO_LATENCY_REPORT_PATH", "artifacts/live_validation/geo_latency_report.json")
    )
    report = _load_geo_latency_report(report_path)
    if report:
        baselines = _baselines_from_geo_report(report, report_path=str(report_path))
        if baselines:
            return baselines
    return _fallback_baselines()


class _ServerView:
    """
    Minimal view for GeoLatencyOptimizer.score_server().
    """

    def __init__(self, server: VPNServer, *, latency_ms: float) -> None:
        self.server_id = server.server_id
        self.region = server.region
        self.latency_ms = latency_ms
        self.performance_score = server.performance_score


def _score_server(
    server: VPNServer,
    *,
    rtt_ms: float,
    baselines: BaselineLatency,
    user_region_hint: Optional[str],
) -> float:
    optimizer = get_latency_optimizer()
    base = optimizer.score_server(
        _ServerView(server, latency_ms=rtt_ms),
        baselines=baselines,
        user_region_hint=user_region_hint,
    )

    load_percent = (server.current_connections / server.max_connections * 100.0) if server.max_connections else 0.0
    consecutive_failures = int(server.consecutive_health_failures or 0)
    health = (server.health_status or "unknown").strip().lower()

    health_penalty = 0.0
    if health == "degraded":
        health_penalty = 35.0
    elif health == "unknown":
        health_penalty = 60.0

    # Prefer lower load; keep the penalty modest so latency doesn't get ignored.
    load_penalty = min(100.0, max(0.0, load_percent)) * 0.9

    # Recent failures are a strong negative signal.
    failure_penalty = min(10, max(0, consecutive_failures)) * 40.0

    return round(float(base) - health_penalty - load_penalty - failure_penalty, 4)


def recommend_server(
    db: Session,
    *,
    user_tier: str,
    user_region_hint: Optional[str] = None,
    include_candidates: bool = True,
) -> dict:
    baselines = load_baselines()
    lo_baselines = baselines.as_latency_optimizer_baselines()

    window_seconds = max(60, int(os.getenv("SECUREWAVE_GEO_RECO_RTT_WINDOW_SECONDS", str(15 * 60))))
    min_samples = max(1, int(os.getenv("SECUREWAVE_GEO_RECO_RTT_MIN_SAMPLES", "5")))

    servers = VPNServerService.get_active_servers(db, user_tier)
    candidates: list[ScoredServer] = []

    for server in servers:
        health = (server.health_status or "unknown").strip().lower()
        if health not in {"healthy", "degraded", "unknown"}:
            continue

        rtt_rollup: RTTRollup | None = get_rtt_rollup(
            db,
            vpn_server_id=server.id,
            window_seconds=window_seconds,
            min_samples=min_samples,
        )

        if rtt_rollup:
            rtt_ms = float(rtt_rollup.p95_ms)
            rtt_source = "rtt_history_p95"
            rtt_samples = int(rtt_rollup.sample_count)
        else:
            rtt_ms = float(server.latency_ms or 999.0)
            rtt_source = "server_latency_ms"
            rtt_samples = 0

        score = _score_server(
            server,
            rtt_ms=rtt_ms,
            baselines=lo_baselines,
            user_region_hint=user_region_hint,
        )

        load_percent = (server.current_connections / server.max_connections * 100.0) if server.max_connections else 0.0
        candidates.append(
            ScoredServer(
                server_id=server.server_id,
                score=score,
                rtt_ms=round(rtt_ms, 3),
                rtt_source=rtt_source,
                rtt_samples=rtt_samples,
                load_percent=round(load_percent, 2),
                health_status=server.health_status,
                consecutive_health_failures=int(server.consecutive_health_failures or 0),
                region=server.region,
            )
        )

    candidates.sort(key=lambda item: item.score, reverse=True)
    recommended_id = candidates[0].server_id if candidates else None

    payload: dict[str, Any] = {
        "generated_at": _utc_now_iso(),
        "user_region_hint": user_region_hint,
        "recommended_server_id": recommended_id,
        "baselines": asdict(baselines),
        "rtt_window_seconds": window_seconds,
        "rtt_min_samples": min_samples,
    }
    if include_candidates:
        payload["candidates"] = [asdict(item) for item in candidates[:25]]

    if _env_bool("SECUREWAVE_GEO_RECO_WRITE_ARTIFACTS", False):
        _write_geo_reco_artifacts(payload)

    return payload


def _atomic_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(content, encoding="utf-8")
    tmp.replace(path)


def _write_geo_reco_artifacts(payload: dict) -> None:
    out_dir = Path(os.getenv("SECUREWAVE_GEO_RECO_ARTIFACT_DIR", "artifacts/geo_reco"))
    out_dir.mkdir(parents=True, exist_ok=True)

    _atomic_write(out_dir / "recommended_server.json", json.dumps(payload, indent=2, sort_keys=True) + "\n")

    # Compact CSV for quick diffing in CI.
    candidates = payload.get("candidates") if isinstance(payload, dict) else None
    if isinstance(candidates, list):
        header = [
            "server_id",
            "score",
            "rtt_ms",
            "rtt_source",
            "rtt_samples",
            "load_percent",
            "health_status",
            "consecutive_health_failures",
            "region",
        ]
        rows = [",".join(header)]
        for item in candidates:
            if not isinstance(item, dict):
                continue
            rows.append(
                ",".join(
                    [
                        str(item.get("server_id", "")),
                        str(item.get("score", "")),
                        str(item.get("rtt_ms", "")),
                        str(item.get("rtt_source", "")),
                        str(item.get("rtt_samples", "")),
                        str(item.get("load_percent", "")),
                        str(item.get("health_status", "")),
                        str(item.get("consecutive_health_failures", "")),
                        str(item.get("region", "")),
                    ]
                )
            )
        _atomic_write(out_dir / "candidates.csv", "\n".join(rows) + "\n")

