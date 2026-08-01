#!/usr/bin/env python3
"""Fail-closed ARM64 Linux package and clean-device release gate.

This gate builds and verifies the package from the current clean candidate,
preflights an explicitly supplied clean ARM64 device, installs the package
through the normal administrator path, and reruns the repository verifier.
It deliberately does not launch the GUI, connect a tunnel, or publish a
website. Those actions require separate operator-controlled proof.
"""

from __future__ import annotations

import argparse
import hashlib
import re
import shlex
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Sequence


PACKAGE_NAME = "securewave-vpn"
PACKAGE_VERSION = "4.0.0+4"
PACKAGE_ARCHITECTURE = "arm64"
PACKAGE_FILENAME = f"{PACKAGE_NAME}_{PACKAGE_VERSION}_{PACKAGE_ARCHITECTURE}.deb"
EXPECTED_HELPER_CONTRACT = "13"

REQUIRED_PAYLOAD = (
    "usr/lib/securewave/securewave_app",
    "usr/share/securewave/packaging/linux/securewave-helperd",
    "usr/share/securewave/packaging/linux/securewave-wg-quick",
    "usr/share/securewave/packaging/linux/securewave-helper.service",
    "usr/share/securewave/packaging/linux/securewave-wg-quick.contract",
    "usr/share/securewave/release/source-sha",
    "usr/share/securewave/release/source-tree-state",
    "usr/share/securewave/release/helper-contract",
)

PLACEHOLDER_MARKERS = (
    "approved-",
    "approved_",
    "real-",
    "real_",
    "your-",
    "your_",
    "placeholder",
    "example.",
    "<",
    ">",
)


class GateBlocked(RuntimeError):
    """A safe, non-sensitive description of a failed gate."""


