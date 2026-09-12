#!/usr/bin/env python3
"""Smoke-test the installed SecureWave Linux app through the desktop session.

This intentionally checks only process startup and the accessibility surface.
It does not sign in, create accounts, change VPN state, or inject credentials.
"""

from __future__ import annotations

import argparse
import json
import os
import signal
import subprocess  # nosec B404 - executable is an explicit local argument
import sys
import time
from pathlib import Path


SYSTEM_CONTROL_NAMES = {"Minimize", "Maximize", "Close"}
INTERACTIVE_ROLES = {
    "check box",
    "combo box",
    "list",
    "list item",
    "page tab",
    "password text",
    "push button",
    "radio button",
    "text",
    "toggle button",
}


def _safe_child_environment() -> dict[str, str]:
    environment = dict(os.environ)
    for name in tuple(environment):
        upper_name = name.upper()
        if (
            "PASSWORD" in upper_name
            or "TOKEN" in upper_name
            or name in {"DEMO_EMAIL", "SECUREWAVE_RUNTIME_PROBE_EMAIL"}
        ):
            environment.pop(name, None)
    return environment


def _find_application(pyatspi: object) -> object | None:
    desktop = pyatspi.Registry.getDesktop(0)  # type: ignore[attr-defined]
    for item in desktop:
        name = (getattr(item, "name", None) or "").lower()
        if "securewave" in name:
            return item
    return None


def _interactive_control_count(node: object) -> tuple[int, int]:
    named_controls = 0
    actionable_controls = 0

    def walk(current: object, depth: int = 0) -> None:
        nonlocal named_controls, actionable_controls
        if depth > 8:
            return
        try:
            role = current.getRoleName()
            name = (current.name or "").strip()
            if role in INTERACTIVE_ROLES and name not in SYSTEM_CONTROL_NAMES:
                if name:
                    named_controls += 1
                try:
                    if current.queryAction().nActions:
                        actionable_controls += 1
                except Exception:  # noqa: BLE001 - accessibility providers vary.
                    pass
            for child in current:
                walk(child, depth + 1)
        except Exception:  # noqa: BLE001 - accessibility providers may disappear.
            pass

    walk(node)
    return named_controls, actionable_controls


def _terminate_process(process: subprocess.Popen[bytes]) -> None:
    if process.poll() is not None:
        return
    try:
        os.killpg(process.pid, signal.SIGTERM)
        process.wait(timeout=5)
    except (ProcessLookupError, subprocess.TimeoutExpired):
        if process.poll() is None:
            try:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait(timeout=5)
            except ProcessLookupError:
                pass


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--binary", default="/usr/bin/securewave-vpn", help="installed app launcher"
    )
    parser.add_argument(
        "--wait-seconds", type=float, default=8.0, help="startup observation window"
    )
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()

    result: dict[str, object] = {
        "binary": str(Path(args.binary)),
        "process_alive": False,
        "accessible_application": False,
        "window_count": 0,
        "named_interactive_controls": 0,
        "actionable_interactive_controls": 0,
        "warnings": [],
    }

    binary = Path(args.binary)
    if not binary.is_file() or not os.access(binary, os.X_OK):
        result["error"] = "installed app launcher is missing or not executable"
        return _emit(result, 2, args.json)
    if not os.environ.get("DISPLAY") and not os.environ.get("WAYLAND_DISPLAY"):
        result["error"] = "no active graphical session was advertised"
        return _emit(result, 2, args.json)

    try:
        import pyatspi  # type: ignore[import-not-found]
    except ImportError:
        result["error"] = "python3-pyatspi is not installed"
        return _emit(result, 2, args.json)

    process = subprocess.Popen(  # nosec B603 - explicit installed launcher
        [str(binary)],
        env=_safe_child_environment(),
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    try:
        deadline = time.monotonic() + max(args.wait_seconds, 0.5)
        application = None
        while time.monotonic() < deadline:
            if process.poll() is not None:
                break
            try:
                application = _find_application(pyatspi)
            except Exception:  # noqa: BLE001 - report the desktop probe result.
                application = None
            if application is not None:
                break
            time.sleep(0.25)

        result["process_alive"] = process.poll() is None
        if application is not None:
            result["accessible_application"] = True
            result["window_count"] = int(application.childCount)
            named, actionable = _interactive_control_count(application)
            result["named_interactive_controls"] = named
            result["actionable_interactive_controls"] = actionable

        if result["accessible_application"] and not result["actionable_interactive_controls"]:
            result["warnings"] = [
                "desktop accessibility exposed the application window but no actionable app controls"
            ]
        result["ok"] = bool(
            result["process_alive"]
            and result["accessible_application"]
            and result["actionable_interactive_controls"]
        )
        if not result["ok"] and "error" not in result:
            result["error"] = "installed app startup or accessibility smoke failed"
        return _emit(result, 0 if result["ok"] else 1, args.json)
    finally:
        _terminate_process(process)


def _emit(result: dict[str, object], code: int, as_json: bool) -> int:
    if as_json:
        print(json.dumps(result, sort_keys=True))
    else:
        status = "PASS" if code == 0 else "FAIL"
        print(f"{status} installed app smoke")
        if result.get("error"):
            print(result["error"])
    return code


if __name__ == "__main__":
    sys.exit(main())
