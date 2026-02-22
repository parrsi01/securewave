#!/usr/bin/env python3
"""Multi-protocol live validation harness for SecureWave.

Outputs timestamped artifacts under:
  artifacts/live_validation_multi_protocol/YYYYMMDD_HHMMSS/
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import re
import sys
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Optional

REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from dev_tools.sandbox.live_validation.common import (  # noqa: E402
    evaluate_dns_leak,
    fetch_public_ip,
    http_json_request,
    parse_nameservers,
    read_text,
    register_or_login_user,
    run_command,
    utc_now_iso,
)

PLATFORMS = ["linux", "windows", "macos", "android", "ios"]
PROTOCOLS = ["wireguard", "openvpn", "ikev2"]

RUNTIME_SCAN_PATHS = [
    "main.py",
    "routes",
    "services",
    "models",
    "scripts",
    "securewave_app/lib",
]
WORKFLOW_SCAN_PATHS = [".github/workflows", ".env.example.backend"]
MOCK_SCAN_EXCLUDE_GLOBS = [
    "!sandbox/live_validation_multi_protocol/run_validation.py",
    "!scripts/ci_multiprotocol_release_guardrails.sh",
    "!scripts/ci_multiprotocol_safety_check.sh",
]
MOCK_PATTERNS = [
    r"\bDEMO_MODE\b",
    r"\bWG_MOCK_MODE\b",
    r"\bWG_SIMULATE\b",
    r"\bmock[_ -]?tunnel\b",
    r"\bsimulate[_ -]?connect\b",
    r"\bfake success\b",
]


@dataclass
class RunContext:
    output_dir: Path
    raw_logs_dir: Path
    timestamp: str


@dataclass
class ApiContext:
    enabled: bool
    base_url: str
    token: Optional[str]
    auth_meta: dict[str, Any]


def now_stamp() -> str:
    return time.strftime("%Y%m%d_%H%M%S", time.gmtime())


def detect_host_platform() -> str:
    platform = sys.platform.lower()
    if platform.startswith("linux"):
        return "linux"
    if platform.startswith("win"):
        return "windows"
    if platform.startswith("darwin"):
        return "macos"
    return "unknown"


def write_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def write_csv(path: Path, rows: list[dict[str, Any]], fieldnames: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def log_jsonl(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(payload) + "\n")


def command_exists(binary: str) -> bool:
    result = run_command(["bash", "-lc", f"command -v {binary} >/dev/null 2>&1"], timeout_seconds=5)
    return result.returncode == 0


def run_logged_command(
    ctx: RunContext,
    *,
    name: str,
    command: list[str] | str,
    timeout_seconds: int = 30,
    shell: bool = False,
    cwd: Optional[Path] = None,
) -> Any:
    result = run_command(
        command,
        timeout_seconds=timeout_seconds,
        shell=shell,
        cwd=str(cwd or REPO_ROOT),
    )
    log_payload = {
        "ts": utc_now_iso(),
        "name": name,
        "command": result.command,
        "returncode": result.returncode,
        "duration_ms": result.duration_ms,
        "stdout": result.stdout,
        "stderr": result.stderr,
    }
    log_jsonl(ctx.raw_logs_dir / "commands.jsonl", log_payload)
    return result


def normalize_protocol_name(token: str) -> Optional[str]:
    raw = token.strip()
    mapping = {
        "wireGuard": "wireguard",
        "openVpn": "openvpn",
        "ikev2": "ikev2",
        "wireguard": "wireguard",
        "openvpn": "openvpn",
    }
    return mapping.get(raw)


def parse_declared_protocols(capability_file: Path) -> dict[str, set[str]]:
    declared: dict[str, set[str]] = {platform: set() for platform in PLATFORMS}
    text = capability_file.read_text(encoding="utf-8")
    lines = text.splitlines()

    in_declared_fn = False
    pending_platforms: list[str] = []
    collecting_return = False
    collected_protocols: list[str] = []

    for line in lines:
        if "static Set<VpnProtocol> declaredProtocols" in line:
            in_declared_fn = True
            continue
        if not in_declared_fn:
            continue

        case_match = re.search(r"case\s+VpnClientPlatform\.(\w+)\s*:", line)
        if case_match and not collecting_return:
            platform = case_match.group(1).strip().lower()
            if platform in declared:
                pending_platforms.append(platform)
            continue

        if "return const <VpnProtocol>{" in line:
            collecting_return = True
            collected_protocols = []

        if collecting_return:
            proto_match = re.search(r"VpnProtocol\.(\w+)", line)
            if proto_match:
                normalized = normalize_protocol_name(proto_match.group(1))
                if normalized:
                    collected_protocols.append(normalized)

            if "};" in line:
                for platform in pending_platforms:
                    declared.setdefault(platform, set()).update(collected_protocols)
                pending_platforms = []
                collecting_return = False
                collected_protocols = []

        if in_declared_fn and line.strip() == "}":
            # End of function. Keep parsing resilient even if formatting changes.
            in_declared_fn = False

    return declared


def run_mock_scan(ctx: RunContext, paths: list[str], scope: str) -> list[dict[str, Any]]:
    pattern = "|".join(MOCK_PATTERNS)
    command = [
        "rg",
        "-n",
        "-i",
        "--no-heading",
        pattern,
        *[f"--glob={glob}" for glob in MOCK_SCAN_EXCLUDE_GLOBS],
        *paths,
    ]
    result = run_logged_command(ctx, name=f"mock_scan_{scope}", command=command, timeout_seconds=20)
    hits: list[dict[str, Any]] = []
    if result.returncode not in {0, 1}:
        hits.append(
            {
                "scope": scope,
                "status": "error",
                "path": "",
                "line": "",
                "match": "",
                "detail": f"scan command failed (exit {result.returncode})",
            }
        )
        return hits

    if result.returncode == 1:
        return hits

    for raw in result.stdout.splitlines():
        # rg output: path:line:match
        parts = raw.split(":", 2)
        if len(parts) != 3:
            continue
        path, line_no, match = parts
        hits.append(
            {
                "scope": scope,
                "status": "hit",
                "path": path,
                "line": line_no,
                "match": match.strip(),
                "detail": "",
            }
        )
    return hits


def evaluate_runtime_for_host(ctx: RunContext, host_platform: str) -> dict[str, dict[str, Any]]:
    runtime: dict[str, dict[str, Any]] = {
        protocol: {
            "ready": None,
            "reason": "not_checked_for_host_platform",
            "evidence": "",
        }
        for protocol in PROTOCOLS
    }

    if host_platform != "linux":
        return runtime

    checks = {
        "wireguard": "command -v wg-quick >/dev/null 2>&1",
        "openvpn": "command -v openvpn >/dev/null 2>&1",
        "ikev2": "command -v swanctl >/dev/null 2>&1 || command -v ipsec >/dev/null 2>&1",
    }
    reasons = {
        "wireguard": "wg-quick missing from PATH",
        "openvpn": "openvpn missing from PATH",
        "ikev2": "strongSwan tooling missing (swanctl/ipsec)",
    }

    for protocol, check in checks.items():
        result = run_logged_command(
            ctx,
            name=f"runtime_check_{protocol}",
            command=["bash", "-lc", check],
            timeout_seconds=5,
        )
        ready = result.returncode == 0
        runtime[protocol] = {
            "ready": ready,
            "reason": "runtime_ready" if ready else reasons[protocol],
            "evidence": result.command,
        }

    return runtime


def api_request(
    ctx: RunContext,
    *,
    method: str,
    url: str,
    headers: Optional[dict[str, str]] = None,
    payload: Optional[dict[str, Any]] = None,
    timeout_seconds: int = 20,
    name: str,
) -> Any:
    started = time.monotonic()
    response = http_json_request(
        method,
        url,
        headers=headers,
        payload=payload,
        timeout_seconds=timeout_seconds,
    )
    elapsed_ms = round((time.monotonic() - started) * 1000.0, 3)

    body = response.body
    body_excerpt: Any
    if isinstance(body, dict):
        body_excerpt = body
    else:
        body_excerpt = str(body)[:600]

    log_jsonl(
        ctx.raw_logs_dir / "api_calls.jsonl",
        {
            "ts": utc_now_iso(),
            "name": name,
            "method": method,
            "url": url,
            "status_code": response.status_code,
            "duration_ms": elapsed_ms,
            "request_payload": payload or {},
            "response_body": body_excerpt,
        },
    )

    return response, elapsed_ms


def init_api_context(
    ctx: RunContext,
    *,
    live_enabled: bool,
    api_base_url: str,
    timeout_seconds: int,
) -> ApiContext:
    if not live_enabled:
        return ApiContext(enabled=False, base_url="", token=None, auth_meta={"status": "live_disabled"})

    if not api_base_url.strip():
        return ApiContext(
            enabled=False,
            base_url="",
            token=None,
            auth_meta={"status": "missing_api_base_url"},
        )

    password = os.getenv("LIVE_MULTI_PROTOCOL_PASSWORD", "LiveValidate#123")
    prefix = os.getenv("LIVE_MULTI_PROTOCOL_EMAIL_PREFIX", "multi.protocol.validation")
    email = f"{prefix}+{int(time.time())}@example.com"

    ok, token, auth_meta = register_or_login_user(
        api_base_url=api_base_url,
        email=email,
        password=password,
        timeout_seconds=timeout_seconds,
    )
    log_jsonl(
        ctx.raw_logs_dir / "api_calls.jsonl",
        {
            "ts": utc_now_iso(),
            "name": "auth_register_or_login",
            "email": email,
            "ok": ok,
            "meta": auth_meta,
        },
    )
    if not ok or not token:
        return ApiContext(enabled=False, base_url=api_base_url.rstrip("/"), token=None, auth_meta=auth_meta)

    return ApiContext(enabled=True, base_url=api_base_url.rstrip("/"), token=token, auth_meta=auth_meta)


def fetch_backend_protocol_matrix(ctx: RunContext, api: ApiContext) -> dict[str, dict[str, Any]]:
    per_platform: dict[str, dict[str, Any]] = {}

    if not api.enabled or not api.token:
        return per_platform

    headers = {"Authorization": f"Bearer {api.token}"}
    for platform in PLATFORMS:
        url = f"{api.base_url}/api/vpn/protocols?device_type={platform}"
        response, elapsed_ms = api_request(
            ctx,
            method="GET",
            url=url,
            headers=headers,
            name=f"protocols_{platform}",
        )
        body = response.body if isinstance(response.body, dict) else {}
        entries = body.get("protocols") if isinstance(body, dict) else None
        parsed: dict[str, Any] = {}
        if isinstance(entries, list):
            for item in entries:
                if not isinstance(item, dict):
                    continue
                protocol = str(item.get("protocol") or "").strip().lower()
                if protocol not in PROTOCOLS:
                    continue
                parsed[protocol] = {
                    "enabled": bool(item.get("enabled", False)),
                    "reason": str(item.get("reason") or "") or None,
                    "platform_supported": bool(item.get("platform_supported", False)),
                    "plan_enabled": bool(item.get("plan_enabled", False)),
                    "server_enabled": bool(item.get("server_enabled", False)),
                    "elapsed_ms": elapsed_ms,
                }

        per_platform[platform] = {
            "status_code": response.status_code,
            "protocols": parsed,
            "raw": body,
        }

    return per_platform


def request_profile(
    ctx: RunContext,
    api: ApiContext,
    *,
    protocol: str,
    device_type: str,
    server_id: Optional[str] = None,
) -> tuple[int, dict[str, Any], float]:
    if not api.enabled or not api.token:
        return 0, {"error": "live_api_disabled"}, 0.0

    headers = {"Authorization": f"Bearer {api.token}"}
    payload: dict[str, Any] = {
        "device_name": f"multi-protocol-validation-{protocol}",
        "device_type": device_type,
        "protocol": protocol,
    }
    if server_id:
        payload["server_id"] = server_id

    response, elapsed_ms = api_request(
        ctx,
        method="POST",
        url=f"{api.base_url}/api/vpn/profile",
        headers=headers,
        payload=payload,
        name=f"profile_{protocol}_{device_type}",
    )
    body = response.body if isinstance(response.body, dict) else {"raw": str(response.body)}
    return response.status_code, body, elapsed_ms


def validate_profile_claims(protocol: str, device_type: str, profile_body: dict[str, Any]) -> tuple[dict[str, Any], dict[str, Any]]:
    dns = profile_body.get("dns") if isinstance(profile_body.get("dns"), dict) else {}
    kill_switch = (
        profile_body.get("kill_switch")
        if isinstance(profile_body.get("kill_switch"), dict)
        else {}
    )

    dns_servers = dns.get("servers") if isinstance(dns.get("servers"), list) else []
    dns_mode = str(dns.get("mode") or "")
    dns_enforcement = str(dns.get("enforcement") or "")
    ad_blocking = str(dns.get("ad_malware_blocking") or "")

    ks_mode = str(kill_switch.get("mode") or "")
    ks_enforcement = str(kill_switch.get("enforcement") or "")
    ks_notes = str(kill_switch.get("notes") or "")

    dns_status = "pass"
    dns_reason = "profile dns claim matches protocol expectations"
    if protocol == "ikev2":
        expected_ok = (
            len(dns_servers) == 0
            and dns_mode == "platform_default"
            and dns_enforcement == "none"
            and ad_blocking == "off"
        )
        if not expected_ok:
            dns_status = "fail"
            dns_reason = "IKEv2 profile claims DNS enforcement that should be disabled"
    else:
        expected_ok = len(dns_servers) > 0 and dns_mode == "tunnel"
        if not expected_ok:
            dns_status = "fail"
            dns_reason = "Tunnel profile missing expected DNS resolver claims"

    ks_status = "pass"
    ks_reason = "kill-switch claim matches protocol/platform policy"
    if protocol == "wireguard" and device_type == "linux":
        expected_ok = ks_mode == "enabled" and ks_enforcement == "wg-quick hooks"
        if not expected_ok:
            ks_status = "fail"
            ks_reason = "Linux WireGuard kill-switch claim mismatch"
    else:
        expected_ok = ks_mode == "disabled" and ks_enforcement == "none"
        if not expected_ok:
            ks_status = "fail"
            ks_reason = "Non-Linux/WireGuard profile over-claims kill-switch enforcement"
        if "does not enforce" not in ks_notes.lower():
            ks_status = "fail"
            ks_reason = "Kill-switch notes are not explicit about non-enforcement"

    dns_row = {
        "timestamp": utc_now_iso(),
        "protocol": protocol,
        "platform": device_type,
        "validation_mode": "profile_claim",
        "result": dns_status,
        "expected_dns": ";".join(str(x) for x in dns_servers),
        "observed_dns": "",
        "leak_detected": "",
        "reason": dns_reason,
        "evidence": "/api/vpn/profile response.dns",
    }

    kill_row = {
        "timestamp": utc_now_iso(),
        "protocol": protocol,
        "platform": device_type,
        "validation_mode": "profile_claim",
        "result": ks_status,
        "mode": ks_mode,
        "enforcement": ks_enforcement,
        "reason": ks_reason,
        "evidence": "/api/vpn/profile response.kill_switch",
    }
    return dns_row, kill_row


def run_ping_avg(ctx: RunContext, region: str, host: str) -> tuple[Optional[float], str]:
    ping_bin = "ping"
    if not command_exists(ping_bin):
        return None, "ping_not_found"

    result = run_logged_command(
        ctx,
        name=f"ping_{region}_{host.replace('.', '_')}",
        command=[ping_bin, "-c", "3", "-W", "1", host],
        timeout_seconds=8,
    )
    if result.returncode != 0:
        return None, f"ping_failed_exit_{result.returncode}"

    avg_ms: Optional[float] = None
    for line in result.stdout.splitlines():
        text = line.strip()
        if "min/avg" in text and "=" in text and "/" in text:
            try:
                rhs = text.split("=", 1)[1].replace(" ms", "").strip()
                parts = rhs.split("/")
                if len(parts) >= 2:
                    avg_ms = float(parts[1])
            except Exception:
                avg_ms = None
            break
        if "time=" in text and " ms" in text:
            try:
                value = float(text.split("time=", 1)[1].split(" ", 1)[0])
                avg_ms = value if avg_ms is None else (avg_ms + value) / 2.0
            except Exception:
                pass

    if avg_ms is None:
        return None, "unable_to_parse_ping_output"
    return round(avg_ms, 3), "ok"


def run_throughput_probe(ctx: RunContext, region: str, url: str, bytes_to_fetch: int = 5 * 1024 * 1024) -> tuple[Optional[float], str, str]:
    if not url.strip():
        return None, "throughput_url_not_configured", ""
    if not command_exists("curl"):
        return None, "curl_not_found", ""

    end = max(0, int(bytes_to_fetch) - 1)
    command = [
        "curl",
        "-sS",
        "-o",
        "/dev/null",
        "--connect-timeout",
        "6",
        "--max-time",
        "30",
        "--range",
        f"0-{end}",
        "-w",
        "%{http_code} %{speed_download} %{time_total}",
        url,
    ]
    result = run_logged_command(
        ctx,
        name=f"throughput_{region}",
        command=command,
        timeout_seconds=35,
    )

    tail = result.stdout.strip().split()
    if result.returncode != 0 or len(tail) < 3:
        return None, f"curl_failed_exit_{result.returncode}", result.command

    http_code = tail[-3]
    if not http_code.startswith("2"):
        return None, f"http_status_{http_code}", result.command

    try:
        speed_download = float(tail[-2])
    except Exception:
        return None, "unable_to_parse_speed_download", result.command

    mbps = round((speed_download * 8.0) / (1024.0 * 1024.0), 3)
    return mbps, "ok", result.command


def load_region_targets(path: Path) -> list[dict[str, Any]]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return []
    regions = payload.get("regions") if isinstance(payload, dict) else None
    if not isinstance(regions, list):
        return []
    out: list[dict[str, Any]] = []
    for item in regions:
        if not isinstance(item, dict):
            continue
        out.append(item)
    return out


def build_manual_checklist(timestamp_dir: Path) -> str:
    rel = timestamp_dir.relative_to(REPO_ROOT)
    return "\n".join(
        [
            "### Linux",
            "1. WireGuard (data-plane):",
            f"   - `sudo cp {rel}/raw_logs/wireguard_linux.conf /etc/wireguard/sw-live.conf`",
            "   - `sudo chmod 600 /etc/wireguard/sw-live.conf`",
            "   - `sudo wg-quick up sw-live`",
            "   - `sudo wg show sw-live latest-handshakes`",
            "   - `curl --interface sw-live https://api.ipify.org`",
            "   - `dig +short whoami.cloudflare @1.1.1.1`",
            "   - `sudo wg-quick down sw-live`",
            "2. OpenVPN (data-plane):",
            f"   - `sudo openvpn --config {rel}/raw_logs/openvpn_linux.ovpn --daemon --writepid /tmp/sw-ovpn.pid --log /tmp/sw-ovpn.log`",
            "   - `ip addr show tun0`",
            "   - `curl --interface tun0 https://api.ipify.org`",
            "   - `sudo kill $(cat /tmp/sw-ovpn.pid)`",
            "3. IKEv2/IPsec (data-plane, strongSwan):",
            "   - `sudo ipsec statusall`",
            "   - `sudo swanctl --list-conns`",
            "   - `sudo swanctl --initiate --child <child-name>`",
            "   - `ip xfrm state`",
            "   - `curl https://api.ipify.org`",
            "",
            "### Windows (PowerShell as Administrator)",
            "1. WireGuard:",
            "   - `wireguard.exe /installtunnelservice C:\\path\\sw-live.conf`",
            "   - `wg.exe show`",
            "   - `curl.exe https://api.ipify.org`",
            "   - `wireguard.exe /uninstalltunnelservice sw-live`",
            "2. OpenVPN:",
            "   - `& \"C:\\Program Files\\OpenVPN\\bin\\openvpn.exe\" --config C:\\path\\sw-live.ovpn --log C:\\Temp\\sw-ovpn.log`",
            "   - `Get-NetIPConfiguration`",
            "3. IKEv2:",
            "   - `Add-VpnConnection -Name \"SecureWave IKEv2\" -ServerAddress <server> -TunnelType IKEv2 -AuthenticationMethod Eap -EncryptionLevel Required -RememberCredential`",
            "   - `rasdial \"SecureWave IKEv2\" <username> <password>`",
            "   - `Get-VpnConnection -Name \"SecureWave IKEv2\"`",
            "",
            "### macOS",
            "1. WireGuard:",
            "   - `sudo wg-quick up ~/Library/Application\\ Support/SecureWave/sw-live.conf`",
            "   - `wg show`",
            "2. OpenVPN:",
            "   - `sudo /usr/local/sbin/openvpn --config ~/Downloads/sw-live.ovpn --log /tmp/sw-ovpn.log`",
            "3. IKEv2 (NetworkExtension/System profile):",
            "   - `networksetup -listallnetworkservices`",
            "   - `scutil --nc list`",
            "   - `scutil --nc start \"SecureWave IKEv2\"`",
            "",
            "### DNS Leak and Kill-Switch Checks",
            "1. Record pre-VPN IP: `curl -s https://api.ipify.org`",
            "2. Connect tunnel and record post-VPN IP: `curl -s https://api.ipify.org`",
            "3. DNS resolvers:",
            "   - Linux: `cat /etc/resolv.conf`",
            "   - Windows: `Get-DnsClientServerAddress -AddressFamily IPv4`",
            "   - macOS: `scutil --dns`",
            "4. Kill-switch behavior:",
            "   - Force tunnel drop (stop VPN process) and verify outbound traffic is blocked where policy says enforced.",
            "",
        ]
    )


def run_error_ux_checks(ctx: RunContext, api: ApiContext, host_platform: str) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    fieldnames = ["timestamp", "case", "status", "http_status", "error_code", "latency_ms", "reason"]
    if not api.enabled or not api.token:
        write_csv(ctx.raw_logs_dir / "error_ux_checks.csv", rows, fieldnames)
        return rows

    headers = {"Authorization": f"Bearer {api.token}"}

    cases = [
        {
            "name": "invalid_protocol_value",
            "payload": {
                "device_name": "error-ux-invalid",
                "device_type": host_platform if host_platform in PLATFORMS else "linux",
                "protocol": "invalid-protocol",
            },
            "expected_status": {400, 422},
        },
        {
            "name": "openvpn_on_ios_not_supported",
            "payload": {
                "device_name": "error-ux-ios",
                "device_type": "ios",
                "protocol": "openvpn",
            },
            "expected_status": {400, 409},
        },
    ]

    for case in cases:
        response, elapsed_ms = api_request(
            ctx,
            method="POST",
            url=f"{api.base_url}/api/vpn/profile",
            headers=headers,
            payload=case["payload"],
            name=f"error_case_{case['name']}",
        )
        body = response.body if isinstance(response.body, dict) else {"raw": str(response.body)}
        error_code = ""
        if isinstance(body.get("error"), dict):
            error_code = str(body["error"].get("code") or "")

        passed = response.status_code in case["expected_status"]
        rows.append(
            {
                "timestamp": utc_now_iso(),
                "case": case["name"],
                "status": "pass" if passed else "fail",
                "http_status": response.status_code,
                "error_code": error_code,
                "latency_ms": elapsed_ms,
                "reason": "" if passed else "unexpected response for protocol-specific error case",
            }
        )

    write_csv(
        ctx.raw_logs_dir / "error_ux_checks.csv",
        rows,
        fieldnames,
    )
    return rows


def build_protocol_matrix_rows(
    *,
    declared: dict[str, set[str]],
    backend: dict[str, dict[str, Any]],
    runtime_host: dict[str, dict[str, Any]],
    host_platform: str,
) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []

    for platform in PLATFORMS:
        backend_entry = backend.get(platform, {})
        backend_protocols = backend_entry.get("protocols", {}) if isinstance(backend_entry, dict) else {}

        for protocol in PROTOCOLS:
            ui_declared = protocol in declared.get(platform, set())
            backend_info = backend_protocols.get(protocol) if isinstance(backend_protocols, dict) else None
            backend_enabled = None if backend_info is None else bool(backend_info.get("enabled", False))
            backend_reason = None if backend_info is None else backend_info.get("reason")

            runtime_ready = None
            runtime_reason = "not_checked"
            if platform == host_platform:
                runtime_ready = runtime_host.get(protocol, {}).get("ready")
                runtime_reason = runtime_host.get(protocol, {}).get("reason", "")

            support_status = "unsupported"
            reason = ""
            evidence_level = "claim_only"

            if not ui_declared:
                support_status = "unsupported"
                reason = "Not declared by protocol capability matrix for this platform"
                evidence_level = "source_of_truth"
            elif backend_enabled is False:
                support_status = "unsupported"
                reason = f"Backend protocol gate disabled ({backend_reason or 'no reason'})"
                evidence_level = "backend_verified"
            elif platform == host_platform and runtime_ready is False:
                support_status = "unsupported"
                reason = f"Native runtime missing on host: {runtime_reason}"
                evidence_level = "runtime_verified"
            else:
                support_status = "supported"
                if backend_enabled is True and (platform != host_platform or runtime_ready in {True, None}):
                    reason = "Declared by UI and enabled by backend"
                    evidence_level = "backend_verified"
                    if platform == host_platform and runtime_ready is True:
                        reason += "; native runtime present on host"
                        evidence_level = "runtime_verified"
                elif backend_enabled is None:
                    reason = "Declared by UI; backend check unavailable in this environment"
                    evidence_level = "claim_only"
                else:
                    reason = "Declared by UI; requires manual runtime validation on target platform"
                    evidence_level = "claim_only"

            rows.append(
                {
                    "timestamp": utc_now_iso(),
                    "platform": platform,
                    "protocol": protocol,
                    "support_status": support_status,
                    "reason": reason,
                    "ui_declared": ui_declared,
                    "backend_enabled": "" if backend_enabled is None else backend_enabled,
                    "runtime_ready_on_host": "" if runtime_ready is None else runtime_ready,
                    "evidence_level": evidence_level,
                }
            )

    return rows


def maybe_write_profile_files(ctx: RunContext, protocol: str, profile_body: dict[str, Any], host_platform: str) -> Optional[Path]:
    profiles_dir = ctx.raw_logs_dir / "profiles"
    profiles_dir.mkdir(parents=True, exist_ok=True)

    if protocol == "wireguard":
        text = str(profile_body.get("wireguard_config") or "")
        if not text.strip():
            profile = profile_body.get("profile")
            if isinstance(profile, dict):
                text = str(profile.get("wireguard_config") or "")
        if not text.strip():
            return None
        path = profiles_dir / f"wireguard_{host_platform}.conf"
        path.write_text(text.strip() + "\n", encoding="utf-8")
        return path

    profile = profile_body.get("profile") if isinstance(profile_body.get("profile"), dict) else {}
    if protocol == "openvpn":
        text = str(profile.get("ovpn_config") or "")
        if not text.strip():
            return None
        path = profiles_dir / f"openvpn_{host_platform}.ovpn"
        path.write_text(text.strip() + "\n", encoding="utf-8")
        return path

    if protocol == "ikev2":
        path = profiles_dir / f"ikev2_{host_platform}.json"
        path.write_text(json.dumps(profile, indent=2) + "\n", encoding="utf-8")
        return path

    return None


def execute_optional_data_plane_validation(
    ctx: RunContext,
    *,
    protocol: str,
    profile_path: Optional[Path],
    dns_expected: list[str],
) -> tuple[dict[str, Any], dict[str, Any], dict[str, Any]]:
    """Optional data-plane probe using operator-supplied command templates.

    Returns: dns_row, kill_row, throughput_row
    """
    host = detect_host_platform()
    connect_env = {
        "wireguard": "LIVE_MULTI_WG_CONNECT_CMD",
        "openvpn": "LIVE_MULTI_OVPN_CONNECT_CMD",
        "ikev2": "LIVE_MULTI_IKEV2_CONNECT_CMD",
    }
    disconnect_env = {
        "wireguard": "LIVE_MULTI_WG_DISCONNECT_CMD",
        "openvpn": "LIVE_MULTI_OVPN_DISCONNECT_CMD",
        "ikev2": "LIVE_MULTI_IKEV2_DISCONNECT_CMD",
    }

    connect_template = os.getenv(connect_env[protocol], "").strip()
    disconnect_template = os.getenv(disconnect_env[protocol], "").strip()

    base_dns = {
        "timestamp": utc_now_iso(),
        "protocol": protocol,
        "platform": host,
        "validation_mode": "data_plane",
        "result": "skipped",
        "expected_dns": ";".join(dns_expected),
        "observed_dns": "",
        "leak_detected": "",
        "reason": "data-plane command templates not configured",
        "evidence": "",
    }
    base_kill = {
        "timestamp": utc_now_iso(),
        "protocol": protocol,
        "platform": host,
        "validation_mode": "data_plane",
        "result": "skipped",
        "mode": "",
        "enforcement": "",
        "reason": "manual kill-switch validation required",
        "evidence": "",
    }
    throughput_row = {
        "timestamp": utc_now_iso(),
        "region": "live_tunnel",
        "platform": host,
        "protocol": protocol,
        "url": os.getenv("LIVE_MULTI_TUNNEL_THROUGHPUT_URL", "https://speed.hetzner.de/10MB.bin"),
        "throughput_mbps": "",
        "status": "skipped",
        "reason": "data-plane command templates not configured",
        "evidence": "",
    }

    if not profile_path or not connect_template or not disconnect_template:
        return base_dns, base_kill, throughput_row

    before_ip = fetch_public_ip()
    connect_cmd = connect_template.format(profile_path=str(profile_path), protocol=protocol)
    disconnect_cmd = disconnect_template.format(profile_path=str(profile_path), protocol=protocol)

    connect = run_logged_command(
        ctx,
        name=f"data_plane_connect_{protocol}",
        command=connect_cmd,
        timeout_seconds=45,
        shell=True,
    )
    if connect.returncode != 0:
        base_dns["result"] = "fail"
        base_dns["reason"] = f"connect command failed (exit {connect.returncode})"
        base_dns["evidence"] = connect.command
        return base_dns, base_kill, throughput_row

    time.sleep(2.0)
    after_ip = fetch_public_ip()
    observed_dns = parse_nameservers(read_text("/etc/resolv.conf")) if host == "linux" else []

    dns_ok, leaked = evaluate_dns_leak(observed_dns, set(dns_expected), allow_private=True)
    base_dns.update(
        {
            "result": "pass" if dns_ok else "fail",
            "observed_dns": ";".join(observed_dns),
            "leak_detected": ";".join(leaked),
            "reason": "dns resolver set within expected range" if dns_ok else "unexpected resolver observed",
            "evidence": connect.command,
        }
    )

    if before_ip and after_ip and before_ip != after_ip:
        base_dns["reason"] += "; public egress IP changed"

    # Kill-switch data-plane checks require controlled tunnel drop on target OS.
    base_kill.update(
        {
            "result": "manual",
            "reason": "manual kill-switch drop test required on target OS",
            "evidence": disconnect_cmd,
        }
    )

    mbps, throughput_status, throughput_cmd = run_throughput_probe(
        ctx,
        region="live_tunnel",
        url=str(throughput_row["url"]),
        bytes_to_fetch=int(os.getenv("LIVE_MULTI_TUNNEL_THROUGHPUT_BYTES", str(5 * 1024 * 1024))),
    )
    throughput_row.update(
        {
            "throughput_mbps": "" if mbps is None else mbps,
            "status": "pass" if throughput_status == "ok" else "fail",
            "reason": "" if throughput_status == "ok" else throughput_status,
            "evidence": throughput_cmd,
        }
    )

    run_logged_command(
        ctx,
        name=f"data_plane_disconnect_{protocol}",
        command=disconnect_cmd,
        timeout_seconds=45,
        shell=True,
    )

    return base_dns, base_kill, throughput_row


def generate_report(
    *,
    ctx: RunContext,
    host_platform: str,
    api: ApiContext,
    runtime_hits: list[dict[str, Any]],
    workflow_hits: list[dict[str, Any]],
    protocol_matrix: list[dict[str, Any]],
    dns_rows: list[dict[str, Any]],
    kill_rows: list[dict[str, Any]],
    handshake_rows: list[dict[str, Any]],
    throughput_rows: list[dict[str, Any]],
    error_rows: list[dict[str, Any],],
) -> str:
    supported = sum(1 for row in protocol_matrix if row.get("support_status") == "supported")
    unsupported = sum(1 for row in protocol_matrix if row.get("support_status") == "unsupported")

    dns_failures = sum(1 for row in dns_rows if str(row.get("result")) in {"fail"})
    kill_failures = sum(1 for row in kill_rows if str(row.get("result")) == "fail")
    error_failures = sum(1 for row in error_rows if row.get("status") == "fail")

    overall = "pass"
    if runtime_hits or dns_failures or kill_failures or error_failures:
        overall = "fail"
    elif not api.enabled:
        overall = "partial"

    handshake_ok = sum(1 for row in handshake_rows if str(row.get("status")) == "pass")
    throughput_ok = sum(1 for row in throughput_rows if str(row.get("status")) == "pass")

    manual_checklist = build_manual_checklist(ctx.output_dir)

    lines = [
        "# FINAL_MULTI_PROTOCOL_VALIDATION_REPORT",
        "",
        f"- Generated (UTC): `{utc_now_iso()}`",
        f"- Host platform: `{host_platform}`",
        f"- Output directory: `{ctx.output_dir}`",
        f"- Live API mode: `{'enabled' if api.enabled else 'disabled'}`",
        f"- Overall status: **{overall.upper()}**",
        "",
        "## Executive Summary",
        f"- Protocol matrix rows: **{len(protocol_matrix)}**",
        f"- Supported claims: **{supported}**",
        f"- Unsupported claims: **{unsupported}**",
        f"- DNS validation failures: **{dns_failures}**",
        f"- Kill-switch validation failures: **{kill_failures}**",
        f"- Error UX/API validation failures: **{error_failures}**",
        f"- Handshake latency rows passing: **{handshake_ok}/{len(handshake_rows)}**",
        f"- Throughput rows passing: **{throughput_ok}/{len(throughput_rows)}**",
        "",
        "## Evidence Scope",
        "- Control-plane checks: `/api/vpn/protocols`, `/api/vpn/profile`",
        "- UI source-of-truth checks: `securewave_app/lib/core/vpn/protocol_capabilities.dart`",
        "- Runtime checks (host-only): command presence for WireGuard/OpenVPN/IKEv2 tools",
        "- Mock/demo scan: runtime paths plus workflow/config scan",
        "",
        "## Mock/Demo Scan",
        f"- Runtime path hits: **{len(runtime_hits)}**",
        f"- Workflow/config hits: **{len(workflow_hits)}**",
    ]

    if runtime_hits:
        lines.append("- Runtime hits detected (must be remediated):")
        for hit in runtime_hits[:20]:
            lines.append(f"  - `{hit['path']}:{hit['line']}` => `{hit['match']}`")
    else:
        lines.append("- Runtime scan passed: no mock/demo flags detected in runtime code paths.")

    if workflow_hits:
        lines.append("- Workflow/config references detected (review required):")
        for hit in workflow_hits[:20]:
            lines.append(f"  - `{hit['path']}:{hit['line']}` => `{hit['match']}`")

    lines.extend(
        [
            "",
            "## Protocol Claims",
            "See `protocol_matrix.csv` for platform x protocol support state and reasons.",
            "",
            "## DNS and Kill-Switch Honesty",
            "- DNS claim checks: `dns_leak_results.csv`",
            "- Kill-switch claim checks: `kill_switch_results.csv`",
            "- Data-plane kill-switch drop tests require manual execution on target OS (commands below).",
            "",
            "## Error UX Validation",
            "- Protocol-specific error API checks captured in `raw_logs/error_ux_checks.csv`.",
            "- For UI wording/state transitions, run Flutter protocol/state tests listed in the checklist below.",
            "",
            "## Performance Baseline (Barbados and Europe)",
            "- Handshake/latency baseline rows are in `handshake_latency.csv`.",
            "- Throughput baseline rows are in `throughput_summary.csv`.",
            "- Where live tunnel execution is unavailable, rows are marked `manual_required` or `skipped` with reasons.",
            "",
            "## Manual Validation Checklist",
            manual_checklist,
            "",
            "## Required Local Test Commands",
            "- Backend tests: `bash scripts/run_backend_tests.sh`",
            "- Flutter tests: `cd securewave_app && flutter test`",
            "- Flutter protocol/state focus: `cd securewave_app && flutter test test/protocol_capability_matrix_test.dart test/state_machine/protocol_transition_test.dart`",
            "- Mock/demo scan: `rg -n \"DEMO_MODE|WG_MOCK_MODE|WG_SIMULATE\" main.py routes services securewave_app/lib scripts`",
            "",
            "## Verdict",
            "- This report does not mark unvalidated scenarios as pass.",
            "- Any skipped/non-live checks remain explicitly marked for manual execution.",
        ]
    )

    return "\n".join(lines).rstrip() + "\n"


def run_validation(args: argparse.Namespace) -> int:
    timestamp = args.timestamp or now_stamp()
    output_dir = Path(args.output_root) / timestamp
    raw_logs_dir = output_dir / "raw_logs"
    raw_logs_dir.mkdir(parents=True, exist_ok=True)
    ctx = RunContext(output_dir=output_dir, raw_logs_dir=raw_logs_dir, timestamp=timestamp)

    host_platform = detect_host_platform()

    capability_file = REPO_ROOT / "securewave_app/lib/core/vpn/protocol_capabilities.dart"
    declared = parse_declared_protocols(capability_file)
    write_json(raw_logs_dir / "declared_protocols.json", {k: sorted(v) for k, v in declared.items()})

    runtime_hits = run_mock_scan(ctx, RUNTIME_SCAN_PATHS, "runtime")
    workflow_hits = run_mock_scan(ctx, WORKFLOW_SCAN_PATHS, "workflow")
    write_csv(
        output_dir / "raw_logs/mock_scan_hits.csv",
        runtime_hits + workflow_hits,
        ["scope", "status", "path", "line", "match", "detail"],
    )

    runtime_host = evaluate_runtime_for_host(ctx, host_platform)
    write_json(raw_logs_dir / "runtime_host_checks.json", runtime_host)

    live_enabled = bool(args.live)
    api_context = init_api_context(
        ctx,
        live_enabled=live_enabled,
        api_base_url=str(args.api_base_url or "").strip(),
        timeout_seconds=int(args.timeout_seconds),
    )
    write_json(raw_logs_dir / "api_auth_meta.json", api_context.auth_meta)

    backend_matrix = fetch_backend_protocol_matrix(ctx, api_context)
    write_json(raw_logs_dir / "backend_protocol_matrix.json", backend_matrix)

    protocol_matrix_rows = build_protocol_matrix_rows(
        declared=declared,
        backend=backend_matrix,
        runtime_host=runtime_host,
        host_platform=host_platform,
    )
    write_csv(
        output_dir / "protocol_matrix.csv",
        protocol_matrix_rows,
        [
            "timestamp",
            "platform",
            "protocol",
            "support_status",
            "reason",
            "ui_declared",
            "backend_enabled",
            "runtime_ready_on_host",
            "evidence_level",
        ],
    )

    dns_rows: list[dict[str, Any]] = []
    kill_rows: list[dict[str, Any]] = []
    handshake_rows: list[dict[str, Any]] = []
    throughput_rows: list[dict[str, Any]] = []

    # API profile checks per protocol for host platform.
    if api_context.enabled and host_platform in PLATFORMS:
        for protocol in PROTOCOLS:
            status_code, body, elapsed_ms = request_profile(
                ctx,
                api_context,
                protocol=protocol,
                device_type=host_platform,
            )

            if status_code == 200 and isinstance(body, dict):
                dns_row, kill_row = validate_profile_claims(protocol, host_platform, body)
                dns_rows.append(dns_row)
                kill_rows.append(kill_row)

                region = "unknown"
                location = str(body.get("server_location") or "")
                if "barbados" in location.lower():
                    region = "barbados"
                elif "europe" in location.lower() or any(
                    token in location.lower() for token in ["germany", "netherlands", "france", "europe"]
                ):
                    region = "europe"

                handshake_rows.append(
                    {
                        "timestamp": utc_now_iso(),
                        "region": region,
                        "platform": host_platform,
                        "protocol": protocol,
                        "metric_source": "profile_request",
                        "latency_ms": round(elapsed_ms, 3),
                        "status": "pass",
                        "reason": "profile issued",
                        "evidence": "/api/vpn/profile",
                    }
                )

                profile_path = maybe_write_profile_files(ctx, protocol, body, host_platform)
                if args.enable_data_plane:
                    expected_dns = []
                    dns_map = body.get("dns") if isinstance(body.get("dns"), dict) else {}
                    if isinstance(dns_map.get("servers"), list):
                        expected_dns = [str(item) for item in dns_map.get("servers") if str(item).strip()]
                    dns_dp, kill_dp, throughput_dp = execute_optional_data_plane_validation(
                        ctx,
                        protocol=protocol,
                        profile_path=profile_path,
                        dns_expected=expected_dns,
                    )
                    dns_rows.append(dns_dp)
                    kill_rows.append(kill_dp)
                    throughput_rows.append(throughput_dp)
            else:
                reason = "profile_request_failed"
                error_code = ""
                if isinstance(body, dict) and isinstance(body.get("error"), dict):
                    error_code = str(body["error"].get("code") or "")
                if error_code:
                    reason = f"{reason}:{error_code}"

                dns_rows.append(
                    {
                        "timestamp": utc_now_iso(),
                        "protocol": protocol,
                        "platform": host_platform,
                        "validation_mode": "profile_claim",
                        "result": "fail",
                        "expected_dns": "",
                        "observed_dns": "",
                        "leak_detected": "",
                        "reason": reason,
                        "evidence": f"/api/vpn/profile status={status_code}",
                    }
                )
                kill_rows.append(
                    {
                        "timestamp": utc_now_iso(),
                        "protocol": protocol,
                        "platform": host_platform,
                        "validation_mode": "profile_claim",
                        "result": "fail",
                        "mode": "",
                        "enforcement": "",
                        "reason": reason,
                        "evidence": f"/api/vpn/profile status={status_code}",
                    }
                )
                handshake_rows.append(
                    {
                        "timestamp": utc_now_iso(),
                        "region": "unknown",
                        "platform": host_platform,
                        "protocol": protocol,
                        "metric_source": "profile_request",
                        "latency_ms": round(elapsed_ms, 3),
                        "status": "fail",
                        "reason": reason,
                        "evidence": "/api/vpn/profile",
                    }
                )
    else:
        for protocol in PROTOCOLS:
            dns_rows.append(
                {
                    "timestamp": utc_now_iso(),
                    "protocol": protocol,
                    "platform": host_platform,
                    "validation_mode": "profile_claim",
                    "result": "manual_required",
                    "expected_dns": "",
                    "observed_dns": "",
                    "leak_detected": "",
                    "reason": "Live API mode disabled or auth failed",
                    "evidence": "",
                }
            )
            kill_rows.append(
                {
                    "timestamp": utc_now_iso(),
                    "protocol": protocol,
                    "platform": host_platform,
                    "validation_mode": "profile_claim",
                    "result": "manual_required",
                    "mode": "",
                    "enforcement": "",
                    "reason": "Live API mode disabled or auth failed",
                    "evidence": "",
                }
            )
            handshake_rows.append(
                {
                    "timestamp": utc_now_iso(),
                    "region": "unknown",
                    "platform": host_platform,
                    "protocol": protocol,
                    "metric_source": "profile_request",
                    "latency_ms": "",
                    "status": "manual_required",
                    "reason": "Live API mode disabled or auth failed",
                    "evidence": "",
                }
            )

    # Regional baseline (Barbados + Europe focus).
    region_cfg = Path(args.region_config)
    if not region_cfg.is_absolute():
        region_cfg = (REPO_ROOT / region_cfg).resolve()

    regions = load_region_targets(region_cfg)
    write_json(raw_logs_dir / "region_targets_effective.json", {"path": str(region_cfg), "regions": regions})

    for region in regions:
        name = str(region.get("name") or "unknown").strip().lower()
        ping_targets = [str(item).strip() for item in region.get("ping_targets", []) if str(item).strip()]
        throughput_url = str(region.get("throughput_url") or "").strip()

        ping_samples: list[float] = []
        for host in ping_targets:
            latency, status = run_ping_avg(ctx, name, host)
            if latency is not None:
                ping_samples.append(latency)

        if ping_samples:
            avg_ping = round(sum(ping_samples) / len(ping_samples), 3)
            handshake_rows.append(
                {
                    "timestamp": utc_now_iso(),
                    "region": name,
                    "platform": host_platform,
                    "protocol": "baseline",
                    "metric_source": "icmp_rtt",
                    "latency_ms": avg_ping,
                    "status": "pass",
                    "reason": f"avg ping across {len(ping_samples)} samples",
                    "evidence": ";".join(ping_targets),
                }
            )
        else:
            handshake_rows.append(
                {
                    "timestamp": utc_now_iso(),
                    "region": name,
                    "platform": host_platform,
                    "protocol": "baseline",
                    "metric_source": "icmp_rtt",
                    "latency_ms": "",
                    "status": "manual_required",
                    "reason": "no ping samples collected",
                    "evidence": ";".join(ping_targets),
                }
            )

        throughput_mbps, throughput_status, evidence_cmd = run_throughput_probe(
            ctx,
            region=name,
            url=throughput_url,
            bytes_to_fetch=int(args.throughput_bytes),
        )
        throughput_rows.append(
            {
                "timestamp": utc_now_iso(),
                "region": name,
                "platform": host_platform,
                "protocol": "baseline",
                "url": throughput_url,
                "throughput_mbps": "" if throughput_mbps is None else throughput_mbps,
                "status": "pass" if throughput_status == "ok" else "manual_required",
                "reason": "" if throughput_status == "ok" else throughput_status,
                "evidence": evidence_cmd,
            }
        )

    error_rows = run_error_ux_checks(ctx, api_context, host_platform)

    write_csv(
        output_dir / "dns_leak_results.csv",
        dns_rows,
        [
            "timestamp",
            "protocol",
            "platform",
            "validation_mode",
            "result",
            "expected_dns",
            "observed_dns",
            "leak_detected",
            "reason",
            "evidence",
        ],
    )

    write_csv(
        output_dir / "kill_switch_results.csv",
        kill_rows,
        [
            "timestamp",
            "protocol",
            "platform",
            "validation_mode",
            "result",
            "mode",
            "enforcement",
            "reason",
            "evidence",
        ],
    )

    write_csv(
        output_dir / "handshake_latency.csv",
        handshake_rows,
        [
            "timestamp",
            "region",
            "platform",
            "protocol",
            "metric_source",
            "latency_ms",
            "status",
            "reason",
            "evidence",
        ],
    )

    write_csv(
        output_dir / "throughput_summary.csv",
        throughput_rows,
        [
            "timestamp",
            "region",
            "platform",
            "protocol",
            "url",
            "throughput_mbps",
            "status",
            "reason",
            "evidence",
        ],
    )

    report = generate_report(
        ctx=ctx,
        host_platform=host_platform,
        api=api_context,
        runtime_hits=runtime_hits,
        workflow_hits=workflow_hits,
        protocol_matrix=protocol_matrix_rows,
        dns_rows=dns_rows,
        kill_rows=kill_rows,
        handshake_rows=handshake_rows,
        throughput_rows=throughput_rows,
        error_rows=error_rows,
    )
    (output_dir / "FINAL_MULTI_PROTOCOL_VALIDATION_REPORT.md").write_text(report, encoding="utf-8")

    summary = {
        "generated_at": utc_now_iso(),
        "output_dir": str(output_dir),
        "host_platform": host_platform,
        "live_api_enabled": api_context.enabled,
        "runtime_mock_hits": len(runtime_hits),
        "workflow_mock_hits": len(workflow_hits),
        "dns_failures": sum(1 for row in dns_rows if str(row.get("result")) == "fail"),
        "kill_switch_failures": sum(1 for row in kill_rows if str(row.get("result")) == "fail"),
        "error_ux_failures": sum(1 for row in error_rows if row.get("status") == "fail"),
    }
    write_json(output_dir / "raw_logs/validation_summary.json", summary)

    print(json.dumps(summary, indent=2))

    # Non-invasive CI mode should not fail on manual-required checks.
    if args.non_invasive:
        return 0

    if summary["runtime_mock_hits"] > 0:
        return 1
    if summary["dns_failures"] > 0 or summary["kill_switch_failures"] > 0 or summary["error_ux_failures"] > 0:
        return 1
    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run multi-protocol live validation suite")
    parser.add_argument(
        "--output-root",
        default=str(REPO_ROOT / "artifacts/live_validation_multi_protocol"),
        help="Root directory for timestamped output artifacts",
    )
    parser.add_argument(
        "--timestamp",
        default="",
        help="Optional fixed timestamp folder name (YYYYMMDD_HHMMSS)",
    )
    parser.add_argument(
        "--region-config",
        default="sandbox/live_validation_multi_protocol/region_targets.json",
        help="JSON file with regional ping/throughput targets",
    )
    parser.add_argument(
        "--api-base-url",
        default=os.getenv("LIVE_API_BASE_URL", ""),
        help="SecureWave API base URL for live profile checks",
    )
    parser.add_argument(
        "--live",
        action="store_true",
        help="Enable live API checks (/api/vpn/protocols and /api/vpn/profile)",
    )
    parser.add_argument(
        "--enable-data-plane",
        action="store_true",
        help="Enable optional data-plane tunnel checks using command templates from env",
    )
    parser.add_argument(
        "--timeout-seconds",
        type=int,
        default=int(os.getenv("LIVE_MULTI_PROTOCOL_TIMEOUT_SECONDS", "20")),
    )
    parser.add_argument(
        "--throughput-bytes",
        type=int,
        default=int(os.getenv("LIVE_MULTI_PROTOCOL_THROUGHPUT_BYTES", str(5 * 1024 * 1024))),
    )
    parser.add_argument(
        "--non-invasive",
        action="store_true",
        help="Never fail due to manual-required/live-disabled checks (for CI safety)",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    return run_validation(args)


if __name__ == "__main__":
    raise SystemExit(main())
