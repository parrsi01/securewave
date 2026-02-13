#!/usr/bin/env python3
"""Live end-to-end validation against a real SecureWave backend and WireGuard tunnel."""

from __future__ import annotations

import argparse
import json
import os
import stat
import sys
import tempfile
import time
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from sandbox.live_validation.common import (
    build_interface_name,
    ensure_dir,
    evaluate_dns_leak,
    fetch_public_ip,
    fetch_vpn_profile,
    parse_latest_handshake_epoch,
    parse_nameservers,
    parse_wireguard_config,
    read_text,
    redact,
    register_or_login_user,
    run_command,
    utc_now_iso,
    write_csv,
    write_json,
)


def _detect_platform(value: str) -> str:
    lower = value.lower().strip()
    if lower != "auto":
        return lower
    if os.name == "nt":
        return "windows"
    if os.getenv("ANDROID_ROOT"):
        return "android"
    return "linux"


def _parse_expected_dns(raw: str) -> list[str]:
    return [item.strip() for item in raw.split(",") if item.strip()]


def _command_from_template(template: str, *, config_path: Path, interface: str) -> str:
    return template.format(config_path=str(config_path), interface=interface)


def _platform_commands(platform: str, *, config_path: Path, interface: str) -> tuple[list[str] | str, list[str] | str, list[str] | str]:
    if platform == "linux":
        return (
            ["wg-quick", "up", str(config_path)],
            ["wg-quick", "down", str(config_path)],
            ["wg", "show", interface, "latest-handshakes"],
        )

    if platform == "windows":
        connect_tmpl = os.getenv("LIVE_WG_WINDOWS_CONNECT_CMD", 'wireguard.exe /installtunnelservice "{config_path}"')
        disconnect_tmpl = os.getenv("LIVE_WG_WINDOWS_DISCONNECT_CMD", 'wireguard.exe /uninstalltunnelservice "{interface}"')
        handshake_tmpl = os.getenv("LIVE_WG_WINDOWS_HANDSHAKE_CMD", 'wg.exe show "{interface}" latest-handshakes')
        return (
            _command_from_template(connect_tmpl, config_path=config_path, interface=interface),
            _command_from_template(disconnect_tmpl, config_path=config_path, interface=interface),
            _command_from_template(handshake_tmpl, config_path=config_path, interface=interface),
        )

    # Android requires operator-provided commands (typically via adb shell).
    connect_tmpl = os.getenv("LIVE_ANDROID_CONNECT_CMD", "")
    disconnect_tmpl = os.getenv("LIVE_ANDROID_DISCONNECT_CMD", "")
    handshake_tmpl = os.getenv("LIVE_ANDROID_HANDSHAKE_CMD", "")
    return (
        _command_from_template(connect_tmpl, config_path=config_path, interface=interface),
        _command_from_template(disconnect_tmpl, config_path=config_path, interface=interface),
        _command_from_template(handshake_tmpl, config_path=config_path, interface=interface),
    )


def _run_platform_command(command: list[str] | str, *, timeout_seconds: int = 30) -> tuple[bool, dict[str, Any]]:
    use_shell = isinstance(command, str)
    if isinstance(command, str) and not command.strip():
        return False, {
            "status": "failed",
            "detail": "missing command template",
            "command": "",
            "stdout": "",
            "stderr": "",
            "duration_ms": 0.0,
        }
    result = run_command(command, timeout_seconds=timeout_seconds, shell=use_shell)
    payload = {
        "status": "ok" if result.returncode == 0 else "failed",
        "detail": f"exit_code={result.returncode}",
        "command": result.command,
        "stdout": result.stdout[:1600],
        "stderr": result.stderr[:1600],
        "duration_ms": result.duration_ms,
    }
    return result.returncode == 0, payload


def _observed_dns(platform: str) -> list[str]:
    if platform == "linux":
        return parse_nameservers(read_text("/etc/resolv.conf"))

    if platform == "windows":
        cmd = os.getenv(
            "LIVE_WINDOWS_DNS_CMD",
            "powershell -NoProfile -Command \"Get-DnsClientServerAddress -AddressFamily IPv4 | Select-Object -ExpandProperty ServerAddresses\"",
        )
        result = run_command(cmd, timeout_seconds=20, shell=True)
        values = [line.strip() for line in result.stdout.splitlines() if line.strip()]
        return values

    dns_cmd = os.getenv("LIVE_ANDROID_DNS_CMD", "adb shell getprop net.dns1")
    result = run_command(dns_cmd, timeout_seconds=20, shell=True)
    values = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    return values


