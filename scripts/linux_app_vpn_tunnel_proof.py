#!/usr/bin/env python3
"""Live ARM64 Linux acceptance proof for the real WireGuard beta path."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import socket
import subprocess
import sys
import time
from pathlib import Path
from urllib.request import urlopen

from linux_vpn_runtime_verifier import _helper_request, verify


ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "securewave_app"
DEFAULT_API = "https://api.securewaveapp.com/api"


def _positive(value: str) -> int:
    parsed = int(value)
    if parsed < 1:
        raise argparse.ArgumentTypeError("must be positive")
    return parsed


def _read_auth_file(path: Path) -> dict[str, str]:
    if not path.is_file() or (path.stat().st_mode & 0o777) != 0o600:
        raise ValueError("credential file must be a regular mode-0600 file")
    values: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            values[key.strip()] = value.strip()
    return values


def _egress_ip() -> str | None:
    try:
        with urlopen("https://api.ipify.org", timeout=10) as response:  # nosec B310 - explicit live acceptance endpoint
            value = response.read(64).decode().strip()
        return value if value else None
    except Exception:
        return None


def _json_line(line: str) -> dict[str, object] | None:
    try:
        value = json.loads(line)
    except json.JSONDecodeError:
        return None
    return value if isinstance(value, dict) else None


def _cleanup() -> bool:
    try:
        response = _helper_request({
            "op": "wireguard.cleanup",
            "config_path": str(Path.home() / ".config" / "securewave" / "sw-wg.conf"),
        })
        return response.get("ok") == "true"
    except (OSError, socket.timeout, UnicodeError):
        return False


def _build_probe(api_base: str) -> tuple[bool, Path | None, str]:
    if shutil.which("flutter") is None:
        return False, None, "flutter is unavailable"
    result = subprocess.run(
        [
            "flutter",
            "build",
            "linux",
            "--release",
            "--target",
            "lib/runtime_vpn_probe.dart",
            f"--dart-define=SECUREWAVE_API_BASE_URL={api_base}",
            "--dart-define=SECUREWAVE_DEMO_MODE=false",
        ],
        cwd=APP,
        capture_output=True,
        text=True,
        timeout=300,
        check=False,
    )
    if result.returncode != 0:
        return False, None, "Flutter release probe build failed"
    machine = os.uname().machine.lower()
    if machine not in {"aarch64", "arm64"}:
        return False, None, "Beta 1 live proof requires an ARM64 Linux host"
    binary = APP / "build" / "linux" / "arm64" / "release" / "bundle" / "securewave_app"
    return binary.is_file() and os.access(binary, os.X_OK), binary, ""


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--api-base", default=os.getenv("SECUREWAVE_API_BASE_URL", DEFAULT_API))
    parser.add_argument("--allow-production", action="store_true")
    parser.add_argument("--auth-file", required=True)
    parser.add_argument("--hold-seconds", type=_positive, default=20)
    parser.add_argument("--evidence-timeout", type=_positive, default=120)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()

    payload: dict[str, object] = {
        "ok": False,
        "architecture": os.uname().machine,
        "api_base_configured": bool(args.api_base),
        "build_ok": False,
        "connect_event": False,
        "disconnect_event": False,
        "egress_changed": False,
        "cleanup_ok": False,
        "error": None,
    }
    api_base = args.api_base.rstrip("/")
    if not api_base.startswith(("https://", "http://")):
        payload["error"] = "API base must be an HTTP(S) URL"
    elif not args.allow_production and not api_base.startswith(("http://127.0.0.1", "http://localhost")):
        payload["error"] = "--allow-production is required for a non-local live target"
    else:
        try:
            credentials = _read_auth_file(Path(args.auth_file).expanduser())
            email = credentials.get("SECUREWAVE_RUNTIME_PROBE_EMAIL", "")
            password = credentials.get("SECUREWAVE_RUNTIME_PROBE_PASSWORD", "")
            if not email or not password:
                raise ValueError("credential file is missing the live probe fields")
            baseline = verify()
            if not baseline["ok"]:
                payload["error"] = "helper baseline is not clean"
            else:
                before_ip = _egress_ip()
                build_ok, binary, build_error = _build_probe(api_base)
                payload["build_ok"] = build_ok
                if not build_ok or binary is None:
                    payload["error"] = build_error or "probe binary is missing"
                else:
                    environment = os.environ.copy()
                    environment.update(
                        {
                            "SECUREWAVE_API_BASE_URL": api_base,
                            "SECUREWAVE_DEMO_MODE": "false",
                            "SECUREWAVE_RUNTIME_PROBE_EMAIL": email,
                            "SECUREWAVE_RUNTIME_PROBE_PASSWORD": password,
                            "SECUREWAVE_RUNTIME_PROBE_HOLD_SECONDS": str(args.hold_seconds),
                        }
                    )
                    process = subprocess.Popen(
                        [str(binary)],
                        cwd=APP,
                        env=environment,
                        stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE,
                        text=True,
                    )
                    events: list[dict[str, object]] = []
                    connected_ip: str | None = None
                    deadline = time.monotonic() + args.evidence_timeout
                    while process.poll() is None and time.monotonic() < deadline:
                        if process.stdout is None:
                            break
                        line = process.stdout.readline()
                        if not line:
                            time.sleep(0.05)
                            continue
                        event = _json_line(line)
                        if event is None:
                            continue
                        events.append(event)
                        if event.get("event") == "connect_result":
                            payload["connect_event"] = event.get("status") == "connected"
                            connected_ip = _egress_ip()
                        if event.get("event") == "disconnect_result":
                            payload["disconnect_event"] = event.get("status") == "disconnected"
                    if process.poll() is None:
                        process.kill()
                        process.wait(timeout=10)
                    else:
                        process.wait(timeout=10)
                    payload["egress_changed"] = bool(before_ip and connected_ip and before_ip != connected_ip)
                    if process.returncode != 0 and payload["error"] is None:
                        payload["error"] = "runtime probe exited unsuccessfully"
                    if not payload["connect_event"] and payload["error"] is None:
                        payload["error"] = "no connected event was observed"
                    if not payload["disconnect_event"] and payload["error"] is None:
                        payload["error"] = "no clean disconnected event was observed"
                    if not payload["egress_changed"] and payload["error"] is None:
                        payload["error"] = "public egress did not change through the tunnel"
        except (OSError, ValueError, subprocess.TimeoutExpired) as exc:
            payload["error"] = str(exc)
        finally:
            payload["cleanup_ok"] = _cleanup()

    payload["final_runtime"] = verify()
    payload["ok"] = (
        payload["error"] is None
        and payload["build_ok"] is True
        and payload["connect_event"] is True
        and payload["disconnect_event"] is True
        and payload["egress_changed"] is True
        and payload["cleanup_ok"] is True
        and payload["final_runtime"].get("ok") is True
    )
    print(json.dumps(payload, indent=2, sort_keys=True) if args.json else ("OK" if payload["ok"] else "BLOCKED"))
    return 0 if payload["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
