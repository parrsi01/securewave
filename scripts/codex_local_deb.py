#!/usr/bin/env python3
"""Build and statically validate the isolated Codex-local ARM64 Debian lane."""

from __future__ import annotations

import hashlib
import re
import shutil
import subprocess
import uuid
from pathlib import Path
from typing import Any
from urllib.parse import urlsplit

try:  # Support direct CLI execution and package-based tests.
    from cli_operation_common import (
        PacketValidationError,
        current_git_identity,
        ensure_external_path,
        fingerprint_api_base,
        write_json_evidence,
    )
except ModuleNotFoundError:  # pragma: no cover - import mode depends on invocation
    from scripts.cli_operation_common import (
        PacketValidationError,
        current_git_identity,
        ensure_external_path,
        fingerprint_api_base,
        write_json_evidence,
    )


ROOT = Path(__file__).resolve().parents[1]
DOCKER_IMAGE = "securewave-codex-local-deb:3.44.0-arm64"
DOCKER_PLATFORM = "linux/arm64"
BASE_IMAGE = "ubuntu:24.04@sha256:b17516cd982bf06bdd5d5600253d12a8de017b9eb831cc052b532a0363d294f9"
FLUTTER_VERSION = "3.44.0"
FLUTTER_COMMIT = "559ffa3f75e7402d65a8def9c28389a9b2e6fe42"
PACKAGE_NAME = "securewave-vpn-codex-local"
REQUIRED_PACKAGE_CONTENTS = (
    "usr/share/securewave/packaging/linux/securewave-wg-quick",
    "usr/share/securewave/packaging/linux/securewave-helperd",
    "usr/share/securewave/packaging/linux/securewave-helper.service",
    "usr/share/securewave/packaging/linux/securewave-helper.tmpfiles",
    "usr/share/securewave/packaging/linux/securewave-wg-quick.contract",
    "usr/share/securewave/release/source-sha",
    "usr/share/securewave/release/source-tree-state",
    "usr/share/securewave/release/app-version",
    "usr/share/securewave/release/package-architecture",
    "usr/share/securewave/release/package-profile",
    "usr/share/securewave/release/api-base-fingerprint",
    "usr/share/securewave/release/helper-contract",
)


class LocalDebBlocked(RuntimeError):
    """Raised when a required local builder prerequisite is unavailable."""


class LocalDebError(RuntimeError):
    """Raised when an executed local build or package validation fails."""


def validate_loopback_api_base(value: str) -> str:
    """Validate the exact non-production API contract used by the local lane."""

    candidate = value.strip()
    if not candidate:
        raise LocalDebBlocked("an explicit loopback API base is required")
    try:
        parsed = urlsplit(candidate)
        hostname = parsed.hostname
        port = parsed.port
    except ValueError as exc:
        raise LocalDebBlocked("the local API base is malformed") from exc
    if parsed.scheme != "http" or parsed.username or parsed.password:
        raise LocalDebBlocked("the local API base must be an HTTP loopback URL")
    if parsed.query or parsed.fragment or hostname not in {"localhost", "127.0.0.1"}:
        raise LocalDebBlocked("the local API base must be an HTTP loopback URL")
    if port is not None and not 1 <= port <= 65535:
        raise LocalDebBlocked("the local API base port is invalid")
    if parsed.path.rstrip("/") != "/api":
        raise LocalDebBlocked("the local API base must end in /api")
    return candidate


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _application_version() -> str:
    pubspec = ROOT / "securewave_app" / "pubspec.yaml"
    for line in pubspec.read_text(encoding="utf-8").splitlines():
        if line.startswith("version:"):
            version = line.split(":", 1)[1].strip()
            if re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+", version):
                return version
    raise LocalDebError("the Flutter application version is unavailable")