def _http_probe(platform: str, interface: str, url: str) -> tuple[bool, dict[str, Any]]:
    if platform == "linux":
        curl = run_command(
            [
                "curl",
                "--interface",
                interface,
                "--max-time",
                "10",
                "-sS",
                "-o",
                "/dev/null",
                "-w",
                "%{http_code}",
                url,
            ],
            timeout_seconds=15,
        )
        status_code = curl.stdout.strip()[-3:] if curl.stdout else ""
        ok = curl.returncode == 0 and status_code.startswith("2")
        return ok, {
            "status": "ok" if ok else "failed",
            "detail": f"http_status={status_code or 'unknown'}",
            "command": curl.command,
            "duration_ms": curl.duration_ms,
            "stderr": curl.stderr[:400],
        }

    # Windows/Android fallback uses plain HTTPS probe from current network namespace.
    sink = "NUL" if platform == "windows" else "/dev/null"
    curl = run_command(["curl", "--max-time", "10", "-sS", "-o", sink, "-w", "%{http_code}", url], timeout_seconds=15)
    status_code = curl.stdout.strip()[-3:] if curl.stdout else ""
    ok = curl.returncode == 0 and status_code.startswith("2")
    return ok, {
        "status": "ok" if ok else "failed",
        "detail": f"http_status={status_code or 'unknown'}",
        "command": curl.command,
        "duration_ms": curl.duration_ms,
        "stderr": curl.stderr[:400],
    }


def _write_secure_config(path: Path, config_text: str) -> None:
    path.write_text(config_text.strip() + "\n", encoding="utf-8")
    try:
        path.chmod(stat.S_IRUSR | stat.S_IWUSR)
    except Exception:
        pass


