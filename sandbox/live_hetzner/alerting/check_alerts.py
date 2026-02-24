#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import sys
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional
from urllib import error as urlerror
from urllib import request as urlrequest

REPO_ROOT = Path(__file__).resolve().parents[3]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from sandbox.live_hetzner.alerting.notifier import notify  # noqa: E402


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _bool_env(name: str, default: bool = False) -> bool:
    raw = os.getenv(name)
    if raw is None:
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on"}


def _float_env(name: str, default: float) -> float:
    raw = os.getenv(name)
    if raw is None:
        return default
    try:
        return float(raw.strip())
    except Exception:
        return default


def _int_env(name: str, default: int) -> int:
    raw = os.getenv(name)
    if raw is None:
        return default
    try:
        return int(raw.strip())
    except Exception:
        return default


def _http_get(url: str, *, headers: dict[str, str] | None = None, timeout_s: int = 12) -> tuple[int, str]:
    req = urlrequest.Request(url=url, method="GET", headers=headers or {})
    try:
        with urlrequest.urlopen(req, timeout=timeout_s) as resp:
            body = resp.read().decode("utf-8", errors="replace")
            return int(resp.status), body
    except urlerror.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace") if exc.fp else str(exc)
        return int(exc.code), body
    except Exception as exc:
        return 0, str(exc)


def _http_json(method: str, url: str, *, payload: dict[str, Any] | None = None, headers: dict[str, str] | None = None) -> tuple[int, Any]:
    body_bytes = None
    hdrs = {"Content-Type": "application/json"}
    if headers:
        hdrs.update(headers)
    if payload is not None:
        body_bytes = json.dumps(payload).encode("utf-8")
    req = urlrequest.Request(url=url, method=method.upper(), headers=hdrs, data=body_bytes)
    try:
        with urlrequest.urlopen(req, timeout=12) as resp:
            raw = resp.read().decode("utf-8", errors="replace")
            try:
                return int(resp.status), json.loads(raw) if raw else {}
            except Exception:
                return int(resp.status), raw
    except urlerror.HTTPError as exc:
        raw = exc.read().decode("utf-8", errors="replace") if exc.fp else str(exc)
        try:
            return int(exc.code), json.loads(raw) if raw else {}
        except Exception:
            return int(exc.code), raw
    except Exception as exc:
        return 0, str(exc)


def _login_for_token(api_base_url: str) -> str | None:
    token = (os.getenv("ALERT_API_TOKEN") or "").strip()
    if token:
        return token

    email = (os.getenv("ALERT_API_EMAIL") or "").strip()
    password = (os.getenv("ALERT_API_PASSWORD") or "").strip()
    if not email or not password:
        return None
    status, body = _http_json("POST", f"{api_base_url.rstrip('/')}/api/auth/login", payload={"email": email, "password": password})
    if status != 200 or not isinstance(body, dict):
        return None
    access = str(body.get("access_token") or "").strip()
    return access or None


@dataclass(frozen=True)
class Check:
    name: str
    status: str  # pass|warn|fail|skip
    detail: str


def _mk_check(name: str, ok: bool, *, detail_ok: str, detail_fail: str, warn: bool = False, skip: bool = False) -> Check:
    if skip:
        return Check(name=name, status="skip", detail=detail_fail)
    if ok:
        return Check(name=name, status="pass", detail=detail_ok)
    return Check(name=name, status="warn" if warn else "fail", detail=detail_fail)


