#!/usr/bin/env python3
"""Background evidence checker for manual SecureWave Linux VPN testing.

This tool is intentionally non-destructive. It performs live API checks with a
real test account, then watches local network state while a human drives the
Flutter app. Credentials are read from environment variables and are never
written to output artifacts.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[1]
ARTIFACT_ROOT = REPO_ROOT / "artifacts" / "manual_test_runs"
REQUIRED_ENV = (
    "SECUREWAVE_API_BASE_URL",
    "SECUREWAVE_TEST_EMAIL",
    "SECUREWAVE_TEST_PASSWORD",
)
PUBLIC_IP_URLS = (
    "https://api.ipify.org",
    "https://ifconfig.me/ip",
)
WATCH_INTERFACE_RE = re.compile(r"^(securewave|sw[-_].*|wg.*|tun.*)$")


@dataclass
class CheckResult:
    name: str
    status: str
    detail: str = ""
    evidence: dict[str, Any] = field(default_factory=dict)


class Checker:
    def __init__(self, args: argparse.Namespace) -> None:
        self.args = args
        self.started_at = utc_now()
        self.run_dir = ARTIFACT_ROOT / self.started_at.strftime("%Y%m%dT%H%M%SZ")
        self.run_dir.mkdir(parents=True, exist_ok=False)
        self.evidence_path = self.run_dir / "evidence.json"
        self.checklist_path = self.run_dir / "checklist.md"
        self.stop_requested = False
        self.results: list[CheckResult] = []
        self.samples: list[dict[str, Any]] = []
        self.token: str | None = None
        self.api_base_url = normalized_api_base(os.environ["SECUREWAVE_API_BASE_URL"])
        self.email = os.environ["SECUREWAVE_TEST_EMAIL"]

    def run(self) -> int:
        print(f"Run directory: {self.run_dir}")
        self.record_environment()
        self.api_preflight()
        baseline_ip = self.capture_public_ip("baseline_public_ip")

        print("")
        print("Manual phase started.")
        print("Launch the Flutter app in another terminal and complete the manual flow.")
        print("Press Ctrl-C after disconnect cleanup, or wait for the timeout.")
        print("")

        end_at = time.monotonic() + self.args.watch_seconds
        while not self.stop_requested and time.monotonic() < end_at:
            self.sample_network_state(baseline_ip)
            self.write_outputs()
            time.sleep(self.args.interval_seconds)

        self.evaluate_disconnect_cleanup()
        self.write_outputs(final=True)
        print(f"Checklist: {self.checklist_path}")
        print(f"Evidence:  {self.evidence_path}")
        return 0

    def record_environment(self) -> None:
        missing_tools = [tool for tool in ("curl", "ip", "python3") if not shutil.which(tool)]
        optional_missing = [tool for tool in ("wg", "flutter") if not shutil.which(tool)]
        self.add_result(
            "required_environment_variables",
            "pass",
            "Required env vars present; credential values are redacted.",
            {"present": list(REQUIRED_ENV)},
        )
        self.add_result(
            "required_tools",
            "pass" if not missing_tools else "fail",
            "Missing: " + ", ".join(missing_tools) if missing_tools else "curl, ip, python3 available.",
            {"missing": missing_tools},
        )
        self.add_result(
            "optional_tools",
            "pass" if not optional_missing else "warn",
            "Missing optional tools: " + ", ".join(optional_missing)
            if optional_missing
            else "wg and flutter available.",
            {"missing": optional_missing},
        )
        self.add_result("uname", "info", run_command(["uname", "-a"]).stdout.strip())

    def api_preflight(self) -> None:
        for path in ("/health", "/ready"):
            result = self.http_json("GET", path)
            self.add_result(
                f"api{path}",
                "pass" if result["ok"] else "fail",
                status_detail(result),
                safe_http_evidence(result),
            )

        login = self.http_json(
            "POST",
            "/auth/login",
            {"email": self.email, "password": os.environ["SECUREWAVE_TEST_PASSWORD"]},
        )
        token = extract_access_token(login.get("json"))
        if token:
            self.token = token
        self.add_result(
            "api_auth_login",
            "pass" if login["ok"] and token else "fail",
            "Login returned an access token." if token else status_detail(login),
            safe_http_evidence(login, redact_body=True),
        )

        for path in ("/user/plan", "/vpn/servers"):
            result = self.http_json("GET", path, token=self.token)
            self.add_result(
                f"api{path}",
                "pass" if result["ok"] else "fail",
                summarize_payload(path, result),
                safe_http_evidence(result),
            )

    def capture_public_ip(self, name: str) -> str | None:
        for url in PUBLIC_IP_URLS:
            result = self.http_text_url(url)
            if result["ok"] and result["text"]:
                ip = result["text"].strip()
                self.add_result(name, "pass", f"{url} returned {ip}", {"url": url, "ip": ip})
                return ip
        self.add_result(name, "fail", "Unable to capture public IP.", {})
        return None

    def sample_network_state(self, baseline_ip: str | None) -> None:
        timestamp = iso_now()
        interfaces = discover_interfaces()
        watched = [iface for iface in interfaces if WATCH_INTERFACE_RE.match(iface["name"])]
        public_ip = fetch_first_public_ip()
        wg_show = run_command(["wg", "show", "securewave"]) if shutil.which("wg") else CommandResult(127, "", "wg not found")
        route_default = run_command(["ip", "route", "get", "1.1.1.1"])
        sample = {
            "timestamp": timestamp,
            "public_ip": public_ip,
            "public_ip_changed_from_baseline": bool(baseline_ip and public_ip and baseline_ip != public_ip),
            "watched_interfaces": watched,
            "wg_show_securewave": command_payload(wg_show),
            "route_get_1_1_1_1": command_payload(route_default),
        }
        self.samples.append(sample)
        if watched:
            names = ", ".join(iface["name"] for iface in watched)
            print(f"{timestamp} watched interfaces: {names}; public_ip={public_ip or 'unknown'}")
        else:
            print(f"{timestamp} no securewave/wg/tun interface visible; public_ip={public_ip or 'unknown'}")

    def evaluate_disconnect_cleanup(self) -> None:
        current = [iface for iface in discover_interfaces() if WATCH_INTERFACE_RE.match(iface["name"])]
        if current:
            self.add_result(
                "disconnect_cleanup_current_interfaces",
                "warn",
                "Watched interfaces still visible at checker stop: "
                + ", ".join(iface["name"] for iface in current),
                {"interfaces": current},
            )
        else:
            self.add_result(
                "disconnect_cleanup_current_interfaces",
                "pass",
                "No securewave/wg/tun interface visible at checker stop.",
                {},
            )

    def http_json(
        self,
        method: str,
        path: str,
        payload: dict[str, Any] | None = None,
        token: str | None = None,
    ) -> dict[str, Any]:
        body = json.dumps(payload).encode("utf-8") if payload is not None else None
        headers = {"Content-Type": "application/json"}
        if token:
            headers["Authorization"] = f"Bearer {token}"
        url = self.api_base_url + path
        request = urllib.request.Request(url, data=body, headers=headers, method=method)
        try:
            with urllib.request.urlopen(request, timeout=self.args.http_timeout) as response:
                raw = response.read().decode("utf-8", errors="replace")
                parsed = json.loads(raw) if raw else None
                return {"ok": 200 <= response.status < 300, "status": response.status, "json": parsed}
        except urllib.error.HTTPError as exc:
            raw = exc.read().decode("utf-8", errors="replace")
            parsed = parse_json_or_text(raw)
            return {"ok": False, "status": exc.code, "json": parsed}
        except Exception as exc:
            return {"ok": False, "status": None, "error": str(exc)}

    def http_text_url(self, url: str) -> dict[str, Any]:
        try:
            request = urllib.request.Request(url, headers={"User-Agent": "securewave-manual-checker/1"})
            with urllib.request.urlopen(request, timeout=self.args.http_timeout) as response:
                text = response.read().decode("utf-8", errors="replace").strip()
                return {"ok": 200 <= response.status < 300, "status": response.status, "text": text}
        except Exception as exc:
            return {"ok": False, "status": None, "error": str(exc)}

    def add_result(
        self,
        name: str,
        status: str,
        detail: str = "",
        evidence: dict[str, Any] | None = None,
    ) -> None:
        self.results.append(CheckResult(name, status, detail, evidence or {}))
        print(f"[{status.upper()}] {name}: {detail}")

    def write_outputs(self, final: bool = False) -> None:
        evidence = {
            "started_at": self.started_at.isoformat(),
            "updated_at": iso_now(),
            "api_base_url": self.api_base_url,
            "test_email_present": bool(self.email),
            "credential_values_redacted": True,
            "final": final,
            "results": [result.__dict__ for result in self.results],
            "samples": self.samples,
        }
        self.evidence_path.write_text(json.dumps(evidence, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        self.checklist_path.write_text(render_checklist(evidence), encoding="utf-8")


@dataclass
class CommandResult:
    returncode: int
    stdout: str
    stderr: str


def main() -> int:
    args = parse_args()
    missing = [name for name in REQUIRED_ENV if not os.environ.get(name)]
    if missing:
        print("Missing required environment variables:", ", ".join(missing), file=sys.stderr)
        print("Export SECUREWAVE_API_BASE_URL, SECUREWAVE_TEST_EMAIL, and SECUREWAVE_TEST_PASSWORD.", file=sys.stderr)
        return 2

    checker = Checker(args)

    def stop(_signum: int, _frame: Any) -> None:
        checker.stop_requested = True
        print("Stop requested; writing final cleanup sample...")

    signal.signal(signal.SIGINT, stop)
    signal.signal(signal.SIGTERM, stop)
    return checker.run()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="SecureWave Linux manual VPN background checker")
    parser.add_argument("--watch-seconds", type=int, default=900, help="Maximum manual watch duration.")
    parser.add_argument("--interval-seconds", type=int, default=10, help="Network sample interval.")
    parser.add_argument("--http-timeout", type=int, default=8, help="HTTP timeout in seconds.")
    return parser.parse_args()


def normalized_api_base(value: str) -> str:
    return value.rstrip("/")


def utc_now() -> dt.datetime:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0)


def iso_now() -> str:
    return utc_now().isoformat()


def run_command(command: list[str]) -> CommandResult:
    if not shutil.which(command[0]):
        return CommandResult(127, "", f"{command[0]} not found")
    try:
        proc = subprocess.run(command, text=True, capture_output=True, timeout=8, check=False)
        return CommandResult(proc.returncode, proc.stdout, proc.stderr)
    except Exception as exc:
        return CommandResult(1, "", str(exc))


def command_payload(result: CommandResult) -> dict[str, Any]:
    return {
        "returncode": result.returncode,
        "stdout": result.stdout[-4000:],
        "stderr": result.stderr[-2000:],
    }


def discover_interfaces() -> list[dict[str, Any]]:
    result = run_command(["ip", "-j", "-s", "link", "show"])
    if result.returncode == 0 and result.stdout.strip():
        try:
            data = json.loads(result.stdout)
            return [normalize_interface(item) for item in data]
        except json.JSONDecodeError:
            pass
    fallback = run_command(["ip", "-s", "link", "show"])
    return parse_ip_link_fallback(fallback.stdout)


def normalize_interface(item: dict[str, Any]) -> dict[str, Any]:
    stats = item.get("stats64") or item.get("stats") or {}
    rx = stats.get("rx", {}) if isinstance(stats, dict) else {}
    tx = stats.get("tx", {}) if isinstance(stats, dict) else {}
    return {
        "name": item.get("ifname", ""),
        "operstate": item.get("operstate", ""),
        "rx_bytes": int(rx.get("bytes") or 0),
        "tx_bytes": int(tx.get("bytes") or 0),
    }


def parse_ip_link_fallback(output: str) -> list[dict[str, Any]]:
    interfaces: list[dict[str, Any]] = []
    current: dict[str, Any] | None = None
    for line in output.splitlines():
        header = re.match(r"^\d+:\s+([^:@]+)", line)
        if header:
            current = {"name": header.group(1), "operstate": "", "rx_bytes": 0, "tx_bytes": 0}
            interfaces.append(current)
            continue
        if current and "state " in line:
            state = re.search(r"\bstate\s+(\S+)", line)
            if state:
                current["operstate"] = state.group(1)
    return interfaces


def fetch_first_public_ip() -> str | None:
    for url in PUBLIC_IP_URLS:
        try:
            request = urllib.request.Request(url, headers={"User-Agent": "securewave-manual-checker/1"})
            with urllib.request.urlopen(request, timeout=5) as response:
                text = response.read().decode("utf-8", errors="replace").strip()
                if text:
                    return text
        except Exception:
            continue
    return None


def extract_access_token(payload: Any) -> str | None:
    if isinstance(payload, dict):
        token = payload.get("access_token")
        if isinstance(token, str) and token:
            return token
    return None


def parse_json_or_text(raw: str) -> Any:
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return raw[:500]


def safe_http_evidence(result: dict[str, Any], redact_body: bool = False) -> dict[str, Any]:
    evidence: dict[str, Any] = {"ok": result.get("ok"), "status": result.get("status")}
    if result.get("error"):
        evidence["error"] = result["error"]
    if not redact_body and isinstance(result.get("json"), dict):
        evidence["json_keys"] = sorted(str(key) for key in result["json"].keys())
    elif redact_body:
        evidence["body_redacted"] = True
    return evidence


def status_detail(result: dict[str, Any]) -> str:
    if result.get("ok"):
        return f"HTTP {result.get('status')}"
    if result.get("status"):
        return f"HTTP {result.get('status')}"
    return str(result.get("error") or "request failed")


def summarize_payload(path: str, result: dict[str, Any]) -> str:
    if not result.get("ok"):
        return status_detail(result)
    payload = result.get("json")
    if path == "/vpn/servers" and isinstance(payload, dict):
        servers = payload.get("servers")
        if isinstance(servers, list):
            return f"HTTP {result.get('status')}; servers={len(servers)}"
    if path == "/user/plan" and isinstance(payload, dict):
        plan = payload.get("plan") or payload.get("tier") or payload.get("name")
        return f"HTTP {result.get('status')}; plan={plan or 'unknown'}"
    return f"HTTP {result.get('status')}"


def render_checklist(evidence: dict[str, Any]) -> str:
    lines = [
        "# SecureWave Linux Manual VPN Checklist",
        "",
        f"- Run started: {evidence['started_at']}",
        f"- Last updated: {evidence['updated_at']}",
        f"- API base URL: {evidence['api_base_url']}",
        "- Credential values: redacted; not written to this artifact",
        "- Primary result mode: live-first; mock mode is fallback only",
        "",
        "## Automated Checks",
        "",
    ]
    for result in evidence["results"]:
        lines.append(f"- [{result['status'].upper()}] {result['name']}: {result['detail']}")

    lines.extend(
        [
            "",
            "## Network Samples",
            "",
            "| Time | Public IP | Changed | Watched interfaces | RX bytes | TX bytes |",
            "| --- | --- | --- | --- | ---: | ---: |",
        ]
    )
    for sample in evidence["samples"]:
        watched = sample.get("watched_interfaces", [])
        names = ", ".join(item.get("name", "") for item in watched) or "none"
        rx_total = sum(int(item.get("rx_bytes") or 0) for item in watched)
        tx_total = sum(int(item.get("tx_bytes") or 0) for item in watched)
        changed = "yes" if sample.get("public_ip_changed_from_baseline") else "no"
        lines.append(
            f"| {sample.get('timestamp')} | {sample.get('public_ip') or 'unknown'} | "
            f"{changed} | {names} | {rx_total} | {tx_total} |"
        )

    lines.extend(
        [
            "",
            "## Human Manual Notes",
            "",
            "- Tester:",
            "- Flutter command:",
            "- App mock API disabled for primary result: yes/no",
            "- Login succeeded in app: yes/no",
            "- Dashboard loaded: yes/no",
            "- Server list appeared: yes/no",
            "- Account mode shown:",
            "- Diagnostics readable: yes/no",
            "- Selected server/protocol:",
            "- App connected state shown: yes/no",
            "- Baseline public IP:",
            "- Connected public IP:",
            "- External leak-check IP/DNS notes:",
            "- App data gauge moved: yes/no",
            "- Checker RX/TX moved: yes/no/unknown",
            "- App disconnected state shown: yes/no",
            "- Tunnel cleanup passed: yes/no",
            "- Bugs found:",
            "- Final verdict: PASS / FAIL / BLOCKED / MOCK-FALLBACK-ONLY",
            "",
            "## Verdict Rule",
            "",
            "Only a real Linux live run with public IP change, tunnel evidence, traffic movement, "
            "and cleanup can be marked PASS. Mock mode is diagnostic only.",
            "",
        ]
    )
    return "\n".join(lines)


if __name__ == "__main__":
    raise SystemExit(main())
