#!/usr/bin/env python3
"""Verify local Linux VPN runtime prerequisites and residue state.

This is intentionally read-only. It does not start tunnels. Use it before and
after app-driven VPN attempts to prove the host has the expected promptless
SecureWave helper service and no stale SecureWave tunnel/process residue.
"""

from __future__ import annotations

import argparse
import json
import os
import platform
import shutil
import socket
import stat
import subprocess  # nosec B404
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


REPO_ROOT = Path(__file__).resolve().parents[1]
RUNNER_PATH = REPO_ROOT / "securewave_app/linux/runner/my_application.cc"


def _flutter_linux_arch(machine: str | None = None) -> str:
    host_arch = machine or platform.machine()
    if host_arch == "x86_64":
        return "x64"
    if host_arch in ("aarch64", "arm64"):
        return "arm64"
    return host_arch or "x64"


BUILD_LINUX_ARCH = _flutter_linux_arch()
BUILD_LINUX_DIR = REPO_ROOT / "securewave_app/build/linux"
BUILD_RELEASE_BUNDLE_DIR = BUILD_LINUX_DIR / BUILD_LINUX_ARCH / "release/bundle"
BUILD_DEBUG_BUNDLE_DIR = BUILD_LINUX_DIR / BUILD_LINUX_ARCH / "debug/bundle"
HELPER_PATH = Path("/usr/local/libexec/securewave-wg-quick")
HELPERD_PATH = Path("/usr/local/libexec/securewave-helperd")
HELPER_CONTRACT_PATH = Path("/usr/local/libexec/securewave-wg-quick.contract")
HELPER_SERVICE_PATH = Path("/etc/systemd/system/securewave-helper.service")
HELPER_TMPFILES_PATH = Path("/usr/lib/tmpfiles.d/securewave-helper.conf")
HELPER_ALLOWLIST_PATH = Path("/etc/securewave/helper-users")
HELPER_SOCKET_PATH = Path("/run/securewave/helper.sock")
REQUIRED_TOOLS = ("wg-quick", "wg", "openvpn", "nmcli", "swanctl", "ipsec", "ip", "setfacl")
WIREGUARD_INTERFACE = "sw-wg"
IKEV2_CONNECTION = "SecureWave-IKEv2"
ADBLOCK_CHAIN = "SECUREWAVE_ADBLOCK"
MIN_ADBLOCK_HELPER_CONTRACT = 8
EXPECTED_SECUREWAVE_HELPER_CONTRACT = 9


@dataclass(frozen=True)
class Check:
    name: str
    ok: bool
    detail: str

    def as_dict(self) -> dict[str, object]:
        return {"name": self.name, "ok": self.ok, "detail": self.detail}


