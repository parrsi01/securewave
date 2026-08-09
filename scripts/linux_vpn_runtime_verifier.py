#!/usr/bin/env python3
"""Read-only checks for the SecureWave Linux WireGuard beta runtime.

The verifier never starts or stops a tunnel. Run it before and after an app
attempt to inspect the helper service, WireGuard runtime, and owned cleanup
state. External exit-IP/data-plane checks require explicit opt-in and a local
baseline file.
"""

from __future__ import annotations

import argparse
import ipaddress
import json
import platform
import shutil
import socket
import stat
import subprocess  # nosec B404
import urllib.parse
import urllib.request
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
REQUIRED_TOOLS = (
    "wg-quick",
    "wg",
    "ip",
    "iptables",
    "nft",
    "resolvectl",
)
WIREGUARD_INTERFACE = "sw-wg"
WIREGUARD_TABLE = "51820"
ADBLOCK_CHAIN = "SECUREWAVE_ADBLOCK"
EXPECTED_SECUREWAVE_HELPER_CONTRACT = 13


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
    index = 0
    while index < len(value):
        if value[index] != "\\" or index + 1 >= len(value):
            out.append(value[index])
            index += 1
            continue
        index += 1
        out.append({"n": "\n", "r": "\r"}.get(value[index], value[index]))
        index += 1
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
    return [
        Check(
            name=f"tool:{tool}",
            ok=shutil.which(tool) is not None,
            detail=shutil.which(tool) or f"{tool} not found in PATH",
        )
        for tool in REQUIRED_TOOLS
    ]


