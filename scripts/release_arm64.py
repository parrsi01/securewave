#!/usr/bin/env python3
"""Fixed, fail-closed ARM64 Debian release checks.

This module deliberately does not accept arbitrary commands, hosts, URLs, or
workflow names.  It validates the repository/package/release contracts and
delegates deployment only to the existing production wrapper after all
external approvals are present.
"""

from __future__ import annotations

import hashlib
import json
import os
import platform
import re
import shutil
import subprocess
import tempfile
from pathlib import Path
from typing import Any, Mapping
from urllib.parse import urlsplit
from urllib.request import Request, urlopen

try:
    from cli_operation_common import (
        PacketValidationError,
        current_git_identity,
        ensure_external_path,
        fingerprint_api_base,
        redact_text,
        run_git,
        write_json_evidence,
    )
    from verify_operation_approval import verify_approval
except ModuleNotFoundError:  # pragma: no cover - direct package invocation
    from scripts.cli_operation_common import (
        PacketValidationError,
        current_git_identity,
        ensure_external_path,
        fingerprint_api_base,
        redact_text,
        run_git,
        write_json_evidence,
    )
    from scripts.verify_operation_approval import verify_approval


ROOT = Path(__file__).resolve().parents[1]
REQUIRED_PACKAGE_PATHS = (
    "usr/share/securewave/packaging/linux/securewave-helperd",
    "usr/share/securewave/packaging/linux/securewave-wg-quick",
    "usr/share/securewave/packaging/linux/securewave-helper.service",
    "usr/share/securewave/packaging/linux/securewave-wg-quick.contract",
    "usr/share/securewave/release/source-sha",
    "usr/share/securewave/release/package-architecture",
    "usr/share/securewave/release/package-profile",
    "usr/share/securewave/release/api-base-fingerprint",
)


class Arm64ReleaseBlocked(RuntimeError):
    """Raised when an ARM64 release prerequisite is not proven."""


def _external_path(value: Path, label: str) -> Path:
    try:
        return ensure_external_path(str(value), ROOT, label)
    except PacketValidationError as exc:
        raise Arm64ReleaseBlocked(str(exc)) from exc


def _run(command: list[str], *, env: Mapping[str, str] | None = None, timeout: int = 300) -> dict[str, Any]:
    completed = subprocess.run(
        command,
        cwd=ROOT,
        env=dict(env) if env is not None else None,
        text=True,
        capture_output=True,
        check=False,
        timeout=timeout,
    )
    return {
        "command": command,
        "exit_code": completed.returncode,
        "output": redact_text((completed.stdout + "\n" + completed.stderr).strip()),
    }


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _validate_live_api_base(packet: Mapping[str, str]) -> dict[str, Any]:
    raw = os.environ.get("SECUREWAVE_API_BASE_URL", "").strip()
    if not raw:
        raise Arm64ReleaseBlocked("SECUREWAVE_API_BASE_URL is not supplied")
    parsed = urlsplit(raw)
    if (
        parsed.scheme.lower() != "https"
        or not parsed.hostname
        or parsed.username
        or parsed.password
        or parsed.query
        or parsed.fragment
        or parsed.path.rstrip("/") != "/api"
    ):
        raise Arm64ReleaseBlocked("SECUREWAVE_API_BASE_URL must be an HTTPS /api base")
    host = parsed.hostname.lower()
    if host in {"localhost", "::1", "0.0.0.0"} or host.startswith("127."):
        raise Arm64ReleaseBlocked("SECUREWAVE_API_BASE_URL must not be loopback")
    actual_fingerprint = fingerprint_api_base(raw)
    if actual_fingerprint.lower() != packet["api_base_fingerprint"].lower():
        raise Arm64ReleaseBlocked("API base fingerprint does not match the packet")
    return {"supplied": True, "fingerprint_matches": True}


def _check_arm64_tools() -> dict[str, Any]:
    operating_system = platform.system().lower()
    machine = platform.machine().lower()
    if operating_system != "linux":
        raise Arm64ReleaseBlocked("ARM64 release requires a Linux ARM64 build/runtime host")
    if machine not in {"aarch64", "arm64"}:
        raise Arm64ReleaseBlocked("ARM64 release requires an ARM64 build/runtime host")
    missing = [tool for tool in ("dpkg", "dpkg-deb", "flutter", "wg-quick") if shutil.which(tool) is None]
    if missing:
        raise Arm64ReleaseBlocked("ARM64 release tools are unavailable")
    return {
        "platform_is_linux": True,
        "machine_is_arm64": True,
        "required_tools_present": True,
    }


