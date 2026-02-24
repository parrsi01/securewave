#!/usr/bin/env python3
"""
Generate operator-facing launch orchestration artifacts.

Outputs (repo-root relative):
- artifacts/launch_orchestrator_summary.md
- artifacts/launch_alert_matrix.md
- artifacts/operator_playbooks_index.md
- artifacts/canary_report.md (template only; overwritten by canary runs)
"""

from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
ARTIFACTS = REPO_ROOT / "artifacts"


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _atomic_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(content, encoding="utf-8")
    tmp.replace(path)


def _exists(relpath: str) -> bool:
    return (REPO_ROOT / relpath).exists()


def _canary_report_template() -> str:
    return "\n".join(
        [
            "# SecureWave Canary Report",
            "",
            f"Generated: `{_utc_now_iso()}`",
            "",
            "No canary run has been recorded yet in this checkout.",
            "",
            "## How To Run A Canary (Blue/Green)",
            "",
            "On the Hetzner host (recommended):",
            "```bash",
            "# Deploy the ref to a new local port (8081), validate, then switch Nginx upstream.",
            "sudo bash scripts/ops/zero_downtime_deploy.sh --mode bluegreen --ref HEAD --canary-port 8081",
            "```",
            "",
            "Outputs:",
            "- Detailed per-run report: `artifacts/canary/<run_id>/canary_report.md`",
            "- Latest report pointer (this file): `artifacts/canary_report.md`",
            "",
            "Rollback behavior:",
            "- If post-promotion checks fail, upstream is switched back to the previous port automatically.",
            "",
        ]
    ) + "\n"


def generate_operator_playbooks_index() -> None:
    lines: list[str] = []
    lines.append("# SecureWave Operator Playbooks Index")
    lines.append("")
    lines.append(f"Generated: `{_utc_now_iso()}`")
    lines.append("")
    lines.append("## Primary Runbooks")
    lines.append("")
    lines.append("- Hetzner provision + policy: `docs/HETZNER_RUNBOOK.md`")
    lines.append("- 30-day launch plan: `docs/launch_plan_30_days.md`")
    lines.append("- Day-2 ops: `docs/day2_operations.md`")
    lines.append("- Nginx preview/HTTPS: `docs/nginx_preview_config.md`")
    lines.append("- Live network validation: `docs/live_network_validation.md`")
    lines.append("- Stripe operations: `docs/STRIPE_RUNBOOK.md`")
    lines.append("- Release checklist: `docs/RELEASE_CHECKLIST.md`")
    lines.append("")
    lines.append("## Operator Scripts (Entry Points)")
    lines.append("")
    lines.append("- Launch validation (one shot): `scripts/run_launch_validation.sh`")
    lines.append("- Canary deploy (blue/green + rollback): `scripts/ops/canary_deploy.sh`")
    lines.append("- Zero-downtime deploy wrapper: `scripts/ops/zero_downtime_deploy.sh`")
    lines.append("- Gunicorn graceful restart helper: `scripts/ops/gunicorn_graceful_restart.sh`")
    lines.append("- Nginx upstream switch helper: `scripts/ops/nginx_switch_upstream.sh`")
    lines.append("")
    lines.append("## Live Hetzner Validation")
    lines.append("")
    lines.append("- Linux runner (WireGuard + SSL + Stripe probes): `sandbox/live_hetzner/run_live_hetzner_validation_linux.sh`")
    lines.append("- Windows runner (WireGuard connectivity): `sandbox/live_hetzner/run_live_hetzner_validation_windows.ps1`")
    lines.append("- Alert checks (metrics gating + notifications): `sandbox/live_hetzner/alerting/check_alerts.py`")
    lines.append("")
    lines.append("## Key Artifacts")
    lines.append("")
    lines.append("- Validation master: `artifacts/validation_master_report.md`")
    lines.append("- Canary report (latest): `artifacts/canary_report.md`")
    lines.append("- Live Hetzner smoke report (latest): `artifacts/live_hetzner_smoke_report.md`")
    lines.append("- Alerting checks documentation: `artifacts/alerting_checks.md`")
    lines.append("- Stripe live activation: `artifacts/stripe_live_activation.md`")
    lines.append("- HTTPS/domain setup: `artifacts/https_domain_setup_instructions.md`")
    lines.append("- Tier isolation: `artifacts/tier_isolation_report.md`")
    lines.append("")

    _atomic_write(ARTIFACTS / "operator_playbooks_index.md", "\n".join(lines) + "\n")