def _run(argv: Iterable[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(  # nosec B603
        list(argv),
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )


def _escape(value: str) -> str:
    return value.replace("\\", "\\\\").replace("\n", "\\n").replace("\r", "\\r")


def _unescape(value: str) -> str:
    out: list[str] = []
    i = 0
    while i < len(value):
        if value[i] != "\\" or i + 1 >= len(value):
            out.append(value[i])
            i += 1
            continue
        i += 1
        if value[i] == "n":
            out.append("\n")
        elif value[i] == "r":
            out.append("\r")
        else:
            out.append(value[i])
        i += 1
    return "".join(out)


def helper_request(fields: dict[str, str], timeout: float = 5.0) -> dict[str, str]:
    request = {"version": "1", **fields}
    body = "".join(f"{key}={_escape(value)}\n" for key, value in request.items())
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
        client.settimeout(timeout)
        client.connect(str(HELPER_SOCKET_PATH))
        client.sendall(body.encode("utf-8"))
        client.shutdown(socket.SHUT_WR)
        chunks: list[bytes] = []
        while True:
            chunk = client.recv(65536)
            if not chunk:
                break
            chunks.append(chunk)
    response: dict[str, str] = {}
    for raw_line in b"".join(chunks).decode("utf-8", errors="replace").splitlines():
        if "=" not in raw_line:
            continue
        key, value = raw_line.split("=", 1)
        response[key] = _unescape(value)
    return response


def check_tools() -> list[Check]:
    checks: list[Check] = []
    for tool in REQUIRED_TOOLS:
        path = shutil.which(tool)
        checks.append(
            Check(
                name=f"tool:{tool}",
                ok=path is not None,
                detail=path or f"{tool} not found in PATH",
            )
        )
    return checks


def check_no_polkit_source() -> list[Check]:
    old_rule = REPO_ROOT / "securewave_app/packaging/linux/50-securewave-wg.rules"
    runner_source = RUNNER_PATH.read_text(encoding="utf-8") if RUNNER_PATH.exists() else ""
    return [
        Check(
            "privilege:no_packaged_polkit_rule",
            not old_rule.exists(),
            "old polkit rule is not packaged" if not old_rule.exists() else f"remove {old_rule}",
        ),
        Check(
            "runner:no_connect_time_pkexec",
            "pkexec" not in runner_source and "--disable-internal-agent" not in runner_source,
            "runner has no pkexec call path"
            if "pkexec" not in runner_source and "--disable-internal-agent" not in runner_source
            else "runner still references pkexec",
        ),
    ]


def check_installed_helper_contract() -> Check:
    if not HELPER_CONTRACT_PATH.exists():
        return Check(
            "privilege:securewave_helper_contract",
            False,
            f"{HELPER_CONTRACT_PATH} not installed",
        )
    raw = HELPER_CONTRACT_PATH.read_text(encoding="utf-8").strip()
    try:
        installed = int(raw)
    except ValueError:
        return Check(
            "privilege:securewave_helper_contract",
            False,
            f"invalid helper contract {raw!r}",
        )
    ok = installed >= EXPECTED_SECUREWAVE_HELPER_CONTRACT
    return Check(
        "privilege:securewave_helper_contract",
        ok,
        f"installed contract {installed}; required {EXPECTED_SECUREWAVE_HELPER_CONTRACT}",
    )


def check_adblock_contract() -> Check:
    if not HELPER_CONTRACT_PATH.exists():
        return Check(
            "privilege:adblock_contract",
            False,
            f"{HELPER_CONTRACT_PATH} not installed",
        )
    raw = HELPER_CONTRACT_PATH.read_text(encoding="utf-8").strip()
    try:
        installed = int(raw)
    except ValueError:
        return Check(
            "privilege:adblock_contract",
            False,
            f"invalid helper contract {raw!r}",
        )
    ok = installed >= MIN_ADBLOCK_HELPER_CONTRACT
    return Check(
        "privilege:adblock_contract",
        ok,
        f"installed contract {installed}; required {MIN_ADBLOCK_HELPER_CONTRACT} for adblock",
    )


def path_exists(path: Path) -> tuple[bool, str | None]:
    try:
        return path.exists(), None
    except PermissionError as exc:
        return False, str(exc)


def check_helper_service_install() -> list[Check]:
    allowlist_exists, allowlist_error = path_exists(HELPER_ALLOWLIST_PATH)
    checks = [
        Check(
            "privilege:helper_script_installed",
            HELPER_PATH.exists() and os.access(HELPER_PATH, os.X_OK),
            str(HELPER_PATH) if HELPER_PATH.exists() else f"{HELPER_PATH} not installed",
        ),
        Check(
            "privilege:helperd_installed",
            HELPERD_PATH.exists() and os.access(HELPERD_PATH, os.X_OK),
            str(HELPERD_PATH) if HELPERD_PATH.exists() else f"{HELPERD_PATH} not installed",
        ),
        Check(
            "privilege:helper_service_unit",
            HELPER_SERVICE_PATH.exists(),
            str(HELPER_SERVICE_PATH) if HELPER_SERVICE_PATH.exists() else f"{HELPER_SERVICE_PATH} not installed",
        ),
        Check(
            "privilege:helper_tmpfiles_config",
            HELPER_TMPFILES_PATH.exists(),
            str(HELPER_TMPFILES_PATH) if HELPER_TMPFILES_PATH.exists() else f"{HELPER_TMPFILES_PATH} not installed",
        ),
        Check(
            "privilege:helper_allowed_users",
            allowlist_exists,
            str(HELPER_ALLOWLIST_PATH) if allowlist_exists else allowlist_error or f"{HELPER_ALLOWLIST_PATH} not installed",
        ),
    ]
    systemctl = shutil.which("systemctl")
    if systemctl and Path("/run/systemd/system").exists():
        active = _run([systemctl, "is-active", "securewave-helper.service"])
        checks.append(
            Check(
                "privilege:helper_service_active",
                active.returncode == 0 and active.stdout.strip() == "active",
                active.stdout.strip() or active.stderr.strip() or "service inactive",
            )
        )
    else:
        checks.append(
            Check(
                "privilege:helper_service_active",
                False,
                "systemd is not available on this host",
            )
        )
    return checks


def check_helper_socket() -> list[Check]:
    if not HELPER_SOCKET_PATH.exists():
        return [
            Check(
                "privilege:helper_socket",
                False,
                f"{HELPER_SOCKET_PATH} not found",
            )
        ]
    mode = HELPER_SOCKET_PATH.stat().st_mode
    permissions = stat.S_IMODE(mode)
    return [
        Check(
            "privilege:helper_socket",
            stat.S_ISSOCK(mode),
            f"{HELPER_SOCKET_PATH} mode {oct(permissions)}",
        ),
        Check(
            "privilege:helper_socket_permissions",
            permissions in (0o660, 0o600),
            f"socket permissions {oct(permissions)}",
        ),
    ]


def check_helper_ipc() -> list[Check]:
    checks: list[Check] = []
    for protocol in ("wireguard", "openvpn", "ikev2"):
        try:
            response = helper_request({"op": "probe", "protocol": protocol})
        except OSError as exc:
            checks.append(
                Check(
                    f"privilege:helper_probe:{protocol}",
                    False,
                    f"helper socket request failed: {exc}",
                )
            )
            continue
        service_seen = response.get("service_version") == "1"
        ok = response.get("ok") == "true"
        acceptable_tool_missing = response.get("code") == "tool_missing"
        checks.append(
            Check(
                f"privilege:helper_probe:{protocol}",
                service_seen and (ok or acceptable_tool_missing),
                response.get("message", response),
            )
        )

    try:
        invalid = helper_request({"op": "shell", "command": "id"})
        checks.append(
            Check(
                "privilege:helper_invalid_op_fails_closed",
                invalid.get("ok") == "false" and invalid.get("code") == "invalid_operation",
                invalid.get("message", str(invalid)),
            )
        )
    except OSError as exc:
        checks.append(
            Check(
                "privilege:helper_invalid_op_fails_closed",
                False,
                f"helper socket request failed: {exc}",
            )
        )
    return checks


def check_runner_contract() -> list[Check]:
    if not RUNNER_PATH.exists():
        return [Check("runner:source", False, f"{RUNNER_PATH} not found")]
    source = RUNNER_PATH.read_text(encoding="utf-8")
    expectations = {
        "runner:method_channel": 'kChannelName = "securewave/vpn"',
        "runner:helper_socket": 'kHelperSocketPath = "/run/securewave/helper.sock"',
        "runner:helper_request": "helper_request(",
        "runner:wireguard_connect_op": '"wireguard.up"',
        "runner:wireguard_disconnect_op": '"wireguard.down"',
        "runner:openvpn_connect_op": '"openvpn.start"',
        "runner:openvpn_disconnect_op": '"openvpn.stop"',
        "runner:ikev2_connect_op": '"ikev2.start"',
        "runner:ikev2_disconnect_op": '"ikev2.stop"',
        "runner:securewave_helper_contract": "kSecureWaveHelperContractVersion = 9",
        "runner:no_implicit_mock": "securewave/vpn",
    }
    return [
        Check(name, token in source, "present" if token in source else f"missing {token!r}")
        for name, token in expectations.items()
    ]


def resolve_build_bundle_dir() -> Path:
    if BUILD_RELEASE_BUNDLE_DIR.exists():
        return BUILD_RELEASE_BUNDLE_DIR
    return BUILD_DEBUG_BUNDLE_DIR


def check_build_artifact() -> Check:
    bundle_dir = resolve_build_bundle_dir()
    build_path = bundle_dir / "securewave_app"
    missing_detail = (
        f"missing {build_path} (bundle: {bundle_dir}); "
        "run: cd securewave_app && flutter build linux --release"
    )
    return Check(
        "build:linux_bundle",
        build_path.exists(),
        f"{build_path} (bundle: {bundle_dir})" if build_path.exists() else missing_detail,
    )


def check_build_helper_payload() -> list[Check]:
    bundle_dir = resolve_build_bundle_dir()
    expected = {
        "build:helper_payload": bundle_dir / "packaging/linux/securewave-wg-quick",
        "build:helperd_payload": bundle_dir / "packaging/linux/securewave-helperd",
        "build:helper_service_payload": bundle_dir / "packaging/linux/securewave-helper.service",
        "build:helper_tmpfiles_payload": bundle_dir / "packaging/linux/securewave-helper.tmpfiles",
        "build:helper_contract_payload": bundle_dir / "packaging/linux/securewave-wg-quick.contract",
        "build:helper_installer_payload": bundle_dir / "scripts/install_linux_helper.sh",
    }
    return [
        Check(
            name,
            path.exists(),
            f"{path} (bundle: {bundle_dir})"
            if path.exists()
            else f"missing {path} (bundle: {bundle_dir})",
        )
        for name, path in expected.items()
    ]


def check_residue() -> list[Check]:
    checks: list[Check] = []

    link = _run(["ip", "link", "show", WIREGUARD_INTERFACE])
    checks.append(
        Check(
            "residue:wireguard_interface",
            link.returncode != 0,
            f"{WIREGUARD_INTERFACE} interface absent"
            if link.returncode != 0
            else f"{WIREGUARD_INTERFACE} interface is still present",
        )
    )

    tun0 = _run(["ip", "link", "show", "tun0"])
    checks.append(
        Check(
            "residue:tun0_interface",
            tun0.returncode != 0,
            "tun0 interface absent" if tun0.returncode != 0 else "tun0 interface is still present",
        )
    )

    routes = _run(["ip", "route", "show"])
    securewave_routes = [
        line
        for line in routes.stdout.splitlines()
        if (
            WIREGUARD_INTERFACE in line
            or "securewave" in line
            or "tun0" in line
            or line.startswith(("0.0.0.0/1 ", "128.0.0.0/1 "))
        )
    ]
    checks.append(
        Check(
            "residue:tunnel_routes",
            routes.returncode == 0 and not securewave_routes,
            "no SecureWave/tun split routes"
            if routes.returncode == 0 and not securewave_routes
            else "\n".join(securewave_routes) or routes.stderr.strip() or "ip route failed",
        )
    )

    rules = _run(["ip", "rule", "show"])
    securewave_rules = [
        line
        for line in rules.stdout.splitlines()
        if (
            "lookup 51820" in line
            or "table 51820" in line
            or "suppress_prefixlength 0" in line
        )
    ]
    checks.append(
        Check(
            "residue:wireguard_policy_rules",
            rules.returncode == 0 and not securewave_rules,
            "no SecureWave WireGuard policy rules"
            if rules.returncode == 0 and not securewave_rules
            else "\n".join(securewave_rules) or rules.stderr.strip() or "ip rule failed",
        )
    )

    table_route_details: list[str] = []
    table_route_ok = True
    for family in ("-4", "-6"):
        table_routes = _run(["ip", family, "route", "show", "table", "51820"])
        if table_routes.returncode != 0:
            if "FIB table does not exist" in table_routes.stderr:
                continue
            table_route_ok = False
            table_route_details.append(table_routes.stderr.strip() or f"ip {family} table 51820 failed")
            continue
        output = table_routes.stdout.strip()
        if output:
            table_route_ok = False
            table_route_details.append(output)
    checks.append(
        Check(
            "residue:wireguard_policy_routes",
            table_route_ok,
            "no SecureWave WireGuard table 51820 routes"
            if table_route_ok
            else "\n".join(table_route_details),
        )
    )

    adblock = _run(["iptables", "-S", ADBLOCK_CHAIN])
    checks.append(
        Check(
            "residue:adblock_chain",
            adblock.returncode != 0,
            f"{ADBLOCK_CHAIN} chain absent"
            if adblock.returncode != 0
            else adblock.stdout.strip() or adblock.stderr.strip() or f"{ADBLOCK_CHAIN} chain exists",
        )
    )

    procs = _run(["pgrep", "-x", "openvpn"])
    checks.append(
        Check(
            "residue:openvpn_process",
            procs.returncode != 0,
            "no SecureWave OpenVPN process"
            if procs.returncode != 0
            else procs.stdout.strip(),
        )
    )

    sas = _run(["swanctl", "--list-sas"])
    securewave_sas = [line for line in sas.stdout.splitlines() if "securewave" in line]
    checks.append(
        Check(
            "residue:ikev2_sa",
            not securewave_sas,
            "no SecureWave IKEv2 SA"
            if not securewave_sas
            else "\n".join(securewave_sas),
        )
    )

    active = _run(["nmcli", "-t", "-f", "NAME,TYPE", "connection", "show", "--active"])
    active_ikev2 = [
        line
        for line in active.stdout.splitlines()
        if line == f"{IKEV2_CONNECTION}:vpn"
    ]
    checks.append(
        Check(
            "residue:ikev2_nm_connection",
            active.returncode == 0 and not active_ikev2,
            f"no active {IKEV2_CONNECTION} NetworkManager VPN"
            if active.returncode == 0 and not active_ikev2
            else "\n".join(active_ikev2) or active.stderr.strip() or "nmcli active connection check failed",
        )
    )

    return checks


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json", action="store_true", help="print machine-readable JSON")
    parser.add_argument(
        "--allow-active-tunnel",
        action="store_true",
        help="skip residue checks when the caller is intentionally verifying an active tunnel",
    )
    args = parser.parse_args()

    checks = [
        *check_tools(),
        *check_no_polkit_source(),
        check_installed_helper_contract(),
        check_adblock_contract(),
        *check_helper_service_install(),
        *check_helper_socket(),
        *check_helper_ipc(),
        *check_runner_contract(),
        check_build_artifact(),
        *check_build_helper_payload(),
    ]
    if not args.allow_active_tunnel:
        checks.extend(check_residue())
    payload = {
        "ok": all(check.ok for check in checks),
        "checks": [check.as_dict() for check in checks],
    }
    if args.json:
        print(json.dumps(payload, indent=2, sort_keys=True))
    else:
        for check in checks:
            status = "OK" if check.ok else "FAIL"
            print(f"{status} {check.name}: {check.detail}")
    return 0 if payload["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
