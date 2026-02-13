"""Common helpers for leak validation scripts."""

from __future__ import annotations

import os
import shutil
import subprocess  # nosec B404 - controlled operator command execution
from pathlib import Path


def run_command(command: list[str], timeout_seconds: int = 5) -> tuple[int, str, str]:
    try:
        proc = subprocess.run(command, capture_output=True, text=True, timeout=timeout_seconds, check=False)  # nosec B603
    except (subprocess.SubprocessError, OSError, TimeoutError) as exc:
        return 1, "", str(exc)
    return proc.returncode, proc.stdout, proc.stderr


def interface_exists(interface: str) -> bool:
    ip_cmd = shutil.which("ip")
    if not ip_cmd:
        return False
    rc, _, _ = run_command([ip_cmd, "link", "show", interface])
    return rc == 0


def default_routes(ipv6: bool = False) -> list[str]:
    ip_cmd = shutil.which("ip")
    if not ip_cmd:
        return []
    cmd = [ip_cmd, "-6", "route", "show", "default"] if ipv6 else [ip_cmd, "route", "show", "default"]
    rc, out, _ = run_command(cmd)
    if rc != 0:
        return []
    return [line.strip() for line in out.splitlines() if line.strip()]


def route_interfaces(routes: list[str]) -> list[str]:
    interfaces: list[str] = []
    for line in routes:
        parts = line.split()
        if "dev" in parts:
            idx = parts.index("dev")
            if idx + 1 < len(parts):
                interfaces.append(parts[idx + 1])
    return interfaces


def bool_env(name: str, default: bool) -> bool:
    raw = os.getenv(name)
    if raw is None:
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on"}


def read_text(path: str | Path) -> str:
    target = Path(path)
    if not target.exists():
        return ""
    return target.read_text(encoding="utf-8", errors="ignore")