def generate_launch_alert_matrix() -> None:
    lines: list[str] = []
    lines.append("# SecureWave Launch Alert Matrix")
    lines.append("")
    lines.append(f"Generated: `{_utc_now_iso()}`")
    lines.append("")
    lines.append("This matrix maps deploy/launch hazard signals to their observability sources and operator actions.")
    lines.append("")
    lines.append("Primary sources:")
    lines.append("- `/metrics` (Prometheus plaintext; public)")
    lines.append("- `/api/metrics/vpn` and `/api/vpn/metrics/vpn` (auth; peer pool + handshake staleness)")
    lines.append("- `sandbox/live_hetzner/alerting/check_alerts.py` (live gate + notifier)")
    lines.append("")
    lines.append("## Alerts")
    lines.append("")
    lines.append("| Signal | Source | Default thresholds | Action |")
    lines.append("|---|---|---|---|")
    lines.append("| CPU high | `/api/metrics/vpn` -> `runtime.system.cpu_percent` | warn>=80%, crit>=90% | Reduce traffic, investigate hot path, consider blue/green cutover. |")
    lines.append("| Memory high | `/api/metrics/vpn` -> `runtime.system.memory_percent` | warn>=80%, crit>=90% | Restart with blue/green, check leak suite artifacts, inspect FD/thread growth. |")
    lines.append("| Handshake P95 high | `/api/metrics/vpn` -> `runtime.handshake_latency.p95_ms` | warn>=1500ms, crit>=2500ms | Validate UDP reachability, server registry correctness, MTU/routing; re-run live validation. |")
    lines.append("| Profile issuance P95 high | `/api/metrics/vpn` -> `runtime.profile_issue_latency.p95_ms` | warn>=3500ms, crit>=6000ms | Check DB health, peer auto-registration path, retry behavior; review slow queries. |")
    lines.append("| Peer churn high | `/api/metrics/vpn` counters over sample window | warn>=4/s, crit>=8/s | Investigate client reconnect storms, rate limits, backend errors; confirm no retry storm. |")
    lines.append("| IP pool near exhaustion | `/api/metrics/vpn` -> `ip_pool.utilization_pct` | warn>=85%, crit>=95% | Scale pool blocks per policy or revoke stale peers; confirm /22 allocator constraints. |")
    lines.append("| Stale handshakes rising | `/api/vpn/metrics/vpn` -> `peers.stale_handshakes` | warn>=10%, crit>=25% | Check WireGuard node health (`wg show`), NAT/UDP path, and tunnel watchdog behavior. |")
    lines.append("| Stripe webhook failures | App logs + receipts (`webhook_event_receipt`) | N/A | Verify `STRIPE_WEBHOOK_SECRET`, signature tolerance, endpoint URL; inspect dedupe receipts. |")
    lines.append("")
    lines.append("## Runbooks")
    lines.append("")
    lines.append("- Remediation steps: `docs/day2_operations.md`")
    lines.append("- Threshold policy + CI gates: `docs/thresholds_and_gating.md`")
    lines.append("")

    _atomic_write(ARTIFACTS / "launch_alert_matrix.md", "\n".join(lines) + "\n")


def generate_launch_orchestrator_summary() -> None:
    lines: list[str] = []
    lines.append("# SecureWave Launch Orchestrator Summary")
    lines.append("")
    lines.append(f"Generated: `{_utc_now_iso()}`")
    lines.append("")
    lines.append("This repo contains operator tooling to execute a production-style rollout on Hetzner:")
    lines.append("- blue/green canary deploy with rollback")
    lines.append("- live validation (WireGuard + DNS + latency/throughput)")
    lines.append("- Stripe live-mode sanity checks (safe by default)")
    lines.append("- metrics/alert gating")
    lines.append("")
    lines.append("## Rollout (Recommended)")
    lines.append("")
    lines.append("1. Ensure Nginx preview is installed and proxying to your current upstream port:")
    lines.append("   - `setup_preview.sh` (or `sandbox/live_hetzner/https/setup_nginx_https.sh`)")
    lines.append("2. Run a blue/green canary deploy and promote:")
    lines.append("```bash")
    lines.append("sudo bash scripts/ops/zero_downtime_deploy.sh --mode bluegreen --ref HEAD --canary-port 8081")
    lines.append("```")
    lines.append("")
    lines.append("## Validation (One Shot)")
    lines.append("")
    lines.append("Local (CI-safe) + optional live suite runner:")
    lines.append("```bash")
    lines.append("# Local suites + reports")
    lines.append("bash scripts/run_launch_validation.sh --strict --no-live")
    lines.append("")
    lines.append("# Live suite (requires LIVE_API_BASE_URL; live WG needs root + wireguard-tools)")
    lines.append("export LIVE_API_BASE_URL=\"https://<your-host>\"")
    lines.append("bash scripts/run_launch_validation.sh --strict --live")
    lines.append("```")
    lines.append("")
    lines.append("## Outputs")
    lines.append("")
    lines.append("- Canary:")
    lines.append("  - `artifacts/canary_report.md` (latest)")
    lines.append("  - `artifacts/canary/<run_id>/canary_report.md` (per run)")
    lines.append("- Validation:")
    lines.append("  - `artifacts/validation_master_report.md`")
    lines.append("  - `artifacts/live_hetzner_smoke_report.md` (when live suite runs)")
    lines.append("")
    lines.append("## CI/CD")
    lines.append("")
    lines.append("- Workflows gate on tests + chaos/benchmark/leak strict thresholds:")
    lines.append("  - `.github/workflows/test.yml`")
    lines.append("  - `.github/workflows/ci-cd.yml`")
    lines.append("")

    _atomic_write(ARTIFACTS / "launch_orchestrator_summary.md", "\n".join(lines) + "\n")


def main() -> int:
    ARTIFACTS.mkdir(parents=True, exist_ok=True)

    generate_operator_playbooks_index()
    generate_launch_alert_matrix()
    generate_launch_orchestrator_summary()

    # Only generate a template when a real canary report isn't present yet.
    canary_report = ARTIFACTS / "canary_report.md"
    if not canary_report.exists() or canary_report.read_text(encoding="utf-8", errors="ignore").strip() == "":
        _atomic_write(canary_report, _canary_report_template())

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