def run_checked(
    command: Sequence[str],
    *,
    label: str,
    cwd: Path | None = None,
    input_text: str | None = None,
    timeout: int = 120,
) -> str:
    """Run a command without exposing its output."""

    try:
        result = subprocess.run(
            list(command),
            cwd=str(cwd) if cwd is not None else None,
            input=input_text,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise GateBlocked(f"{label} unavailable or timed out") from exc

    if result.returncode != 0:
        raise GateBlocked(f"{label} failed")
    return result.stdout


def read_required(path: Path, *, label: str) -> str:
    try:
        value = path.read_text(encoding="utf-8").strip()
    except (OSError, UnicodeError) as exc:
        raise GateBlocked(f"{label} unavailable") from exc
    if not value:
        raise GateBlocked(f"{label} is empty")
    return value


def reject_placeholders(value: str, *, label: str) -> None:
    lowered = value.lower()
    if any(marker in lowered for marker in PLACEHOLDER_MARKERS):
        raise GateBlocked(f"{label} is a placeholder")
    if any(character.isspace() for character in value) or value.startswith("-"):
        raise GateBlocked(f"{label} is invalid")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--candidate-sha", required=True)
    parser.add_argument("--authorized-candidate", required=True)
    parser.add_argument("--device", required=True, help="approved user@host SSH target")
    parser.add_argument(
        "--remote-candidate-root",
        required=True,
        help="absolute path of the clean candidate checkout on the test device",
    )
    parser.add_argument("--runtime-authorized", action="store_true")
    parser.add_argument("--test-device-authorized", action="store_true")
    parser.add_argument("--install-authorized", action="store_true")
    parser.add_argument("--allowlist-change-authorized", action="store_true")
    return parser.parse_args()


def validate_args(args: argparse.Namespace) -> Path:
    if not re.fullmatch(r"[0-9a-f]{40}", args.candidate_sha):
        raise GateBlocked("candidate SHA is invalid")
    if args.authorized_candidate != args.candidate_sha:
        raise GateBlocked("authorized candidate does not match candidate SHA")
    for value, label in (
        (args.device, "device"),
        (args.remote_candidate_root, "remote candidate root"),
    ):
        reject_placeholders(value, label=label)
    if not args.runtime_authorized:
        raise GateBlocked("runtime authorization is required")
    if not args.test_device_authorized:
        raise GateBlocked("test-device authorization is required")
    if not args.install_authorized:
        raise GateBlocked("package-install authorization is required")
    if not args.allowlist_change_authorized:
        raise GateBlocked("helper allowlist authorization is required")

    remote_root = Path(args.remote_candidate_root)
    if not remote_root.is_absolute():
        raise GateBlocked("remote candidate root must be absolute")
    return remote_root


def local_candidate_checks(root: Path, candidate_sha: str) -> None:
    head = run_checked(
        ["git", "-C", str(root), "rev-parse", "HEAD"],
        label="candidate HEAD inspection",
    ).strip()
    if head != candidate_sha:
        raise GateBlocked("local candidate is not pinned to the requested SHA")

    status = run_checked(
        ["git", "-C", str(root), "status", "--porcelain", "--untracked-files=all"],
        label="candidate worktree inspection",
    )
    if status:
        raise GateBlocked("local candidate worktree is not clean")


def build_and_verify_package(root: Path, candidate_sha: str) -> tuple[Path, str]:
    build_script = root / "securewave_app" / "scripts" / "build_deb.sh"
    if not build_script.is_file():
        raise GateBlocked("documented package build script is unavailable")

    run_checked(
        ["bash", str(build_script)],
        cwd=root,
        label="candidate ARM64 package build",
        timeout=1800,
    )

    package_dir = root / "securewave_app" / "build" / "packaging"
    package_path = package_dir / PACKAGE_FILENAME
    checksum_path = package_dir / f"{PACKAGE_FILENAME}.sha256"
    if not package_path.is_file() or not checksum_path.is_file():
        raise GateBlocked("candidate package or checksum is unavailable")

    run_checked(
        ["sha256sum", "--check", checksum_path.name],
        cwd=package_dir,
        label="candidate package checksum verification",
    )

    package_sha256 = hashlib.sha256()
    try:
        with package_path.open("rb") as package_file:
            for chunk in iter(lambda: package_file.read(1024 * 1024), b""):
                package_sha256.update(chunk)
    except OSError as exc:
        raise GateBlocked("candidate package checksum calculation failed") from exc

    package_sha256_value = package_sha256.hexdigest()
    package_name = run_checked(
        ["dpkg-deb", "--field", str(package_path), "Package"],
        label="package metadata inspection",
    ).strip()
    package_version = run_checked(
        ["dpkg-deb", "--field", str(package_path), "Version"],
        label="package metadata inspection",
    ).strip()
    package_architecture = run_checked(
        ["dpkg-deb", "--field", str(package_path), "Architecture"],
        label="package metadata inspection",
    ).strip()
    dependencies = run_checked(
        ["dpkg-deb", "--field", str(package_path), "Depends"],
        label="package dependency inspection",
    ).strip()
    if package_name != PACKAGE_NAME:
        raise GateBlocked("package name does not match the release contract")
    if package_version != PACKAGE_VERSION:
        raise GateBlocked("package version does not match the release contract")
    if package_architecture != PACKAGE_ARCHITECTURE:
        raise GateBlocked("package is not ARM64")
    if not dependencies:
        raise GateBlocked("package dependency metadata is missing")

    with tempfile.TemporaryDirectory(prefix="securewave-package-") as temporary_dir:
        extract_root = Path(temporary_dir)
        run_checked(
            ["dpkg-deb", "--extract", str(package_path), str(extract_root)],
            label="package payload extraction",
        )
        for relative_path in REQUIRED_PAYLOAD:
            payload_path = extract_root / relative_path
            if not payload_path.is_file():
                raise GateBlocked(f"required package payload is missing: {relative_path}")
        app_path = extract_root / "usr/lib/securewave/securewave_app"
        if not app_path.stat().st_mode & 0o111:
            raise GateBlocked("Flutter Linux executable is not executable")

        embedded_sha = read_required(
            extract_root / "usr/share/securewave/release/source-sha",
            label="embedded source SHA",
        )
        embedded_tree_state = read_required(
            extract_root / "usr/share/securewave/release/source-tree-state",
            label="embedded source tree state",
        )
        embedded_contract = read_required(
            extract_root / "usr/share/securewave/release/helper-contract",
            label="embedded helper contract",
        )
        payload_contract = read_required(
            extract_root / "usr/share/securewave/packaging/linux/securewave-wg-quick.contract",
            label="payload helper contract",
        )
        if embedded_sha != candidate_sha:
            raise GateBlocked("package source SHA does not match the candidate")
        if embedded_tree_state != "clean":
            raise GateBlocked("package was not built from a clean source tree")
        if embedded_contract != EXPECTED_HELPER_CONTRACT:
            raise GateBlocked("embedded helper contract is incompatible")
        if payload_contract != EXPECTED_HELPER_CONTRACT:
            raise GateBlocked("payload helper contract is incompatible")

    local_candidate_checks(root, candidate_sha)
    return package_path, package_sha256_value


def ssh_script(device: str, script: str, *, label: str, timeout: int = 180) -> None:
    run_checked(
        [
            "ssh",
            "-o",
            "BatchMode=yes",
            "-o",
            "ConnectTimeout=10",
            device,
            "bash",
            "-s",
        ],
        input_text=script,
        label=label,
        timeout=timeout,
    )


def remote_preflight_script(remote_root: Path, candidate_sha: str) -> str:
    quoted_root = shlex.quote(str(remote_root))
    quoted_sha = shlex.quote(candidate_sha)
    return f"""set -eu
test "$(id -u)" -ne 0
test "$(uname -m)" = aarch64
test "$(dpkg --print-architecture)" = arm64
test -d /run/systemd/system
command -v wg >/dev/null 2>&1
command -v wg-quick >/dev/null 2>&1
command -v ip >/dev/null 2>&1
login_user="$(id -un)"
id -nG "$login_user" | tr ' ' '\n' | grep -qx securewave

if ip -4 rule show | awk '$1 == "220:" {{ found=1 }} END {{ exit found ? 0 : 1 }}'; then
  exit 1
fi
if ip -6 rule show | awk '$1 == "220:" {{ found=1 }} END {{ exit found ? 0 : 1 }}'; then
  exit 1
fi
if ip link show sw-wg >/dev/null 2>&1; then
  exit 1
fi
if ip route show table 51820 | grep -q .; then
  exit 1
fi
if systemctl list-units --type=service --state=active --no-legend 2>/dev/null | \\
    awk 'tolower($1) ~ /(strongswan|ipsec)/ {{ found=1 }} END {{ exit found ? 0 : 1 }}'; then
  exit 1
fi

candidate_root={quoted_root}
test -d "$candidate_root/.git"
test "$(git -C "$candidate_root" rev-parse HEAD)" = {quoted_sha}
test -z "$(git -C "$candidate_root" status --porcelain --untracked-files=all)"
"""


def remote_install_script(remote_root: Path, candidate_sha: str) -> str:
    quoted_root = shlex.quote(str(remote_root))
    quoted_sha = shlex.quote(candidate_sha)
    quoted_package = shlex.quote(f"/tmp/{PACKAGE_FILENAME}")
    return f"""set -eu
test "$(id -u)" -ne 0
test -f {quoted_package}
sudo -n apt-get install -y {quoted_package} >/dev/null 2>&1
sudo -n systemctl is-active --quiet securewave-helper.service
test -S /run/securewave/helper.sock
test "$(stat -c '%a' /run/securewave/helper.sock)" = 660
login_user="$(id -un)"
id -nG "$login_user" | tr ' ' '\n' | grep -qx securewave
uid="$(id -u)"
sudo -n awk -v uid="$uid" '$1 == uid {{ found=1 }} END {{ exit !found }}' /etc/securewave/helper-users
python3 -c 'import socket; s=socket.socket(socket.AF_UNIX, socket.SOCK_STREAM); s.settimeout(3); s.connect("/run/securewave/helper.sock"); s.sendall(b"version=1\\nop=probe\\nprotocol=wireguard\\n"); d=s.recv(4096); raise SystemExit(1 if (not d or b"code=unauthorized" in d) else 0)'

candidate_root={quoted_root}
test "$(git -C "$candidate_root" rev-parse HEAD)" = {quoted_sha}
test -z "$(git -C "$candidate_root" status --porcelain --untracked-files=all)"
"""


def remote_verifier_script(remote_root: Path) -> str:
    quoted_root = shlex.quote(str(remote_root))
    return f"""set -eu
candidate_root={quoted_root}
cd "$candidate_root"
test -f scripts/linux_vpn_runtime_verifier.py
out_file="$(mktemp /tmp/securewave-runtime-verifier.XXXXXX.out)"
err_file="$(mktemp /tmp/securewave-runtime-verifier.XXXXXX.err)"
trap 'rm -f "$out_file" "$err_file"' EXIT
if ! python3 scripts/linux_vpn_runtime_verifier.py >"$out_file" 2>"$err_file"; then
  exit 1
fi
test -s "$out_file"
if grep -Eq '^(FAIL|BLOCKED) ' "$out_file" "$err_file"; then
  exit 1
fi
"""


def main() -> int:
    args = parse_args()
    try:
        remote_root = validate_args(args)
        root = Path(__file__).resolve().parent.parent
        local_candidate_checks(root, args.candidate_sha)
        package_path, package_sha256 = build_and_verify_package(root, args.candidate_sha)

        ssh_script(
            args.device,
            remote_preflight_script(remote_root, args.candidate_sha),
            label="clean ARM64 device preflight",
        )
        run_checked(
            [
                "scp",
                "-o",
                "BatchMode=yes",
                "-o",
                "ConnectTimeout=10",
                str(package_path),
                f"{args.device}:/tmp/{PACKAGE_FILENAME}",
            ],
            label="candidate package transfer",
            timeout=300,
        )
        ssh_script(
            args.device,
            remote_install_script(remote_root, args.candidate_sha),
            label="authorized package installation and helper verification",
            timeout=300,
        )
        ssh_script(
            args.device,
            remote_verifier_script(remote_root),
            label="remote SecureWave read-only verifier",
            timeout=300,
        )
    except GateBlocked as exc:
        print(f"BLOCKED: {exc}", file=sys.stderr)
        return 2

    print(f"candidate_sha={args.candidate_sha}")
    print("candidate_worktree_clean=true")
    print(f"package={PACKAGE_FILENAME}")
    print(f"package_sha256={package_sha256}")
    print(f"package_architecture={PACKAGE_ARCHITECTURE}")
    print(f"helper_contract={EXPECTED_HELPER_CONTRACT}")
    print("remote_verifier=passed")
    print("gui_wireguard_lifecycle=not_run")
    print("website_publication=not_run")
    print("NEXT: run securewave-vpn in the approved device graphical session.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