def _inspect_package(path: Path, expected_sha: str) -> dict[str, Any]:
    path = _external_path(path, "ARM64 artifact")
    if not path.is_file():
        raise Arm64ReleaseBlocked("ARM64 artifact does not exist")
    actual_sha = _sha256(path)
    if actual_sha.lower() != expected_sha.lower():
        raise Arm64ReleaseBlocked("ARM64 artifact SHA-256 does not match the packet")

    field = _run(["dpkg-deb", "--field", str(path)])
    if field["exit_code"] != 0:
        raise Arm64ReleaseBlocked("dpkg-deb metadata inspection failed")
    metadata = field["output"]
    package_name = re.search(r"(?m)^Package:\s*(\S+)", metadata)
    architecture = re.search(r"(?m)^Architecture:\s*(\S+)", metadata)
    if not package_name or package_name.group(1) != "securewave-vpn":
        raise Arm64ReleaseBlocked("ARM64 artifact is not the production SecureWave package")
    if not architecture or architecture.group(1) != "arm64":
        raise Arm64ReleaseBlocked("ARM64 artifact metadata is not arm64")

    contents = _run(["dpkg-deb", "--contents", str(path)])
    if contents["exit_code"] != 0:
        raise Arm64ReleaseBlocked("dpkg-deb contents inspection failed")
    for required in REQUIRED_PACKAGE_PATHS:
        if required not in contents["output"]:
            raise Arm64ReleaseBlocked("ARM64 artifact is missing a required helper/provenance file")

    with tempfile.TemporaryDirectory(prefix="securewave-arm64-package-") as extract_root:
        extracted = _run(["dpkg-deb", "--extract", str(path), extract_root])
        if extracted["exit_code"] != 0:
            raise Arm64ReleaseBlocked("ARM64 artifact extraction failed")
        release_root = Path(extract_root) / "usr/share/securewave/release"
        profile = (release_root / "package-profile").read_text(encoding="utf-8").strip()
        package_arch = (release_root / "package-architecture").read_text(encoding="utf-8").strip()
        if profile != "production" or package_arch != "arm64":
            raise Arm64ReleaseBlocked("ARM64 artifact provenance is not a production arm64 profile")

    return {
        "present": True,
        "sha256": actual_sha,
        "package": package_name.group(1),
        "architecture": architecture.group(1),
        "helper_contract_present": True,
        "production_profile": True,
    }


def _run_release_guards() -> dict[str, Any]:
    result = _run(["bash", "scripts/verify_release_guards.sh"], timeout=300)
    if result["exit_code"] != 0:
        raise Arm64ReleaseBlocked("release guards did not pass")
    return result


def _build_artifact(packet: Mapping[str, str]) -> tuple[Path, dict[str, Any]]:
    _check_arm64_tools()
    output_dir = Path(tempfile.mkdtemp(prefix="securewave-arm64-release-"))
    env = os.environ.copy()
    env.update(
        {
            "SECUREWAVE_API_BASE_URL": env.get("SECUREWAVE_API_BASE_URL", ""),
            "SECUREWAVE_PACKAGE_PROFILE": "production",
            "SECUREWAVE_CODEX_LOCAL": "false",
            "SECUREWAVE_PACKAGE_OUTPUT_DIR": str(output_dir),
        }
    )
    result = _run(["bash", "securewave_app/scripts/build_deb.sh"], env=env, timeout=1800)
    if result["exit_code"] != 0:
        raise Arm64ReleaseBlocked("ARM64 package build failed")
    artifacts = sorted(output_dir.glob("*.deb"))
    if len(artifacts) != 1:
        raise Arm64ReleaseBlocked("ARM64 package build did not produce exactly one package")
    return artifacts[0], {"build": result, "artifact_path_present": True}


def _write_result(evidence_dir: Path, payload: dict[str, Any]) -> Path:
    return write_json_evidence(evidence_dir, "arm64-release.json", payload)


def run_preflight(
    *,
    packet: Mapping[str, str],
    evidence_dir: Path,
    artifact: Path | None = None,
) -> tuple[str, Path]:
    evidence_dir = _external_path(evidence_dir, "evidence_dir")
    evidence_dir.mkdir(parents=True, exist_ok=True)
    evidence: dict[str, Any] = {
        "operation": "release-arm64",
        "mode": "preflight",
        "environment": packet.get("environment"),
        "candidate_sha": packet.get("candidate_sha"),
        "external_mutation": "not attempted",
    }
    try:
        evidence["api"] = _validate_live_api_base(packet)
        evidence["tools"] = _check_arm64_tools()
        evidence["release_guards"] = _run_release_guards()
        if artifact is None:
            artifact, build = _build_artifact(packet)
            evidence["build"] = build
        evidence["artifact"] = _inspect_package(artifact, packet["artifact_sha256"])
    except Arm64ReleaseBlocked as exc:
        evidence["result"] = "BLOCKED_EXTERNAL_ACCESS"
        evidence["blocker"] = str(exc)
        destination = _write_result(evidence_dir, evidence)
        return "BLOCKED_EXTERNAL_ACCESS", destination

    evidence["result"] = "ARM64_RELEASE_CANDIDATE"
    destination = _write_result(evidence_dir, evidence)
    return "ARM64_RELEASE_CANDIDATE", destination


