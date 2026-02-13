#!/usr/bin/env python3
"""
SecureWave live user simulation scaffold.

Flow:
1) user registration
2) login
3) VPN profile fetch
4) endpoint reachability probe (UDP send, optional reply)

Outputs:
- JSON logs
- CSV metrics
- Markdown report
"""

from __future__ import annotations

import argparse
import csv
import json
import random
import socket
import string
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import httpx


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def iso(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).isoformat()


def random_email(prefix: str = "simuser") -> str:
    suffix = "".join(random.choices(string.ascii_lowercase + string.digits, k=8))
    return f"{prefix}+{suffix}@example.com"


@dataclass
class Metric:
    step: str
    status: str
    latency_ms: float
    detail: str
    ts: str


class SimulationRunner:
    def __init__(self, base_url: str, timeout: float = 20.0):
        self.base_url = base_url.rstrip("/")
        self.client = httpx.Client(base_url=self.base_url, timeout=timeout)
        self.logs: list[dict[str, Any]] = []
        self.metrics: list[Metric] = []

    def close(self) -> None:
        self.client.close()

    def _record(self, step: str, status: str, started: float, detail: str, payload: Any | None = None) -> None:
        latency_ms = round((time.perf_counter() - started) * 1000, 2)
        metric = Metric(step=step, status=status, latency_ms=latency_ms, detail=detail, ts=iso(utc_now()))
        self.metrics.append(metric)
        self.logs.append(
            {
                "ts": metric.ts,
                "step": step,
                "status": status,
                "latency_ms": latency_ms,
                "detail": detail,
                "payload": payload,
            }
        )

    def register(self, email: str, password: str) -> None:
        started = time.perf_counter()
        response = self.client.post(
            "/api/auth/register",
            json={"email": email, "password": password, "password_confirm": password},
        )
        ok = response.status_code in (200, 201, 400)
        status = "ok" if ok else "error"
        self._record("register", status, started, f"status_code={response.status_code}", response.json())
        if not ok:
            raise RuntimeError(f"registration failed: {response.status_code} {response.text}")

    def login(self, email: str, password: str) -> dict[str, Any]:
        started = time.perf_counter()
        response = self.client.post("/api/auth/login", json={"email": email, "password": password})
        if response.status_code != 200:
            self._record("login", "error", started, f"status_code={response.status_code}", response.text)
            raise RuntimeError(f"login failed: {response.status_code} {response.text}")
        body = response.json()
        self._record("login", "ok", started, "token issued", {"token_type": body.get("token_type", "bearer")})
        return body

    def fetch_profile(self, token: str, device_name: str, device_type: str) -> dict[str, Any]:
        started = time.perf_counter()
        response = self.client.post(
            "/api/vpn/profile",
            headers={"Authorization": f"Bearer {token}"},
            json={
                "device_name": device_name,
                "device_type": device_type,
                "protocol": "wireguard",
            },
        )
        if response.status_code != 200:
            self._record("fetch_profile", "error", started, f"status_code={response.status_code}", response.text)
            raise RuntimeError(f"profile fetch failed: {response.status_code} {response.text}")
        body = response.json()
        self._record(
            "fetch_profile",
            "ok",
            started,
            f"server_id={body.get('server_id')}",
            {"device_id": body.get("device_id"), "server_id": body.get("server_id")},
        )
        return body

    def probe_udp_endpoint(self, endpoint: str, expect_reply: bool, timeout_seconds: float = 2.0) -> dict[str, Any]:
        started = time.perf_counter()
        host, port_raw = endpoint.rsplit(":", 1)
        port = int(port_raw)

        payload = b"securewave-probe"
        status = "ok"
        detail = "udp_probe_sent"
        got_reply = False

        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.settimeout(timeout_seconds)
        try:
            sock.sendto(payload, (host, port))
            if expect_reply:
                try:
                    data, _ = sock.recvfrom(2048)
                    got_reply = bool(data)
                    detail = "udp_reply_received" if got_reply else "udp_empty_reply"
                except socket.timeout:
                    status = "error"
                    detail = "udp_reply_timeout"
            else:
                detail = "udp_probe_sent_no_reply_expected"
        except Exception as exc:  # pragma: no cover - network-environment dependent
            status = "error"
            detail = f"udp_probe_failed:{exc}"
        finally:
            sock.close()

        self._record("udp_probe", status, started, detail, {"endpoint": endpoint, "reply": got_reply})
        return {"status": status, "detail": detail, "reply": got_reply}


def _extract_endpoint(wireguard_config: str) -> str:
    for line in wireguard_config.splitlines():
        if line.strip().startswith("Endpoint ="):
            return line.split("=", 1)[1].strip()
    raise ValueError("Endpoint not found in WireGuard config")


def write_outputs(output_dir: Path, logs: list[dict[str, Any]], metrics: list[Metric]) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    logs_path = output_dir / "simulation_logs.json"
    metrics_path = output_dir / "simulation_metrics.csv"
    report_path = output_dir / "simulation_report.md"

    logs_path.write_text(json.dumps(logs, indent=2), encoding="utf-8")

    with metrics_path.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.writer(fh)
        writer.writerow(["ts", "step", "status", "latency_ms", "detail"])
        for m in metrics:
            writer.writerow([m.ts, m.step, m.status, m.latency_ms, m.detail])

    avg_latency = round(sum(m.latency_ms for m in metrics) / max(1, len(metrics)), 2)
    handshake_success = len([m for m in metrics if m.step == "udp_probe" and m.status == "ok"])
    routing_success = len([m for m in metrics if m.step == "fetch_profile" and m.status == "ok"])
    report = f"""# Simulation Report

- Generated at: {iso(utc_now())}
- Steps executed: {len(metrics)}
- Average latency (ms): {avg_latency}
- Handshake/probe success count: {handshake_success}
- Packet routing profile success count: {routing_success}

## Output files
- JSON logs: `{logs_path}`
- CSV metrics: `{metrics_path}`
"""
    report_path.write_text(report, encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="SecureWave user simulation scaffold")
    parser.add_argument("--base-url", default="http://127.0.0.1:8000")
    parser.add_argument("--email", default="")
    parser.add_argument("--password", default="SimUserPass123!")
    parser.add_argument("--device-name", default="Simulation Device")
    parser.add_argument("--device-type", default="linux")
    parser.add_argument("--expect-udp-reply", action="store_true")
    parser.add_argument("--output-dir", default="artifacts/simulation")
    args = parser.parse_args()

    email = args.email or random_email()
    runner = SimulationRunner(args.base_url)

    try:
        runner.register(email, args.password)
        login = runner.login(email, args.password)
        token = login.get("access_token")
        if not token:
            raise RuntimeError("missing access token from login")

        profile = runner.fetch_profile(token, args.device_name, args.device_type)
        endpoint = _extract_endpoint(profile["wireguard_config"])
        runner.probe_udp_endpoint(endpoint, expect_reply=args.expect_udp_reply)
    finally:
        runner.close()

    output_dir = Path(args.output_dir)
    write_outputs(output_dir, runner.logs, runner.metrics)
    print(f"Simulation complete. Outputs written to {output_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