def run_live_validation(
    *,
    output_dir: Path,
    api_base_url: str,
    users: int,
    platform: str,
    strict: bool,
    timeout_seconds: int,
    handshake_timeout_seconds: int,
    interface_prefix: str,
    device_type: str,
    expected_dns: list[str],
    http_probe_url: str,
    public_ip_endpoint: str,
    server_id: str | None,
) -> dict:
    out_dir = ensure_dir(output_dir)
    started_at = utc_now_iso()
    effective_platform = _detect_platform(platform)

    password = os.getenv("LIVE_VALIDATION_PASSWORD", "LiveValidate#123")
    username_prefix = os.getenv("LIVE_VALIDATION_EMAIL_PREFIX", "live.validation")

    before_ip = fetch_public_ip(endpoint=public_ip_endpoint)
    handshake_rows: list[dict[str, Any]] = []
    dns_rows: list[dict[str, Any]] = []

    user_results: list[dict[str, Any]] = []
    failures = 0
    strict_failures = 0

    with tempfile.TemporaryDirectory(prefix="securewave_live_validation_") as temp_dir:
        temp_path = Path(temp_dir)

        for index in range(1, max(1, users) + 1):
            email = f"{username_prefix}+{int(time.time())}{index}@example.com"
            ok_auth, access_token, auth_meta = register_or_login_user(
                api_base_url=api_base_url,
                email=email,
                password=password,
                timeout_seconds=timeout_seconds,
            )
            if not ok_auth or not access_token:
                failures += 1
                strict_failures += 1
                user_results.append(
                    {
                        "user": email,
                        "status": "failed",
                        "stage": "auth",
                        "detail": auth_meta,
                    }
                )
                continue

            profile = fetch_vpn_profile(
                api_base_url=api_base_url,
                access_token=access_token,
                device_name=f"live-validation-{index}",
                device_type=device_type,
                timeout_seconds=timeout_seconds,
                server_id=server_id,
            )
            profile_body = profile.body if isinstance(profile.body, dict) else {}
            if profile.status_code != 200:
                failures += 1
                strict_failures += 1
                user_results.append(
                    {
                        "user": email,
                        "status": "failed",
                        "stage": "profile",
                        "detail": {
                            "status_code": profile.status_code,
                            "response": profile_body,
                        },
                    }
                )
                continue

            config_text = str(profile_body.get("wireguard_config", "")).strip()
            sections = parse_wireguard_config(config_text)
            peer_public_key = sections.get("peer", {}).get("publickey")
            endpoint = sections.get("peer", {}).get("endpoint")
            if not config_text or "interface" not in sections or "peer" not in sections:
                failures += 1
                strict_failures += 1
                user_results.append(
                    {
                        "user": email,
                        "status": "failed",
                        "stage": "profile_parse",
                        "detail": "wireguard config missing sections",
                    }
                )
                continue

            interface = build_interface_name(interface_prefix, index)
            config_path = temp_path / f"{interface}.conf"
            _write_secure_config(config_path, config_text)

            connect_cmd, disconnect_cmd, handshake_cmd = _platform_commands(
                effective_platform,
                config_path=config_path,
                interface=interface,
            )

            session: dict[str, Any] = {
                "user": email,
                "token": redact(access_token),
                "status": "pass",
                "platform": effective_platform,
                "interface": interface,
                "server_endpoint": endpoint,
                "profile_status_code": profile.status_code,
                "profile_latency_ms": profile.duration_ms,
                "auth": auth_meta,
            }

            connect_ok, connect_meta = _run_platform_command(connect_cmd, timeout_seconds=timeout_seconds)
            session["connect"] = connect_meta
            if not connect_ok:
                failures += 1
                session["status"] = "failed"
                if strict:
                    strict_failures += 1
                user_results.append(session)
                _run_platform_command(disconnect_cmd, timeout_seconds=timeout_seconds)
                continue

            handshake_success = False
            handshake_ms = 0.0
            handshake_epoch = 0
            poll_started = time.monotonic()
            while (time.monotonic() - poll_started) <= handshake_timeout_seconds:
                hs_ok, hs_meta = _run_platform_command(handshake_cmd, timeout_seconds=max(5, timeout_seconds // 2))
                if hs_ok:
                    epoch = parse_latest_handshake_epoch(hs_meta.get("stdout", ""), peer_public_key)
                    if epoch > 0:
                        handshake_success = True
                        handshake_epoch = epoch
                        handshake_ms = round((time.monotonic() - poll_started) * 1000, 3)
                        break
                time.sleep(1.0)

            after_ip = fetch_public_ip(endpoint=public_ip_endpoint)
            ip_changed = bool(before_ip and after_ip and before_ip != after_ip)

            observed_dns = _observed_dns(effective_platform)
            dns_ok, leaked_dns = evaluate_dns_leak(observed_dns, set(expected_dns), allow_private=True)
            dns_status = "ok" if dns_ok else "failed"
            if not dns_ok:
                failures += 1
                if strict:
                    strict_failures += 1

            http_ok, http_meta = _http_probe(effective_platform, interface, http_probe_url)
            if not http_ok:
                failures += 1
                if strict:
                    strict_failures += 1

            _run_platform_command(disconnect_cmd, timeout_seconds=timeout_seconds)

            if not handshake_success:
                failures += 1
                if strict:
                    strict_failures += 1

            session.update(
                {
                    "status": "pass" if handshake_success and dns_ok and http_ok else "failed",
                    "handshake_success": handshake_success,
                    "handshake_epoch": handshake_epoch,
                    "handshake_ms": handshake_ms,
                    "external_ip_before": before_ip,
                    "external_ip_after": after_ip,
                    "external_ip_changed": ip_changed,
                    "dns": {
                        "expected": expected_dns,
                        "observed": observed_dns,
                        "status": dns_status,
                        "leaked": leaked_dns,
                    },
                    "http_probe": http_meta,
                }
            )

            user_results.append(session)
            handshake_rows.append(
                {
                    "timestamp": utc_now_iso(),
                    "user": email,
                    "platform": effective_platform,
                    "interface": interface,
                    "server_endpoint": endpoint or "",
                    "handshake_ms": handshake_ms,
                    "success": handshake_success,
                    "external_ip_before": before_ip or "",
                    "external_ip_after": after_ip or "",
                    "external_ip_changed": ip_changed,
                }
            )
            dns_rows.append(
                {
                    "timestamp": utc_now_iso(),
                    "user": email,
                    "platform": effective_platform,
                    "interface": interface,
                    "expected_dns": ";".join(expected_dns),
                    "observed_dns": ";".join(observed_dns),
                    "status": dns_status,
                    "leaked": ";".join(leaked_dns),
                }
            )

    write_csv(
        out_dir / "handshake_stats.csv",
        handshake_rows,
        [
            "timestamp",
            "user",
            "platform",
            "interface",
            "server_endpoint",
            "handshake_ms",
            "success",
            "external_ip_before",
            "external_ip_after",
            "external_ip_changed",
        ],
    )

    write_csv(
        out_dir / "dns_checks.csv",
        dns_rows,
        [
            "timestamp",
            "user",
            "platform",
            "interface",
            "expected_dns",
            "observed_dns",
            "status",
            "leaked",
        ],
    )

    payload = {
        "harness": "live_e2e_validate",
        "generated_at": utc_now_iso(),
        "started_at": started_at,
        "finished_at": utc_now_iso(),
        "overall_status": "pass" if strict_failures == 0 else "fail",
        "strict": strict,
        "platform": effective_platform,
        "users": users,
        "failures": failures,
        "strict_failures": strict_failures,
        "api_base_url": api_base_url,
        "http_probe_url": http_probe_url,
        "public_ip_endpoint": public_ip_endpoint,
        "results": user_results,
    }
    write_json(out_dir / "live_e2e_result.json", payload)
    return payload


def main() -> int:
    parser = argparse.ArgumentParser(description="Run real E2E connectivity validation")
    parser.add_argument("--output-dir", default="artifacts/live_validation")
    parser.add_argument("--api-base-url", default=os.getenv("LIVE_API_BASE_URL", ""))
    parser.add_argument("--users", type=int, default=int(os.getenv("LIVE_VALIDATION_USERS", "3")))
    parser.add_argument("--platform", default=os.getenv("LIVE_VALIDATION_PLATFORM", "auto"))
    parser.add_argument("--strict", action="store_true")
    parser.add_argument("--timeout-seconds", type=int, default=int(os.getenv("LIVE_VALIDATION_TIMEOUT_SECONDS", "25")))
    parser.add_argument(
        "--handshake-timeout-seconds",
        type=int,
        default=int(os.getenv("LIVE_HANDSHAKE_TIMEOUT_SECONDS", "20")),
    )
    parser.add_argument("--interface-prefix", default=os.getenv("LIVE_VALIDATION_INTERFACE_PREFIX", "swlive"))
    parser.add_argument("--device-type", default=os.getenv("LIVE_VALIDATION_DEVICE_TYPE", "linux"))
    parser.add_argument(
        "--expected-dns",
        default=os.getenv("LIVE_ALLOWED_DNS", "94.140.14.14,94.140.15.15,1.1.1.1"),
    )
    parser.add_argument("--http-probe-url", default=os.getenv("LIVE_HTTP_PROBE_URL", "https://api.ipify.org"))
    parser.add_argument("--public-ip-endpoint", default=os.getenv("LIVE_PUBLIC_IP_ENDPOINT", "https://api.ipify.org"))
    parser.add_argument("--server-id", default=os.getenv("LIVE_VALIDATION_SERVER_ID", ""))
    args = parser.parse_args()

    if not args.api_base_url.strip():
        raise SystemExit("LIVE_API_BASE_URL is required for live validation")

    payload = run_live_validation(
        output_dir=Path(args.output_dir),
        api_base_url=args.api_base_url.strip(),
        users=max(1, args.users),
        platform=args.platform,
        strict=args.strict,
        timeout_seconds=max(5, args.timeout_seconds),
        handshake_timeout_seconds=max(5, args.handshake_timeout_seconds),
        interface_prefix=args.interface_prefix.strip() or "swlive",
        device_type=args.device_type,
        expected_dns=_parse_expected_dns(args.expected_dns),
        http_probe_url=args.http_probe_url,
        public_ip_endpoint=args.public_ip_endpoint,
        server_id=args.server_id.strip() or None,
    )

    print(json.dumps(payload, indent=2))
    return 0 if payload.get("overall_status") == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