def _run_docker(arguments: list[str], *, timeout: int) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(
            ["docker", *arguments],
            cwd=ROOT,
            text=True,
            capture_output=True,
            check=False,
            timeout=timeout,
        )
    except FileNotFoundError as exc:
        raise LocalDebBlocked("Docker is not available on PATH") from exc
    except subprocess.TimeoutExpired as exc:
        raise LocalDebError("the Docker local build timed out") from exc


def _docker_server_platform() -> str:
    if shutil.which("docker") is None:
        raise LocalDebBlocked("Docker is not available on PATH")
    result = _run_docker(["version", "--format", "{{.Server.Os}}/{{.Server.Arch}}"], timeout=30)
    platform = result.stdout.strip().lower()
    if result.returncode != 0 or platform not in {"linux/arm64", "linux/aarch64"}:
        raise LocalDebBlocked("the Docker daemon is not Linux ARM64")
    return platform


def _prepare_output_dir(value: Path) -> Path:
    output_dir = ensure_external_path(str(value), ROOT, "output_dir")
    if not output_dir.parent.is_dir():
        raise LocalDebBlocked("the output directory parent does not exist")
    output_dir.mkdir(exist_ok=True)
    if not output_dir.is_dir():
        raise LocalDebBlocked("the output path is not a directory")
    if any(path.is_file() and path.suffix == ".deb" for path in output_dir.iterdir()):
        raise LocalDebBlocked("the output directory contains a pre-existing Debian artifact")
    return output_dir


def _build_image() -> dict[str, Any]:
    dockerfile = ROOT / "Dockerfile.codex-local-deb"
    if not dockerfile.is_file():
        raise LocalDebBlocked("the fixed local ARM64 Dockerfile is missing")
    result = _run_docker(
        [
            "build",
            "--platform=linux/arm64",
            "--pull",
            "--file",
            str(dockerfile),
            "--tag",
            DOCKER_IMAGE,
            str(ROOT),
        ],
        timeout=3600,
    )
    if result.returncode != 0:
        if result.returncode == 125:
            raise LocalDebBlocked("Docker could not build the fixed local ARM64 image")
        raise LocalDebError("the fixed local ARM64 Docker image build failed")

    inspect = _run_docker(
        ["image", "inspect", DOCKER_IMAGE, "--format", "{{.Os}}/{{.Architecture}}"],
        timeout=30,
    )
    image_platform = inspect.stdout.strip().lower()
    if inspect.returncode != 0 or image_platform not in {"linux/arm64", "linux/aarch64"}:
        raise LocalDebError("the built local image is not Linux ARM64")
    return {
        "image": DOCKER_IMAGE,
        "base_image": BASE_IMAGE,
        "platform": image_platform,
        "flutter_version": FLUTTER_VERSION,
        "flutter_commit": FLUTTER_COMMIT,
        "build_exit_code": result.returncode,
    }


def _remove_container(container_name: str) -> None:
    _run_docker(["rm", "--force", container_name], timeout=60)


def _run_package_build(api_base: str, output_dir: Path) -> int:
    """Build in a temporary container and copy only the package to the host.

    Docker Desktop may not expose the host's ``/tmp`` directory to its Linux
    daemon even when the CLI can resolve that path locally.  Using
    ``docker cp`` instead of an output bind mount keeps the documented external
    output contract working without weakening the repository path guard.
    """

    container_name = f"securewave-local-deb-build-{uuid.uuid4().hex}"
    created = _run_docker(
        [
            "create",
            "--platform=linux/arm64",
            "--name",
            container_name,
            "--mount",
            f"type=bind,src={ROOT},dst=/source,readonly",
            "--env",
            f"SECUREWAVE_API_BASE_URL={api_base}",
            DOCKER_IMAGE,
        ],
        timeout=60,
    )
    if created.returncode == 125:
        raise LocalDebBlocked("Docker could not create the local ARM64 package builder")
    if created.returncode != 0:
        raise LocalDebError("Docker could not create the local ARM64 package builder")
    try:
        started = _run_docker(["start", "--attach", container_name], timeout=3600)
        if started.returncode == 125:
            raise LocalDebBlocked("Docker could not start the local ARM64 package builder")
        if started.returncode != 0:
            raise LocalDebError("the local Debian package build failed")
        copied = _run_docker(
            ["cp", f"{container_name}:/out/.", str(output_dir)],
            timeout=300,
        )
        if copied.returncode != 0:
            raise LocalDebError("Docker could not copy the local Debian artifact")
        return started.returncode
    finally:
        _remove_container(container_name)