def check_no_polkit_source() -> list[Check]:
    old_rule = "50-securewave-wg.rules"
    source_files = (
        REPO_ROOT / "securewave_app/scripts/build_deb.sh",
        REPO_ROOT / "securewave_app/scripts/install_linux_helper.sh",
        REPO_ROOT / "securewave_app/linux/CMakeLists.txt",
    )
    references = [
        path.read_text(encoding="utf-8")
        for path in source_files
        if path.exists()
    ]
    packaged = any(old_rule in source for source in references)
    runner_source = RUNNER_PATH.read_text(encoding="utf-8") if RUNNER_PATH.exists() else ""
    return [
        Check(
            "privilege:no_packaged_polkit_rule",
            not packaged,
            "no polkit rule is installed by the Linux beta"
            if not packaged
            else "a legacy polkit rule is still referenced by the package",
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
    return Check(
        "privilege:securewave_helper_contract",
        installed >= EXPECTED_SECUREWAVE_HELPER_CONTRACT,
        f"installed contract {installed}; required {EXPECTED_SECUREWAVE_HELPER_CONTRACT}",
    )


def _path_exists(path: Path) -> tuple[bool, str | None]:
    try:
        return path.exists(), None
    except PermissionError as exc:
        return False, str(exc)


def check_helper_service_install() -> list[Check]:
    allowlist_exists, allowlist_error = _path_exists(HELPER_ALLOWLIST_PATH)
    checks = [
        Check(
            "privilege:helper_script_installed",
            HELPER_PATH.is_file() and HELPER_PATH.stat().st_mode & 0o111 != 0,
            str(HELPER_PATH) if HELPER_PATH.exists() else f"{HELPER_PATH} not installed",
        ),
        Check(
            "privilege:helperd_installed",
            HELPERD_PATH.is_file() and HELPERD_PATH.stat().st_mode & 0o111 != 0,
            str(HELPERD_PATH) if HELPERD_PATH.exists() else f"{HELPERD_PATH} not installed",
        ),
        Check(
            "privilege:helper_service_unit",
            HELPER_SERVICE_PATH.is_file(),
            str(HELPER_SERVICE_PATH)
            if HELPER_SERVICE_PATH.exists()
            else f"{HELPER_SERVICE_PATH} not installed",
        ),
        Check(
            "privilege:helper_tmpfiles_config",
            HELPER_TMPFILES_PATH.is_file(),
            str(HELPER_TMPFILES_PATH)
            if HELPER_TMPFILES_PATH.exists()
            else f"{HELPER_TMPFILES_PATH} not installed",
        ),
        Check(
            "privilege:helper_allowed_users",
            allowlist_exists,
            str(HELPER_ALLOWLIST_PATH)
            if allowlist_exists
            else allowlist_error or f"{HELPER_ALLOWLIST_PATH} not installed",
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
        return [Check("privilege:helper_socket", False, f"{HELPER_SOCKET_PATH} not found")]
    try:
        mode = HELPER_SOCKET_PATH.stat().st_mode
    except OSError as exc:
        return [Check("privilege:helper_socket", False, f"socket inspection failed: {type(exc).__name__}")]
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
    try:
        response = helper_request({"op": "probe", "protocol": "wireguard"})
        service_seen = response.get("service_version") == "1"
        ok = response.get("ok") == "true"
        acceptable_tool_missing = response.get("code") == "tool_missing"
        checks.append(
            Check(
                "privilege:helper_probe:wireguard",
                service_seen and (ok or acceptable_tool_missing),
                response.get("message", str(response)),
            )
        )
    except OSError as exc:
        checks.append(
            Check(
                "privilege:helper_probe:wireguard",
                False,
                f"helper socket request failed: {exc}",
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
        "runner:wireguard_protocol_gate": 'g_strcmp0(protocol, "wireguard") == 0',
        "runner:securewave_helper_contract": "kSecureWaveHelperContractVersion = 13",
        "runner:no_connect_time_pkexec": "pkexec",
    }
    checks = []
    for name, token in expectations.items():
        if name == "runner:no_connect_time_pkexec":
            ok = token not in source
            detail = "no pkexec call path" if ok else "pkexec remains in runner"
        else:
            ok = token in source
            detail = "present" if ok else f"missing {token!r}"
        checks.append(Check(name, ok, detail))
    return checks


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
        build_path.is_file(),
        f"{build_path} (bundle: {bundle_dir})"
        if build_path.exists()
        else missing_detail,
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


def _wireguard_status_request() -> dict[str, str]:
    return helper_request(
        {
            "op": "wireguard.status",
            "config_path": str(Path.home() / ".config/securewave/sw-wg.conf"),
        }
    )


def check_active_runtime(protocol: str) -> list[Check]:
    if protocol != "wireguard":
        return [Check("runtime:protocol", False, "the Linux beta supports WireGuard only")]
    try:
        response = _wireguard_status_request()
    except OSError as exc:
        return [Check("runtime:wireguard:status", False, f"helper status request failed: {exc}")]

    service_ok = response.get("ok") == "true"
    connected = service_ok and response.get("status") == "connected"
    route_ok = (
        response.get("route_via_sw_wg") == "true"
        and response.get("ipv4_route_via_sw_wg") == "true"
        and response.get("ipv6_route_via_sw_wg") == "true"
    )
    safety_ok = (
        response.get("policy_rules_present") == "true"
        and response.get("policy_routes_present") == "true"
        and response.get("firewall_inspection_ok") == "true"
        and response.get("ipv4_kill_switch_present") == "true"
        and response.get("ipv6_block_present") == "true"
        and response.get("ipv6_mode") == "block"
        and response.get("handshake_inspection_ok") == "true"
        and response.get("handshake_present") == "true"
        and response.get("endpoint_inspection_ok") == "true"
        and response.get("endpoint_bypass_present") == "true"
    )
    dns = _run(["resolvectl", "dns", WIREGUARD_INTERFACE])
    domains = _run(["resolvectl", "domain", WIREGUARD_INTERFACE])
    dns_ok = (
        dns.returncode == 0
        and bool(dns.stdout.partition(":")[2].strip())
        and domains.returncode == 0
        and "~." in domains.stdout.split()
    )
    counters_ok = response.get("counters_available") == "true"
    return [
        Check(
            "runtime:wireguard:status",
            connected,
            "helper reports connected with authenticated WireGuard evidence"
            if connected
            else response.get("message", "helper did not report connected"),
        ),
        Check(
            "runtime:wireguard:route",
            service_ok and route_ok,
            "full-tunnel IPv4/IPv6 route evidence is present"
            if service_ok and route_ok
            else "full-tunnel route evidence is absent",
        ),
        Check(
            "runtime:wireguard:safety",
            service_ok and safety_ok,
            "WireGuard policy, firewall, handshake, and endpoint evidence is present"
            if service_ok and safety_ok
            else "WireGuard safety evidence is absent",
        ),
        Check(
            "runtime:wireguard:dns",
            dns_ok,
            "WireGuard DNS evidence is present; addresses redacted"
            if dns_ok
            else "WireGuard DNS evidence is absent",
        ),
        Check(
            "runtime:wireguard:counters",
            service_ok and counters_ok,
            "runtime byte counters are available; values redacted"
            if service_ok and counters_ok
            else "runtime byte counters are unavailable",
        ),
    ]


def check_external_data_plane(
    baseline_path: Path | None,
    exit_ip_url: str,
    data_plane_url: str,
) -> list[Check]:
    if baseline_path is None or not baseline_path.is_file():
        return [
            Check(
                "runtime:exit_ip_change",
                False,
                "baseline public-IP file is required for authorized external probes",
            ),
            Check(
                "runtime:data_plane",
                False,
                "data-plane probe not attempted without a baseline public-IP file",
            ),
        ]
    try:
        baseline = ipaddress.ip_address(baseline_path.read_text(encoding="utf-8").strip())
        for url in (exit_ip_url, data_plane_url):
            if urllib.parse.urlparse(url).scheme != "https":
                raise ValueError("external probe URLs must use HTTPS")
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        with opener.open(exit_ip_url, timeout=10) as response:  # nosec B310
            observed = ipaddress.ip_address(response.read(128).decode("ascii").strip())
        with opener.open(data_plane_url, timeout=10) as response:  # nosec B310
            response.read(1)
            data_plane_ok = 200 <= response.status < 400
    except (OSError, ValueError, UnicodeError) as exc:
        return [
            Check("runtime:exit_ip_change", False, f"external probe failed: {type(exc).__name__}"),
            Check("runtime:data_plane", False, "external data-plane probe failed"),
        ]
    return [
        Check(
            "runtime:exit_ip_change",
            observed != baseline,
            "public exit IP changed; addresses redacted"
            if observed != baseline
            else "public exit IP did not change; address redacted",
        ),
        Check(
            "runtime:data_plane",
            data_plane_ok,
            "HTTPS data-plane probe succeeded; response body redacted"
            if data_plane_ok
            else "HTTPS data-plane probe failed",
        ),
    ]


def _wireguard_policy_residue() -> tuple[bool, str]:
    results = {
        family: _run(["ip", family, "-N", "rule", "show"])
        for family in ("-4", "-6")
    }
    if any(result.returncode != 0 for result in results.values()):
        return False, "IPv4/IPv6 policy-rule inspection failed"
    residue = [
        line
        for result in results.values()
        for line in result.stdout.splitlines()
        if f"table {WIREGUARD_TABLE}" in line
        or f"lookup {WIREGUARD_TABLE}" in line
        or "suppress_prefixlength 0" in line
    ]
    return not residue, "no SecureWave WireGuard policy rules" if not residue else "WireGuard policy rules remain"


def _wireguard_table_residue() -> tuple[bool, str]:
    residue: list[str] = []
    for family in ("-4", "-6"):
        result = _run(["ip", family, "route", "show", "table", WIREGUARD_TABLE])
        if result.returncode != 0:
            if "FIB table does not exist" in result.stderr:
                continue
            return False, f"IPv{family[-1]} route-table inspection failed"
        residue.extend(result.stdout.splitlines())
    return not residue, "no SecureWave WireGuard table routes" if not residue else "WireGuard table routes remain"


def check_residue() -> list[Check]:
    checks: list[Check] = []
    try:
        status = _wireguard_status_request()
    except OSError:
        status = {"ok": "false", "message": "helper socket request failed"}
    try:
        contract = int(status.get("contract", ""))
    except (TypeError, ValueError):
        contract = 0
    firewall_clean = (
        contract >= EXPECTED_SECUREWAVE_HELPER_CONTRACT
        and status.get("ok") == "true"
        and status.get("status") == "disconnected"
        and status.get("firewall_inspection_ok") == "true"
        and status.get("nft_table_present") == "false"
        and status.get("iptables_rule_present") == "false"
        and status.get("ip6tables_rule_present") == "false"
        and status.get("ipv4_kill_switch_present") == "false"
        and status.get("ipv6_block_present") == "false"
        and status.get("firewall_residue_present") == "false"
    )
    checks.append(
        Check(
            "residue:wireguard_firewall",
            firewall_clean,
            "privileged helper confirms no owned WireGuard firewall residue"
            if firewall_clean
            else "privileged WireGuard firewall inspection failed or residue remains",
        )
    )

    links = _run(["ip", "-o", "link", "show"])
    interfaces = []
    if links.returncode == 0:
        interfaces = [
            line.split(":", 2)[1].strip().split("@", 1)[0]
            for line in links.stdout.splitlines()
            if len(line.split(":", 2)) >= 2
        ]
    interface_clean = links.returncode == 0 and WIREGUARD_INTERFACE not in interfaces
    checks.append(
        Check(
            "residue:wireguard_interface",
            interface_clean,
            "sw-wg interface absent"
            if interface_clean
            else "sw-wg interface is still present or interface inspection failed",
        )
    )

    routes = _run(["ip", "route", "show"])
    main_route_residue = routes.returncode != 0 or any(
        WIREGUARD_INTERFACE in line for line in routes.stdout.splitlines()
    )
    checks.append(
        Check(
            "residue:tunnel_routes",
            not main_route_residue,
            "no SecureWave interface route in the main table"
            if not main_route_residue
            else "SecureWave interface route remains or route inspection failed",
        )
    )

    policy_clean, policy_detail = _wireguard_policy_residue()
    checks.append(Check("residue:wireguard_policy_rules", policy_clean, policy_detail))
    table_clean, table_detail = _wireguard_table_residue()
    checks.append(Check("residue:wireguard_policy_routes", table_clean, table_detail))

    try:
        adblock = helper_request({"op": "firewall.adblock_status"})
    except OSError:
        adblock = {"ok": "false", "message": "helper socket request failed"}
    adblock_clean = adblock.get("ok") == "true" and adblock.get("present") == "false"
    checks.append(
        Check(
            "residue:adblock_chain",
            adblock_clean,
            f"{ADBLOCK_CHAIN} chain absent"
            if adblock_clean
            else f"{ADBLOCK_CHAIN} state could not be inspected safely",
        )
    )

    dns = _run(["resolvectl", "dns", WIREGUARD_INTERFACE])
    domains = _run(["resolvectl", "domain", WIREGUARD_INTERFACE])
    dns_clean = (
        (dns.returncode != 0 or not dns.stdout.partition(":")[2].strip())
        and (domains.returncode != 0 or "~." not in domains.stdout.split())
    )
    checks.append(
        Check(
            "residue:wireguard_dns",
            dns_clean,
            "no DNS state remains on sw-wg"
            if dns_clean
            else "DNS state remains on sw-wg",
        )
    )
    return checks


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json", action="store_true", help="print machine-readable JSON")
    parser.add_argument(
        "--allow-active-tunnel",
        action="store_true",
        help="deprecated compatibility flag; use --active-protocol for fail-closed checks",
    )
    parser.add_argument(
        "--active-protocol",
        choices=("wireguard",),
        help="validate an intentionally active WireGuard tunnel",
    )
    parser.add_argument(
        "--external-probes",
        action="store_true",
        help="perform one authorized HTTPS exit-IP check and one data-plane request",
    )
    parser.add_argument(
        "--baseline-exit-ip-file",
        type=Path,
        help="private local file containing the pre-tunnel public IP; its value is never printed",
    )
    parser.add_argument(
        "--exit-ip-url",
        default="https://api.ipify.org",
        help="HTTPS endpoint used only with --external-probes",
    )
    parser.add_argument(
        "--data-plane-url",
        default="https://example.com/",
        help="HTTPS endpoint used only with --external-probes",
    )
    parser.add_argument(
        "--skip-build-checks",
        action="store_true",
        help="omit local Flutter bundle checks on a package-install target",
    )
    args = parser.parse_args()

    checks = [
        *check_tools(),
        *check_no_polkit_source(),
        check_installed_helper_contract(),
        *check_helper_service_install(),
        *check_helper_socket(),
        *check_helper_ipc(),
        *check_runner_contract(),
    ]
    if not args.skip_build_checks:
        checks.extend([check_build_artifact(), *check_build_helper_payload()])
    if args.active_protocol:
        checks.extend(check_active_runtime(args.active_protocol))
        if args.external_probes:
            checks.extend(
                check_external_data_plane(
                    args.baseline_exit_ip_file,
                    args.exit_ip_url,
                    args.data_plane_url,
                )
            )
        else:
            checks.extend(
                [
                    Check(
                        "runtime:exit_ip_change",
                        False,
                        "not checked; pass --external-probes with explicit authorization",
                    ),
                    Check(
                        "runtime:data_plane",
                        False,
                        "not checked; pass --external-probes with explicit authorization",
                    ),
                ]
            )
    elif args.allow_active_tunnel:
        checks.append(
            Check(
                "runtime:active_protocol_required",
                False,
                "--allow-active-tunnel requires --active-protocol",
            )
        )
    else:
        checks.extend(check_residue())

    payload = {"ok": all(check.ok for check in checks), "checks": [check.as_dict() for check in checks]}
    if args.json:
        print(json.dumps(payload, indent=2, sort_keys=True))
    else:
        for check in checks:
            print(f"{'OK' if check.ok else 'FAIL'} {check.name}: {check.detail}")
    return 0 if payload["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