def run_checks(*, api_base_url: str, window_s: int) -> dict[str, Any]:
    token = _login_for_token(api_base_url)
    headers = {"Authorization": f"Bearer {token}"} if token else {}

    thresholds = {
        "cpu_percent_warn": _float_env("ALERT_CPU_PCT_WARN", 80.0),
        "cpu_percent_crit": _float_env("ALERT_CPU_PCT_CRIT", 90.0),
        "mem_percent_warn": _float_env("ALERT_MEM_PCT_WARN", 80.0),
        "mem_percent_crit": _float_env("ALERT_MEM_PCT_CRIT", 90.0),
        "handshake_p95_warn_ms": _float_env("ALERT_HANDSHAKE_P95_WARN_MS", 1500.0),
        "handshake_p95_crit_ms": _float_env("ALERT_HANDSHAKE_P95_CRIT_MS", 2500.0),
        "profile_p95_warn_ms": _float_env("ALERT_PROFILE_P95_WARN_MS", 3500.0),
        "profile_p95_crit_ms": _float_env("ALERT_PROFILE_P95_CRIT_MS", 6000.0),
        "ip_pool_warn_pct": _float_env("ALERT_IP_POOL_UTIL_WARN_PCT", 85.0),
        "ip_pool_crit_pct": _float_env("ALERT_IP_POOL_UTIL_CRIT_PCT", 95.0),
        "peer_churn_warn_per_s": _float_env("ALERT_PEER_CHURN_WARN_PER_S", 4.0),
        "peer_churn_crit_per_s": _float_env("ALERT_PEER_CHURN_CRIT_PER_S", 8.0),
        "stale_handshake_warn_pct": _float_env("ALERT_STALE_HANDSHAKES_WARN_PCT", 10.0),
        "stale_handshake_crit_pct": _float_env("ALERT_STALE_HANDSHAKES_CRIT_PCT", 25.0),
    }

    checks: list[Check] = []

    # /metrics (Prometheus)
    m_status, m_body = _http_get(f"{api_base_url.rstrip('/')}/metrics", timeout_s=10)
    checks.append(_mk_check("/metrics reachable", m_status == 200, detail_ok="200", detail_fail=f"status={m_status}"))

    # /api/metrics/vpn (JSON)
    vpn1_status, vpn1 = _http_json("GET", f"{api_base_url.rstrip('/')}/api/metrics/vpn", headers=headers if token else None)
    if not token:
        checks.append(Check(name="/api/metrics/vpn auth", status="skip", detail="no token (set ALERT_API_TOKEN or ALERT_API_EMAIL/PASSWORD)"))
    else:
        checks.append(_mk_check("/api/metrics/vpn reachable", vpn1_status == 200, detail_ok="200", detail_fail=f"status={vpn1_status}"))

    time.sleep(max(1, int(window_s)))
    vpn2_status, vpn2 = _http_json("GET", f"{api_base_url.rstrip('/')}/api/metrics/vpn", headers=headers if token else None)

    # /api/metrics/system
    sys_status, sys_body = _http_json("GET", f"{api_base_url.rstrip('/')}/api/metrics/system", headers=headers if token else None)
    if token:
        checks.append(_mk_check("/api/metrics/system reachable", sys_status == 200, detail_ok="200", detail_fail=f"status={sys_status}"))

    # /api/vpn/metrics/vpn (richer stale handshake stats) - optional
    vpn_rich_status, vpn_rich = _http_json("GET", f"{api_base_url.rstrip('/')}/api/vpn/metrics/vpn", headers=headers if token else None)
    if token and vpn_rich_status == 200 and isinstance(vpn_rich, dict):
        checks.append(Check(name="/api/vpn/metrics/vpn reachable", status="pass", detail="200"))
    elif token:
        checks.append(Check(name="/api/vpn/metrics/vpn reachable", status="warn", detail=f"status={vpn_rich_status}"))

    # Threshold checks from vpn metrics snapshot
    runtime = (vpn2.get("runtime") if isinstance(vpn2, dict) else None) or {}
    system = (runtime.get("system") if isinstance(runtime, dict) else None) or {}
    profile_lat = (runtime.get("profile_issue_latency") if isinstance(runtime, dict) else None) or {}
    handshake_lat = (runtime.get("handshake_latency") if isinstance(runtime, dict) else None) or {}
    ip_pool = (vpn2.get("ip_pool") if isinstance(vpn2, dict) else None) or {}

    cpu = float(system.get("cpu_percent") or 0.0)
    mem = float(system.get("memory_percent") or 0.0)
    hs_p95 = float(handshake_lat.get("p95_ms") or 0.0)
    profile_p95 = float(profile_lat.get("p95_ms") or 0.0)
    pool_util = float(ip_pool.get("utilization_pct") or 0.0)

    def _threshold(name: str, value: float, warn_at: float, crit_at: float, unit: str) -> None:
        if value >= crit_at:
            checks.append(Check(name=name, status="fail", detail=f"{value}{unit} >= {crit_at}{unit}"))
        elif value >= warn_at:
            checks.append(Check(name=name, status="warn", detail=f"{value}{unit} >= {warn_at}{unit}"))
        else:
            checks.append(Check(name=name, status="pass", detail=f"{value}{unit}"))

    _threshold("CPU percent", cpu, thresholds["cpu_percent_warn"], thresholds["cpu_percent_crit"], "%")
    _threshold("Memory percent", mem, thresholds["mem_percent_warn"], thresholds["mem_percent_crit"], "%")
    _threshold("Handshake P95", hs_p95, thresholds["handshake_p95_warn_ms"], thresholds["handshake_p95_crit_ms"], "ms")
    _threshold("Profile issuance P95", profile_p95, thresholds["profile_p95_warn_ms"], thresholds["profile_p95_crit_ms"], "ms")
    _threshold("IP pool utilization", pool_util, thresholds["ip_pool_warn_pct"], thresholds["ip_pool_crit_pct"], "%")

    # Peer churn rate from two samples
    churn_per_s = None
    try:
        c1 = (vpn1.get("runtime") or {}).get("counters") or {}
        c2 = (vpn2.get("runtime") or {}).get("counters") or {}
        v1 = float(c1.get("peer_connect_total") or 0.0) + float(c1.get("peer_disconnect_total") or 0.0)
        v2 = float(c2.get("peer_connect_total") or 0.0) + float(c2.get("peer_disconnect_total") or 0.0)
        churn_per_s = round(max(0.0, v2 - v1) / max(1.0, float(window_s)), 4)
    except Exception:
        churn_per_s = None

    if churn_per_s is None:
        checks.append(Check(name="Peer churn rate", status="warn", detail="unable_to_compute"))
    else:
        if churn_per_s >= thresholds["peer_churn_crit_per_s"]:
            checks.append(Check(name="Peer churn rate", status="fail", detail=f"{churn_per_s}/s"))
        elif churn_per_s >= thresholds["peer_churn_warn_per_s"]:
            checks.append(Check(name="Peer churn rate", status="warn", detail=f"{churn_per_s}/s"))
        else:
            checks.append(Check(name="Peer churn rate", status="pass", detail=f"{churn_per_s}/s"))

    # Stale handshake ratio (if richer metrics available)
    stale_ratio = None
    try:
        peers = (vpn_rich.get("peers") or {}) if isinstance(vpn_rich, dict) else {}
        total = float(peers.get("total") or 0.0)
        stale = float(peers.get("stale_handshakes") or 0.0)
        if total > 0:
            stale_ratio = round((stale / total) * 100.0, 3)
    except Exception:
        stale_ratio = None

    if stale_ratio is not None:
        if stale_ratio >= thresholds["stale_handshake_crit_pct"]:
            checks.append(Check(name="Stale handshakes pct", status="fail", detail=f"{stale_ratio}%"))
        elif stale_ratio >= thresholds["stale_handshake_warn_pct"]:
            checks.append(Check(name="Stale handshakes pct", status="warn", detail=f"{stale_ratio}%"))
        else:
            checks.append(Check(name="Stale handshakes pct", status="pass", detail=f"{stale_ratio}%"))
    else:
        checks.append(Check(name="Stale handshakes pct", status="skip", detail="endpoint_unavailable_or_no_data"))

    overall = "pass"
    if any(c.status == "fail" for c in checks):
        overall = "fail"
    elif any(c.status == "warn" for c in checks):
        overall = "warn"

    return {
        "generated_at": _utc_now_iso(),
        "api_base_url": api_base_url,
        "window_seconds": int(window_s),
        "overall_status": overall,
        "thresholds": thresholds,
        "computed": {
            "peer_churn_per_s": churn_per_s,
            "stale_handshake_pct": stale_ratio,
        },
        "checks": [c.__dict__ for c in checks],
        "raw": {
            "metrics_status": m_status,
            "api_metrics_vpn_status": vpn2_status,
            "api_metrics_system_status": sys_status,
            "api_vpn_metrics_vpn_status": vpn_rich_status,
        },
    }