def _validate_deployment_inputs(packet: Mapping[str, str]) -> dict[str, Any]:
    target = os.environ.get("SECUREWAVE_DEPLOY_TARGET_REFERENCE", "").strip()
    if target != packet["authorized_target_reference"]:
        raise Arm64ReleaseBlocked("deployment target reference does not match the packet")
    image = os.environ.get("SECUREWAVE_PRODUCTION_IMAGE", "").strip()
    if image != packet["immutable_image_reference"]:
        raise Arm64ReleaseBlocked("production image does not match the packet")
    if os.environ.get("CONFIRM_DEPLOY") != "securewave-production":
        raise Arm64ReleaseBlocked("production deployment confirmation is missing")
    if shutil.which("ssh") is None or shutil.which("scp") is None:
        raise Arm64ReleaseBlocked("SSH deployment tools are unavailable")
    if not os.environ.get("SECUREWAVE_PRODUCTION_HOST", "").strip():
        raise Arm64ReleaseBlocked("production deployment host is not supplied")
    return {"target_matches": True, "immutable_image_matches": True, "ssh_tools_present": True}


def _manifest_matches(artifact: Path, expected_sha: str) -> bool:
    manifest_path = ROOT / "static/downloads/manifest.json"
    try:
        payload = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return False
    filename = artifact.name
    for entry in payload.get("downloads", []):
        if entry.get("filename") == filename:
            return (
                entry.get("platform") == "linux"
                and entry.get("architecture") == "arm64"
                and entry.get("status") == "available"
                and entry.get("url") == f"/downloads/{filename}"
                and entry.get("checksum_sha256", "").lower() == expected_sha.lower()
            )
    return False


def _verify_public_download(expected_sha: str) -> dict[str, Any]:
    public_url = os.environ.get("SECUREWAVE_PUBLIC_DOWNLOAD_URL", "").strip()
    parsed = urlsplit(public_url)
    if parsed.scheme != "https" or not parsed.hostname or parsed.query or parsed.fragment:
        raise Arm64ReleaseBlocked("public download URL must be an explicit HTTPS URL")
    request = Request(public_url, method="GET")
    try:
        with urlopen(request, timeout=30) as response:
            body = response.read()
            status = response.status
    except Exception as exc:
        raise Arm64ReleaseBlocked(f"public download verification failed:{type(exc).__name__}") from exc
    if status != 200 or hashlib.sha256(body).hexdigest().lower() != expected_sha.lower():
        raise Arm64ReleaseBlocked("public download checksum or status did not match")
    return {"status": status, "checksum_matches": True}


def run_publish(
    *,
    packet: Mapping[str, str],
    evidence_dir: Path,
    artifact: Path,
    approval_file: Path,
) -> tuple[str, Path]:
    evidence_dir = _external_path(evidence_dir, "evidence_dir")
    artifact = _external_path(artifact, "ARM64 artifact")
    approval_file = _external_path(approval_file, "approval_file")
    evidence: dict[str, Any] = {
        "operation": "release-arm64",
        "mode": "publish",
        "environment": packet.get("environment"),
        "candidate_sha": packet.get("candidate_sha"),
        "external_mutation": "not attempted",
    }
    try:
        identity = current_git_identity(ROOT)
        if not identity["clean"]:
            raise Arm64ReleaseBlocked("release publish requires a clean worktree")
        if identity["branch"] != packet["release_branch"]:
            raise Arm64ReleaseBlocked("current branch does not match the release packet")
        if identity["head"].lower() != packet["candidate_sha"].lower():
            raise Arm64ReleaseBlocked("current HEAD does not match the release packet")
        evidence["api"] = _validate_live_api_base(packet)
        evidence["artifact"] = _inspect_package(artifact, packet["artifact_sha256"])
        if not _manifest_matches(artifact, packet["artifact_sha256"]):
            raise Arm64ReleaseBlocked(
                "ARM64 artifact is not already staged in the guarded download manifest"
            )
        evidence["deployment_inputs"] = _validate_deployment_inputs(packet)
        approval = verify_approval(
            approval_file=approval_file,
            public_key_file=Path(packet["approval_public_key_file"]),
            ledger_file=Path(packet["approval_ledger_file"]),
            operation="release_arm64",
            environment="production",
            target_ref=packet["authorized_target_reference"],
            candidate_sha=identity["head"],
            artifact_sha256=packet["artifact_sha256"],
            immutable_image_reference=packet["immutable_image_reference"],
            consume=False,
            repository_root=ROOT,
        )
        evidence["approval"] = approval
        if os.environ.get("SECUREWAVE_RELEASE_PUSH", "").strip().lower() != "true":
            raise Arm64ReleaseBlocked("SECUREWAVE_RELEASE_PUSH=true is required for publish mode")
        raise Arm64ReleaseBlocked(
            "backend image publication and remote ARM64 runtime verification require an authorized fixed CI/target contract"
        )
    except Exception as exc:
        if isinstance(exc, Arm64ReleaseBlocked):
            evidence["result"] = "BLOCKED_EXTERNAL_ACCESS"
            evidence["blocker"] = str(exc)
        else:
            evidence["result"] = "FAIL"
            evidence["blocker"] = f"{type(exc).__name__}"
        destination = _write_result(evidence_dir, evidence)
        return evidence["result"], destination
