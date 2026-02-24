#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import csv
from pathlib import Path
from typing import Any


def _read_json(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}
    return data if isinstance(data, dict) else {}


def _read_csv_rows(path: Path) -> list[dict[str, str]]:
    if not path.exists():
        return []
    with path.open("r", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        return [dict(row) for row in reader]


def _pct(values: list[float], pct: float) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    if len(ordered) == 1:
        return float(ordered[0])
    k = (len(ordered) - 1) * (pct / 100.0)
    f = int(k)
    c = min(f + 1, len(ordered) - 1)
    return float(ordered[f] + (k - f) * (ordered[c] - ordered[f]))


def _fmt_bool(value: Any) -> str:
    return "PASS" if bool(value) else "FAIL"


def _fmt_opt(value: Any) -> str:
    if value is None:
        return "n/a"
    text = str(value).strip()
    return text if text else "n/a"


def _handshake_summary(live_validation_dir: Path) -> dict[str, Any]:
    # Prefer readiness summary if present.
    summary = _read_json(live_validation_dir / "validation_summary.json")
    if summary:
        return {
            "source": "validation_summary.json",
            "status": summary.get("overall_status"),
            "readiness_score": summary.get("readiness_score"),
            "handshake": summary.get("handshake") or {},
            "dns": summary.get("dns") or {},
            "statuses": summary.get("statuses") or {},
        }
    # Fallback: raw result only.
    e2e = _read_json(live_validation_dir / "live_e2e_result.json")
    return {
        "source": "live_e2e_result.json",
        "status": e2e.get("overall_status"),
        "handshake": {},
        "dns": {},
        "statuses": {"e2e": e2e.get("overall_status")},
    }


def _performance_summary(live_validation_dir: Path) -> dict[str, Any]:
    rows = _read_csv_rows(live_validation_dir / "performance_stats.csv")
    throughputs: list[float] = []
    for row in rows:
        raw = (row.get("throughput_mbps") or "").strip()
        try:
            throughputs.append(float(raw))
        except Exception:
            continue
    return {
        "samples": len(throughputs),
        "throughput_p50_mbps": round(_pct(throughputs, 50), 3) if throughputs else None,
        "throughput_p95_mbps": round(_pct(throughputs, 95), 3) if throughputs else None,
    }


def generate(*, run_dir: Path) -> str:
    live_validation_dir = run_dir / "live_validation"
    handshake = _handshake_summary(live_validation_dir)
    perf = _performance_summary(live_validation_dir)
    e2e = _read_json(live_validation_dir / "live_e2e_result.json")

    smoke = _read_json(run_dir / "smoke_http_https.json")
    ssl_probe = _read_json(run_dir / "ssl_probe.json")
    metrics = _read_json(run_dir / "metrics_probe.json")
    stripe = _read_json(run_dir / "stripe_smoke.json")
    preview = _read_json(run_dir / "domain_preview.json")

    lines: list[str] = []
    lines.append("# SecureWave Live Hetzner Smoke Report")
    lines.append("")
    lines.append(f"- Run dir: `{run_dir}`")
    lines.append(f"- Generated at (report): `{_fmt_opt(smoke.get('generated_at') or handshake.get('generated_at'))}`")
    lines.append("")

    lines.append("## Real WireGuard Connectivity")
    lines.append(f"- Live validation status: **{_fmt_opt(handshake.get('status'))}** (source={handshake.get('source')})")
    if handshake.get("readiness_score") is not None:
        lines.append(f"- Readiness score: **{_fmt_opt(handshake.get('readiness_score'))} / 100**")
    hs = handshake.get("handshake") or {}
    if hs:
        lines.append(f"- Handshake samples: **{int(hs.get('samples') or 0)}**")
        lines.append(f"- Handshake P50/P95 (ms): **{_fmt_opt(hs.get('p50_ms'))} / {_fmt_opt(hs.get('p95_ms'))}**")
    if perf.get("samples", 0) > 0:
        lines.append(f"- Throughput P50/P95 (Mbps): **{_fmt_opt(perf.get('throughput_p50_mbps'))} / {_fmt_opt(perf.get('throughput_p95_mbps'))}**")
    # IP rotation and DNS results are per-user in raw payload; keep summary level here.
    dns = handshake.get("dns") or {}
    if dns:
        lines.append(f"- DNS leak checks: **{_fmt_opt(dns.get('checks'))}**; leaks: **{_fmt_opt(dns.get('leaks'))}**")
    # Include one representative session detail if present.
    results = e2e.get("results") or []
    if isinstance(results, list) and results:
        first = results[0] if isinstance(results[0], dict) else {}
        lines.append(f"- Example session: handshake_success={_fmt_opt(first.get('handshake_success'))} ip_changed={_fmt_opt(first.get('external_ip_changed'))}")
    lines.append("")

    lines.append("## Basic Smoke Tests")
    probes = (smoke.get("probes") or {}) if isinstance(smoke.get("probes"), dict) else {}
    lines.append(f"- curl http://<ip>: **{_fmt_opt(((probes.get('http_ip') or {}) if isinstance(probes.get('http_ip'), dict) else {}).get('status_code'))}**")
    lines.append(f"- curl https://<ip>: **{_fmt_opt(((probes.get('https_ip') or {}) if isinstance(probes.get('https_ip'), dict) else {}).get('status_code'))}**")
    lines.append(f"- curl https://<ip> (-k): **{_fmt_opt(((probes.get('https_ip_insecure') or {}) if isinstance(probes.get('https_ip_insecure'), dict) else {}).get('status_code'))}**")
    lines.append(f"- /health: **{_fmt_opt(((probes.get('health') or {}) if isinstance(probes.get('health'), dict) else {}).get('status_code'))}**")
    lines.append(f"- /metrics: **{_fmt_opt(((probes.get('metrics') or {}) if isinstance(probes.get('metrics'), dict) else {}).get('status_code'))}**")
    lines.append("")

    lines.append("## SSL Verification")
    api_host_443 = ssl_probe.get("api_host_443") or {}
    ip_443 = ssl_probe.get("ip_443") or {}
    if isinstance(api_host_443, dict):
        lines.append(f"- api_host_443: status={_fmt_opt(api_host_443.get('status'))} verify={_fmt_opt(api_host_443.get('verify'))}")
    if isinstance(ip_443, dict):
        lines.append(f"- ip_443: status={_fmt_opt(ip_443.get('status'))} verify={_fmt_opt(ip_443.get('verify'))}")
    else:
        lines.append("- ip_443: n/a")
    lines.append("")

    lines.append("## Backend Connectivity")
    lines.append(f"- /api/vpn/profile: **{_fmt_opt((handshake.get('statuses') or {}).get('e2e'))}** (via live validation harness)")
    lines.append(f"- /metrics preview captured: **{_fmt_bool(bool(((metrics.get('metrics') or {}) if isinstance(metrics.get('metrics'), dict) else {}).get('preview')))}**")
    lines.append("")

    lines.append("## Stripe Live Activation Sanity")
    lines.append(f"- Backend stripe-status HTTP: **{_fmt_opt((stripe.get('backend_stripe_status') or {}).get('http_status'))}** mode={_fmt_opt(stripe.get('backend_mode'))}")
    lines.append(f"- Live actions blocked (safety): **{_fmt_opt(stripe.get('live_actions_blocked'))}**")
    lines.append(f"- Create checkout session HTTP: **{_fmt_opt((stripe.get('checkout_session') or {}).get('http_status'))}**")
    lines.append(f"- Webhook validation attempted: **{_fmt_opt((stripe.get('webhook_validation') or {}).get('attempted'))}** HTTP={_fmt_opt((stripe.get('webhook_validation') or {}).get('http_status'))}")
    lines.append("")

    lines.append("## Domain Preview Setup")
    lines.append(f"- nip.io: **{_fmt_opt(preview.get('nip_io'))}**")
    lines.append(f"- sslip.io: **{_fmt_opt(preview.get('sslip_io'))}**")
    lines.append("")

    lines.append("## Notes")
    lines.append("- IP-based HTTPS often fails certificate validation unless the cert includes the IP in SAN; use a nip.io/sslip.io hostname for a valid hostname-based cert.")
    lines.append("- WireGuard tunnel operations require root/admin privileges on the runner machine.")
    lines.append("")
    return "\n".join(lines) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--run-dir", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    run_dir = Path(args.run_dir)
    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(generate(run_dir=run_dir), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