def _parse_validation_output(output: str) -> tuple[dict[str, str], str]:
    fields: dict[str, str] = {}
    content_lines: list[str] = []
    in_contents = False
    for line in output.splitlines():
        if line == "contents_begin":
            in_contents = True
            continue
        if line == "contents_end":
            in_contents = False
            continue
        if in_contents:
            content_lines.append(line)
            continue
        key, separator, value = line.partition("=")
        if separator and key:
            fields[key] = value
    if not fields or not content_lines:
        raise LocalDebError("the local package validator returned incomplete evidence")
    return fields, "\n".join(content_lines)


def _validate_package(api_base: str, output_dir: Path, source_sha: str) -> dict[str, Any]:
    packages = sorted(output_dir.glob("*.deb"))
    if len(packages) != 1:
        raise LocalDebError("the local package build did not produce exactly one Debian artifact")
    package = packages[0]
    if not package.name.startswith(f"{PACKAGE_NAME}_"):
        raise LocalDebError("the local package has the wrong package name")

    container_name = f"securewave-local-deb-validate-{uuid.uuid4().hex}"
    created = _run_docker(
        [
            "create",
            "--platform=linux/arm64",
            "--name",
            container_name,
            "--entrypoint",
            "/usr/local/bin/codex-local-deb-container",
            DOCKER_IMAGE,
            "validate",
        ],
        timeout=60,
    )
    if created.returncode == 125:
        raise LocalDebBlocked("Docker could not create the local ARM64 package validator")
    if created.returncode != 0:
        raise LocalDebError("Docker could not create the local ARM64 package validator")
    try:
        copied = _run_docker(
            ["cp", str(package), f"{container_name}:/out/"],
            timeout=300,
        )
        if copied.returncode != 0:
            raise LocalDebError("Docker could not copy the local package for inspection")
        started = _run_docker(["start", "--attach", container_name], timeout=300)
        if started.returncode == 125:
            raise LocalDebBlocked("Docker could not start the local ARM64 package validator")
        if started.returncode != 0:
            raise LocalDebError("the local Debian package validator failed")
        fields, contents = _parse_validation_output(started.stdout)
    finally:
        _remove_container(container_name)

    expected_fingerprint = fingerprint_api_base(api_base)
    expected_version = _application_version()
    expected_contract = (ROOT / "securewave_app/packaging/linux/securewave-wg-quick.contract").read_text(
        encoding="utf-8"
    ).strip()
    if fields.get("package") != PACKAGE_NAME:
        raise LocalDebError("the local package metadata name is incorrect")
    if fields.get("architecture") != "arm64":
        raise LocalDebError("the local package metadata architecture is not arm64")
    if fields.get("version") != expected_version:
        raise LocalDebError("the local package version does not match the source")
    if source_sha.lower() != fields.get("provenance_source-sha", "").lower():
        raise LocalDebError("the local package provenance source SHA does not match HEAD")
    if fields.get("provenance_source-tree-state") != "clean":
        raise LocalDebError("the local package provenance does not report a clean source tree")
    if fields.get("provenance_package-architecture") != "arm64":
        raise LocalDebError("the local package provenance architecture is not arm64")
    if fields.get("provenance_package-profile") != "codex-local":
        raise LocalDebError("the local package provenance profile is not codex-local")
    if fields.get("provenance_api-base-fingerprint") != expected_fingerprint:
        raise LocalDebError("the local package API-base fingerprint does not match the input")
    if fields.get("provenance_helper-contract") != expected_contract:
        raise LocalDebError("the local package helper contract does not match the source")
    declared_dependencies = {
        item.strip().split(" ", 1)[0] for item in fields.get("depends", "").split(",")
    }
    if "libsecret-1-0" not in declared_dependencies:
        raise LocalDebError("the local package does not declare libsecret-1-0")
    for required in REQUIRED_PACKAGE_CONTENTS:
        if required not in contents:
            raise LocalDebError("the local package is missing a required helper or provenance file")

    return {
        "filename": package.name,
        "sha256": _sha256_file(package),
        "package": fields["package"],
        "version": fields["version"],
        "architecture": fields["architecture"],
        "depends_libsecret": True,
        "profile": fields["provenance_package-profile"],
        "source_sha": fields["provenance_source-sha"],
        "api_base_fingerprint": fields["provenance_api-base-fingerprint"],
        "required_contents_present": True,
        "mock_api": False,
    }