def _render_md(result: dict[str, Any]) -> str:
    checks = result.get("checks") or []
    lines: list[str] = []
    lines.append("# SecureWave Alerting Checks (Live)")
    lines.append("")
    lines.append(f"- Generated at: `{result.get('generated_at')}`")
    lines.append(f"- API base URL: `{result.get('api_base_url')}`")
    lines.append(f"- Overall: **{result.get('overall_status')}**")
    lines.append("")
    lines.append("## Checks")
    lines.append("")
    for item in checks:
        if not isinstance(item, dict):
            continue
        lines.append(f"- {item.get('name')}: **{item.get('status')}** ({item.get('detail')})")
    lines.append("")
    lines.append("## Computed")
    lines.append("")
    computed = result.get("computed") or {}
    lines.append(f"- Peer churn rate (events/sec): **{computed.get('peer_churn_per_s')}**")
    lines.append(f"- Stale handshake percent: **{computed.get('stale_handshake_pct')}**")
    lines.append("")
    return "\n".join(lines) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser(description="Run live alerting checks against a SecureWave backend.")
    ap.add_argument("--api-base-url", default=os.getenv("LIVE_API_BASE_URL", ""))
    ap.add_argument("--window-seconds", type=int, default=_int_env("ALERT_SAMPLE_WINDOW_SECONDS", 10))
    ap.add_argument("--out-json", default="artifacts/live_hetzner_alerting_result.json")
    ap.add_argument("--out-md", default="artifacts/live_hetzner_alerting_result.md")
    ap.add_argument("--notify", action="store_true", help="Send notifications if warn/fail.")
    args = ap.parse_args()

    if not str(args.api_base_url).strip():
        raise SystemExit("LIVE_API_BASE_URL is required (or pass --api-base-url).")

    result = run_checks(api_base_url=str(args.api_base_url).strip(), window_s=max(3, int(args.window_seconds)))
    out_json = Path(args.out_json)
    out_json.parent.mkdir(parents=True, exist_ok=True)
    out_json.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    out_md = Path(args.out_md)
    out_md.parent.mkdir(parents=True, exist_ok=True)
    out_md.write_text(_render_md(result), encoding="utf-8")

    if args.notify and result.get("overall_status") in {"warn", "fail"}:
        title = f"SecureWave alerts: {result.get('overall_status')}"
        text = f"API={result.get('api_base_url')}\nGenerated={result.get('generated_at')}\n"
        notify_results = notify(title=title, text=text, payload=result)
        result["notifications"] = [r.__dict__ for r in notify_results]
        out_json.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    return 0 if result.get("overall_status") == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
