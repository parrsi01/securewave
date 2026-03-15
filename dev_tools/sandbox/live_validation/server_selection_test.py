#!/usr/bin/env python3
"""Latency-based server selection validation for SecureWave VPN.

Validates that SecureWave's server selection logic returns the
lowest-latency server when the client requests a profile in AUTO mode.

Test phases:
1. Fetch server list from GET /api/vpn/servers.
2. Measure RTT latency to each server endpoint via ping.
3. Rank servers by latency.
4. Request VPN profile (auto server selection).
5. Verify returned endpoint matches lowest-latency server.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[3]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from dev_tools.sandbox.live_validation.common import (
    build_api_url,
    fetch_vpn_profile,
    http_json_request,
    parse_wireguard_config,
    run_command,
    utc_now_iso,
    write_json,
)


@dataclass
class ServerLatency:
    """Measured latency to a VPN server."""

    server_id: str = ""
    server_name: str = ""
    endpoint_host: str = ""
    endpoint_port: int = 0
    latency_ms: float | None = None
    ping_success: bool = False
    region: str = ""


@dataclass
class ServerSelectionReport:
    """Full server selection test report."""

    test_name: str = "latency_server_selection"
    started_at: str = ""
    finished_at: str = ""
    verdict: str = "UNTESTED"

    servers_fetched: int = 0
    server_latencies: list[ServerLatency] = field(default_factory=list)

    expected_best_server: str = ""
    expected_best_latency_ms: float | None = None

    profile_server_endpoint: str = ""
    profile_server_id: str = ""
    selection_matches: bool = False

    tolerance_ms: float = 20.0  # Allow this much tolerance in selection.
    failures: list[str] = field(default_factory=list)

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


def fetch_server_list(
    api_base_url: str,
    access_token: str,
    *,
    timeout_seconds: int = 15,
) -> list[dict[str, Any]]:
    """Fetch VPN server list from the API."""
    result = http_json_request(
        "GET",
        build_api_url(api_base_url, "/vpn/servers"),
        headers={"Authorization": f"Bearer {access_token}"},
        timeout_seconds=timeout_seconds,
    )
    if result.status_code != 200:
        return []
    body = result.body
    if isinstance(body, dict):
        return body.get("servers", [])
    return []


def measure_latency(host: str, *, count: int = 3, timeout: int = 2) -> tuple[bool, float | None]:
    """Measure ping RTT to a host. Returns (success, avg_ms)."""
    result = run_command(
        ["ping", "-c", str(count), "-W", str(timeout), host],
        timeout_seconds=count * timeout + 3,
    )
    if result.returncode != 0:
        return False, None

    for line in result.stdout.splitlines():
        if "min/avg" in line and "=" in line:
            try:
                tail = line.split("=", 1)[1].strip().replace(" ms", "")
                parts = tail.split("/")
                if len(parts) >= 2:
                    return True, float(parts[1])
            except (ValueError, IndexError):
                pass
    return False, None


def rank_servers_by_latency(
    servers: list[dict[str, Any]],
) -> list[ServerLatency]:
    """Measure latency to each server and rank by RTT."""
    results: list[ServerLatency] = []

    for server in servers:
        server_id = str(server.get("id") or server.get("server_id") or "")
        name = str(server.get("name") or server.get("hostname") or "")
        endpoint = str(server.get("endpoint") or server.get("ip_address") or "")
        region = str(server.get("region") or server.get("location") or "")

        # Parse host from endpoint.
        host = endpoint.split(":")[0] if endpoint else ""
        port = 51820
        if ":" in endpoint:
            try:
                port = int(endpoint.rsplit(":", 1)[1])
            except ValueError:
                pass

        if not host:
            results.append(ServerLatency(
                server_id=server_id,
                server_name=name,
                endpoint_host=host,
                endpoint_port=port,
                region=region,
                ping_success=False,
            ))
            continue

        success, avg_ms = measure_latency(host)
        results.append(ServerLatency(
            server_id=server_id,
            server_name=name,
            endpoint_host=host,
            endpoint_port=port,
            latency_ms=round(avg_ms, 3) if avg_ms is not None else None,
            ping_success=success,
            region=region,
        ))

    # Sort by latency (None/failed at end).
    results.sort(key=lambda s: s.latency_ms if s.latency_ms is not None else float("inf"))
    return results


def evaluate_selection(
    ranked: list[ServerLatency],
    selected_endpoint: str,
    *,
    tolerance_ms: float = 20.0,
) -> tuple[bool, str]:
    """Check if the selected server is optimal or near-optimal.

    Allows tolerance — if the selected server's latency is within
    tolerance_ms of the best server, it's considered acceptable.
    """
    if not ranked:
        return False, "no_servers_ranked"

    # Find the selected server in rankings.
    selected_host = selected_endpoint.split(":")[0] if selected_endpoint else ""
    selected_entry: ServerLatency | None = None
    for s in ranked:
        if s.endpoint_host == selected_host:
            selected_entry = s
            break

    best = ranked[0]
    if best.latency_ms is None:
        return True, "no_latency_data_for_best"

    if selected_entry is None:
        return False, f"selected_endpoint_not_in_server_list: {selected_host}"

    if selected_entry.latency_ms is None:
        return False, f"no_latency_data_for_selected: {selected_host}"

    delta = selected_entry.latency_ms - best.latency_ms
    if delta <= tolerance_ms:
        return True, f"within_tolerance: delta={delta:.1f}ms"

    return False, f"suboptimal_selection: best={best.endpoint_host}({best.latency_ms:.1f}ms) selected={selected_host}({selected_entry.latency_ms:.1f}ms) delta={delta:.1f}ms"


def run_server_selection_test(
    *,
    api_base_url: str,
    access_token: str,
    tolerance_ms: float = 20.0,
    device_type: str = "linux",
    output_dir: Path | None = None,
) -> ServerSelectionReport:
    """Run the full server selection validation test."""
    report = ServerSelectionReport(
        started_at=utc_now_iso(),
        tolerance_ms=tolerance_ms,
    )

    # Step 1: Fetch server list.
    servers = fetch_server_list(api_base_url, access_token)
    report.servers_fetched = len(servers)

    if not servers:
        report.verdict = "SKIP"
        report.failures.append("no_servers_returned")
        report.finished_at = utc_now_iso()
        if output_dir:
            write_json(output_dir / "server_selection_report.json", report.to_dict())
        return report

    # Step 2: Measure latency to each server.
    report.server_latencies = rank_servers_by_latency(servers)

    reachable = [s for s in report.server_latencies if s.ping_success]
    if not reachable:
        report.verdict = "SKIP"
        report.failures.append("no_reachable_servers")
        report.finished_at = utc_now_iso()
        if output_dir:
            write_json(output_dir / "server_selection_report.json", report.to_dict())
        return report

    best = reachable[0]
    report.expected_best_server = best.server_id or best.endpoint_host
    report.expected_best_latency_ms = best.latency_ms

    # Step 3: Request VPN profile (auto selection).
    profile = fetch_vpn_profile(
        api_base_url=api_base_url,
        access_token=access_token,
        device_name="server-selection-test",
        device_type=device_type,
        timeout_seconds=15,
    )
    profile_body = profile.body if isinstance(profile.body, dict) else {}

    if profile.status_code != 200:
        report.verdict = "FAIL"
        report.failures.append(f"profile_fetch_failed: status={profile.status_code}")
        report.finished_at = utc_now_iso()
        if output_dir:
            write_json(output_dir / "server_selection_report.json", report.to_dict())
        return report

    config_text = str(profile_body.get("wireguard_config", ""))
    sections = parse_wireguard_config(config_text)
    endpoint = sections.get("peer", {}).get("endpoint", "")
    report.profile_server_endpoint = endpoint
    report.profile_server_id = str(profile_body.get("server_id", ""))

    # Step 4: Evaluate selection.
    ok, reason = evaluate_selection(
        report.server_latencies,
        endpoint,
        tolerance_ms=tolerance_ms,
    )
    report.selection_matches = ok
    report.verdict = "PASS" if ok else "FAIL"
    if not ok:
        report.failures.append(reason)

    report.finished_at = utc_now_iso()
    if output_dir:
        write_json(output_dir / "server_selection_report.json", report.to_dict())
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description="SecureWave Server Selection Validation")
    parser.add_argument("--api-base-url", default=os.getenv("LIVE_API_BASE_URL", ""))
    parser.add_argument("--access-token", default=os.getenv("LIVE_ACCESS_TOKEN", ""))
    parser.add_argument("--tolerance-ms", type=float, default=20.0)
    parser.add_argument("--device-type", default="linux")
    parser.add_argument("--output-dir", default="artifacts/server_selection_test")
    args = parser.parse_args()

    if not args.api_base_url.strip():
        print("SERVER_SELECTION_TEST: SKIP — LIVE_API_BASE_URL required")
        return 0

    if not args.access_token.strip():
        print("SERVER_SELECTION_TEST: SKIP — LIVE_ACCESS_TOKEN required")
        return 0

    out_dir = Path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    report = run_server_selection_test(
        api_base_url=args.api_base_url.strip(),
        access_token=args.access_token.strip(),
        tolerance_ms=args.tolerance_ms,
        device_type=args.device_type,
        output_dir=out_dir,
    )

    print(f"\nSERVER_SELECTION_TEST: {report.verdict}")
    print(f"  servers_fetched:    {report.servers_fetched}")
    print(f"  expected_best:      {report.expected_best_server} ({report.expected_best_latency_ms}ms)")
    print(f"  profile_endpoint:   {report.profile_server_endpoint}")
    print(f"  selection_matches:  {report.selection_matches}")
    if report.failures:
        print(f"  failures:           {report.failures}")
    print()
    print(json.dumps(report.to_dict(), indent=2))
    return 0 if report.verdict == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