def run_local_deb(
    *,
    api_base: str,
    output_dir: Path,
    evidence_dir: Path,
) -> tuple[str, Path]:
    """Build and validate one non-production package without touching a target."""

    evidence_dir = ensure_external_path(str(evidence_dir), ROOT, "evidence_dir")
    output_dir = ensure_external_path(str(output_dir), ROOT, "output_dir")
    evidence: dict[str, Any] = {
        "operation": "local-deb",
        "environment": "codex-local",
        "external_system_status": "no application, provider, deployment, or public target contacted",
        "package_profile": "codex-local",
        "mock_api": False,
    }
    result = "UNKNOWN"
    try:
        api_base = validate_loopback_api_base(api_base)
        output_dir = _prepare_output_dir(output_dir)
        identity = current_git_identity(ROOT)
        if identity["repository_root"] != str(ROOT):
            raise LocalDebBlocked("the current repository root is not SecureWave")
        if not identity["clean"]:
            raise LocalDebBlocked("the source worktree is not clean")
        source_sha = identity["head"]
        manifest = ROOT / "static/downloads/manifest.json"
        manifest_before = _sha256_file(manifest)
        docker_platform = _docker_server_platform()
        image = _build_image()
        build_exit_code = _run_package_build(api_base, output_dir)
        if build_exit_code != 0:
            raise LocalDebError("the local Debian package build failed")
        package = _validate_package(api_base, output_dir, source_sha)
        manifest_after = _sha256_file(manifest)
        if manifest_before != manifest_after:
            raise LocalDebError("the public download manifest changed during local packaging")
        evidence.update(
            {
                "result": "LOCAL_PACKAGE_READY",
                "branch": identity["branch"],
                "candidate_sha": source_sha,
                "docker": {"server_platform": docker_platform, **image},
                "api": {
                    "profile": "codex-local",
                    "loopback_only": True,
                    "fingerprint": fingerprint_api_base(api_base),
                    "mock_api": False,
                },
                "package": package,
                "download_manifest_unchanged": True,
            }
        )
        result = "LOCAL_PACKAGE_READY"
    except PacketValidationError as exc:
        evidence.update({"result": "BLOCKED_LOCAL_BUILD", "blocker": str(exc)})
        result = "BLOCKED_LOCAL_BUILD"
    except LocalDebBlocked as exc:
        evidence.update({"result": "BLOCKED_LOCAL_BUILD", "blocker": str(exc)})
        result = "BLOCKED_LOCAL_BUILD"
    except LocalDebError as exc:
        evidence.update({"result": "FAIL", "failure": str(exc)})
        result = "FAIL"
    except (OSError, RuntimeError) as exc:
        evidence.update({"result": "UNKNOWN", "failure": type(exc).__name__})
        result = "UNKNOWN"

    destination = write_json_evidence(evidence_dir, "local-deb.json", evidence)
    return result, destination
