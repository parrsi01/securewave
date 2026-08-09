#!/usr/bin/env python3
"""Read-only checks for the installed SecureWave WireGuard helper."""

from __future__ import annotations

import argparse
import json
import os
import socket
import subprocess
from pathlib import Path


SOCKET_PATH = Path("/run/securewave/helper.sock")
CONTRACT_PATH = Path("/usr/local/libexec/securewave-wg-quick.contract")
HELPER_PATH = Path("/usr/local/libexec/securewave-helperd")
SCRIPT_PATH = Path("/usr/local/libexec/securewave-wg-quick")
INTERFACE = "sw-wg"
CONTRACT = 13


def _escape(value: str) -> str:
    return value.replace("\\", "\\\\").replace("\n", "\\n").replace("\r", "\\r")


def _unescape(value: str) -> str:
    output = ""
    index = 0
    while index < len(value):
        if value[index] != "\\" or index + 1 == len(value):
            output += value[index]
        else:
            index += 1
            output += {"n": "\n", "r": "\r"}.get(value[index], value[index])
        index += 1
    return output


def _fields(body: str) -> dict[str, str]:
    result: dict[str, str] = {}
    for line in body.splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            result[key] = _unescape(value)
    return result


def _helper_request(fields: dict[str, str], timeout: float = 10) -> dict[str, str]:
    request = {"version": "1", **fields}
    payload = "".join(f"{key}={_escape(value)}\n" for key, value in request.items())
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
        connection.settimeout(timeout)
        connection.connect(str(SOCKET_PATH))
        connection.sendall(payload.encode())
        connection.shutdown(socket.SHUT_WR)
        chunks: list[bytes] = []
        while True:
            chunk = connection.recv(4096)
            if not chunk:
                break
            chunks.append(chunk)
    return _fields(b"".join(chunks).decode(errors="replace"))


def _command(args: list[str]) -> tuple[bool, str]:
    try:
        result = subprocess.run(args, capture_output=True, text=True, timeout=5, check=False)
    except (OSError, subprocess.TimeoutExpired) as exc:
        return False, type(exc).__name__
    return result.returncode == 0, (result.stdout or result.stderr).strip()


def _check_path(path: Path, executable: bool = False) -> dict[str, object]:
    present = path.is_file() and (not executable or os.access(path, os.X_OK))
    return {"path": str(path), "present": present}


def verify(require_connected: bool = False) -> dict[str, object]:
    checks: list[dict[str, object]] = []
    contract = None
    try:
        contract = int(CONTRACT_PATH.read_text(encoding="utf-8").strip())
    except (OSError, ValueError):
        pass
    checks.append({"name": "contract", "ok": contract is not None and contract >= CONTRACT, "value": contract})
    checks.append({"name": "helper_binary", "ok": _check_path(HELPER_PATH, True)["present"]})
    checks.append({"name": "helper_script", "ok": _check_path(SCRIPT_PATH, True)["present"]})
    checks.append({"name": "socket", "ok": SOCKET_PATH.exists()})

    probe: dict[str, str] = {}
    status: dict[str, str] = {}
    try:
        probe = _helper_request({"op": "probe"})
        checks.append({"name": "probe", "ok": probe.get("ok") == "true" and probe.get("contract", "0").isdigit() and int(probe["contract"]) >= CONTRACT})
        status = _helper_request({"op": "wireguard.status"})
        checks.append({"name": "status", "ok": status.get("ok") == "true" and status.get("interface") == INTERFACE})
    except (OSError, socket.timeout, UnicodeError) as exc:
        checks.append({"name": "helper_request", "ok": False, "error": type(exc).__name__})

    if require_connected:
        checks.append({"name": "connected", "ok": status.get("status") == "connected"})

    interface_present, _ = _command(["ip", "link", "show", "dev", INTERFACE])
    if not require_connected:
        checks.append({"name": "disconnected_baseline", "ok": not interface_present})

    return {
        "ok": all(bool(check.get("ok")) for check in checks),
        "contract_required": CONTRACT,
        "probe": {key: value for key, value in probe.items() if key not in {"message", "stdout"}},
        "status": {key: value for key, value in status.items() if key not in {"message", "stdout"}},
        "checks": checks,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--require-connected", action="store_true")
    args = parser.parse_args()
    result = verify(require_connected=args.require_connected)
    if args.json:
        print(json.dumps(result, indent=2, sort_keys=True))
    else:
        print("OK" if result["ok"] else "BLOCKED")
        for check in result["checks"]:
            print(f"{'OK' if check.get('ok') else 'FAIL'} {check['name']}")
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
