#!/usr/bin/env python3
"""Produce a local, redacted history report for SecureWave login behavior."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import sys
import tarfile
import tempfile
import subprocess
from pathlib import Path
from typing import Any

try:  # Support both direct CLI execution and package-based tests.
    from cli_operation_common import (
        current_git_identity,
        ensure_external_path,
        fingerprint_api_base,
        run_git,
        write_json_evidence,
    )
except ModuleNotFoundError:  # pragma: no cover - import mode depends on invocation
    from scripts.cli_operation_common import (
        current_git_identity,
        ensure_external_path,
        fingerprint_api_base,
        run_git,
        write_json_evidence,
    )


ROOT = Path(__file__).resolve().parents[1]


DEB_FIXED_PAYLOAD_PATHS = (
    "usr/bin/securewave-vpn",
    "usr/lib/securewave/securewave_app",
    "usr/lib/securewave/lib/libapp.so",
    "usr/lib/securewave/lib/libflutter_secure_storage_linux_plugin.so",
    "usr/lib/securewave/data/flutter_assets/.env",
    "usr/share/securewave/release/source-sha",
    "usr/share/securewave/release/source-tree-state",
    "usr/share/securewave/release/app-version",
    "usr/share/securewave/release/package-architecture",
)

INSTALLED_RUNTIME_PATHS = (
    "usr/bin/securewave-vpn",
    "usr/lib/securewave/securewave_app",
)


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _parse_deb_control(text: str) -> dict[str, str]:
    """Keep only safe package identity fields from a Debian control file."""

    fields: dict[str, str] = {}
    allowed = {"Package", "Version", "Architecture", "Depends"}
    for raw_line in text.splitlines():
        key, separator, value = raw_line.partition(":")
        if separator and key in allowed and key not in fields:
            fields[key] = value.strip()
    return fields


def _elf_architecture(prefix: bytes) -> str | None:
    if prefix[:4] != b"\x7fELF" or len(prefix) < 20:
        return None
    if prefix[4] != 2 or prefix[5] != 1:
        return "unknown"
    machine = int.from_bytes(prefix[18:20], byteorder="little")
    return {62: "x86_64", 183: "aarch64"}.get(machine, "unknown")


def _ascii_strings(data: bytes) -> list[str]:
    return [
        match.decode("ascii", errors="ignore")
        for match in re.findall(rb"[ -~]{4,}", data)
    ]


def _safe_deb_components(path: Path) -> tuple[str, list[str], dict[str, bytes]]:
    """Read selected Debian members without executing package contents.

    Native Debian hosts use ``dpkg-deb``.  The macOS Codex workstation does
    not have that tool, so the read-only fallback uses ``ar`` and ``bsdtar``.
    Only fixed, known payload paths are extracted into a temporary directory or
    memory; package-provided paths are never used as extraction destinations.
    """

    if shutil.which("dpkg-deb"):
        with tempfile.TemporaryDirectory(prefix="securewave-deb-control-") as raw_dir:
            control_dir = Path(raw_dir) / "control"
            data_dir = Path(raw_dir) / "data"
            control_dir.mkdir()
            data_dir.mkdir()
            control_result = subprocess.run(
                ["dpkg-deb", "--control", str(path), str(control_dir)],
                capture_output=True,
                check=False,
                timeout=60,
            )
            if control_result.returncode != 0:
                raise RuntimeError("dpkg-deb control inspection failed")
            control_file = control_dir / "control"
            control_text = control_file.read_text(encoding="utf-8", errors="replace")
            contents_result = subprocess.run(
                ["dpkg-deb", "--contents", str(path)],
                capture_output=True,
                check=False,
                timeout=60,
            )
            if contents_result.returncode != 0:
                raise RuntimeError("dpkg-deb content inspection failed")
            extract_result = subprocess.run(
                ["dpkg-deb", "--extract", str(path), str(data_dir)],
                capture_output=True,
                check=False,
                timeout=60,
            )
            if extract_result.returncode != 0:
                raise RuntimeError("dpkg-deb payload inspection failed")
            payload = {
                relative: (data_dir / relative).read_bytes()
                for relative in DEB_FIXED_PAYLOAD_PATHS
                if (data_dir / relative).is_file()
            }
            names = [line for line in contents_result.stdout.decode("utf-8", "replace").splitlines() if line]
            return control_text, names, payload

    if not shutil.which("ar") or not shutil.which("bsdtar"):
        raise RuntimeError("no supported Debian inspection tool is available")

    archive_members = subprocess.run(
        ["ar", "t", str(path)],
        capture_output=True,
        check=False,
        timeout=60,
    )
    if archive_members.returncode != 0:
        raise RuntimeError("ar member inspection failed")
    members = set(archive_members.stdout.decode("utf-8", "replace").splitlines())
    control_member = next(
        (name for name in ("control.tar.zst", "control.tar.xz", "control.tar.gz", "control.tar") if name in members),
        None,
    )
    data_member = next(
        (name for name in ("data.tar.zst", "data.tar.xz", "data.tar.gz", "data.tar") if name in members),
        None,
    )
    if not control_member or not data_member:
        raise RuntimeError("Debian control or data archive is missing")

    def read_ar_member(name: str) -> bytes:
        result = subprocess.run(
            ["ar", "p", str(path), name],
            capture_output=True,
            check=False,
            timeout=60,
        )
        if result.returncode != 0:
            raise RuntimeError("ar payload member could not be read")
        return result.stdout

    def list_tar_members(archive: bytes) -> list[str]:
        result = subprocess.run(
            ["bsdtar", "-tf", "-"],
            input=archive,
            capture_output=True,
            check=False,
            timeout=60,
        )
        if result.returncode != 0:
            raise RuntimeError("Debian tar member listing failed")
        return [line for line in result.stdout.decode("utf-8", "replace").splitlines() if line]

    def read_tar_member(archive: bytes, relative: str) -> bytes | None:
        for candidate in (f"./{relative}", relative):
            result = subprocess.run(
                ["bsdtar", "-xOf", "-", candidate],
                input=archive,
                capture_output=True,
                check=False,
                timeout=60,
            )
            if result.returncode == 0:
                return result.stdout
        return None

    control_archive = read_ar_member(control_member)
    data_archive = read_ar_member(data_member)
    control_bytes = read_tar_member(control_archive, "control")
    if control_bytes is None:
        raise RuntimeError("Debian control file is missing")
    names = list_tar_members(data_archive)
    payload: dict[str, bytes] = {}
    for relative in DEB_FIXED_PAYLOAD_PATHS:
        member_bytes = read_tar_member(data_archive, relative)
        if member_bytes is not None:
            payload[relative] = member_bytes
    return control_bytes.decode("utf-8", "replace"), names, payload


def _runtime_log_record(path_value: Path | None) -> dict[str, Any]:
    if path_value is None:
        return {"present": False, "classification": "UNKNOWN"}
    path = ensure_external_path(str(path_value), ROOT, "runtime_log")
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return {"present": False, "classification": "UNKNOWN"}
    keyring_failure = "libsecret_error" in text or "Failed to unlock the keyring" in text
    login_signal = bool(re.search(r"/auth/login|login", text, flags=re.IGNORECASE))
    return {
        "present": True,
        "classification": "RUNTIME_LOG_FACT",
        "filename": path.name,
        "size_bytes": path.stat().st_size,
        "keyring_unlock_failure_observed": keyring_failure,
        "login_signal_observed": login_signal,
        "egl_warning_observed": "libEGL warning" in text,
        "runtime_error_signal_observed": "CRITICAL" in text or "ERROR" in text,
        "runtime_result": (
            "KEYRING_ACCESS_FAILURE_OBSERVED"
            if keyring_failure
            else "LOGIN_ATTEMPT_SIGNAL_PRESENT"
            if login_signal
            else "NO_LOGIN_ATTEMPT_PROOF"
        ),
    }


def _source_commit_relationship(source_sha: str, current_head: str) -> tuple[bool, str]:
    """Classify an artifact source commit against the current checkout."""

    if not re.fullmatch(r"[0-9a-fA-F]{40}", source_sha):
        return False, "UNKNOWN_SOURCE_SHA"
    if not current_head:
        return False, "CURRENT_HEAD_UNKNOWN"
    source_exists = run_git(
        "cat-file",
        "-e",
        f"{source_sha}^{{commit}}",
        repository_root=ROOT,
    ).returncode == 0
    if not source_exists:
        return False, "SOURCE_COMMIT_NOT_PRESENT_LOCALLY"
    if source_sha.lower() == current_head.lower():
        return True, "CURRENT_HEAD"
    source_is_ancestor = run_git(
        "merge-base",
        "--is-ancestor",
        source_sha,
        current_head,
        repository_root=ROOT,
    ).returncode == 0
    if source_is_ancestor:
        return True, "ANCESTOR_OF_CURRENT_HEAD"
    current_is_ancestor = run_git(
        "merge-base",
        "--is-ancestor",
        current_head,
        source_sha,
        repository_root=ROOT,
    ).returncode == 0
    if current_is_ancestor:
        return True, "CURRENT_HEAD_IS_ANCESTOR"
    return True, "UNRELATED_TO_CURRENT_HEAD"


def _ordered_markers(text: str, first: str, second: str) -> bool:
    """Return whether two source markers occur in the supplied order."""

    first_index = text.find(first)
    second_index = text.find(second)
    return first_index >= 0 and second_index > first_index


def _function_segment(text: str, function_name: str, next_function: str) -> str:
    """Return one source function body without evaluating or executing it."""

    match = re.search(
        rf"Future<void>\s+{re.escape(function_name)}\b.*?(?=\n\s*Future<void>\s+{re.escape(next_function)}\b|\Z)",
        text,
        flags=re.DOTALL,
    )
    return match.group(0) if match else ""


def _login_storage_facts(
    auth_service: str,
    auth_session: str,
    secure_storage: str,
) -> dict[str, bool]:
    """Record redacted source markers for the login-to-keyring handoff.

    These booleans make a keyring-related runtime signal useful without
    claiming that a particular binary reached the API or that a token was
    successfully stored.  No source values, account data, or credentials are
    copied into the report.
    """

    login_body = _function_segment(auth_service, "login", "register")
    session_body = _function_segment(auth_session, "setSession", "clearSession")
    return {
        "login_calls_api_before_local_session_work": _ordered_markers(
            login_body,
            "final tokens = await _api.login",
            "_session.setSession",
        ),
        "login_clears_vpn_state_before_session": _ordered_markers(
            login_body,
            "clearVpnRuntimeState",
            "_session.setSession",
        ),
        "login_session_call_present": "_session.setSession" in login_body,
        "session_restores_from_secure_storage": "getAccessToken" in auth_session,
        "session_persists_before_memory_authentication": _ordered_markers(
            session_body,
            "await _storage.saveTokens",
            "_isAuthenticated = true",
        ),
        "session_memory_authentication_precedes_persistence": _ordered_markers(
            session_body,
            "_isAuthenticated = true",
            "await _storage.saveTokens",
        ),
        "session_handles_storage_failure": (
            "SecureStorageUnavailableException" in auth_session
            and "Session token storage failed" in auth_session
        ),
        "secure_storage_uses_platform_keyring": "FlutterSecureStorage" in secure_storage,
        "historical_login_reads_owner_before_state_clear": _ordered_markers(
            login_body,
            "getAccountOwnerEmail",
            "clearVpnRuntimeState",
        ),
    }


def _source_commit_api_facts(source_sha: str) -> dict[str, Any]:
    """Read only the source-controlled API/build facts for an artifact SHA.

    The current checkout is not necessarily the source of an external package.
    Comparing an artifact only with the current fallback can therefore hide a
    historical build-path difference.  This helper records fingerprints and
    boolean relationships only; it never places an API URL in the report.
    """

    if not re.fullmatch(r"[0-9a-fA-F]{40}", source_sha):
        return {"classification": "UNKNOWN", "source_commit_present": False}

    source_exists = run_git(
        "cat-file",
        "-e",
        f"{source_sha}^{{commit}}",
        repository_root=ROOT,
    ).returncode == 0
    if not source_exists:
        return {
            "classification": "UNKNOWN",
            "source_commit_present": False,
        }

    def historical_file(path: str) -> str:
        result = run_git("show", f"{source_sha}:{path}", repository_root=ROOT)
        return result.stdout if result.returncode == 0 else ""

    constants = historical_file("securewave_app/lib/core/constants/app_constants.dart")
    config = historical_file("securewave_app/lib/core/config/app_config.dart")
    build = historical_file("securewave_app/scripts/build_deb.sh")
    auth_service = historical_file("securewave_app/lib/services/auth_service.dart")
    auth_session = historical_file("securewave_app/lib/core/services/auth_session.dart")
    secure_storage = historical_file("securewave_app/lib/core/services/secure_storage.dart")
    fallback_match = re.search(
        r"baseUrlFallback\s*=\s*['\"]([^'\"]+)",
        constants,
    )
    fallback = fallback_match.group(1).strip() if fallback_match else ""
    return {
        "classification": "HISTORICAL_SOURCE_FACT",
        "source_commit_present": True,
        "fallback_present": bool(fallback),
        "fallback_fingerprint": fingerprint_api_base(fallback) if fallback else None,
        "build_has_explicit_api_define": "--dart-define=SECUREWAVE_API_BASE_URL="
        in build,
        "build_has_explicit_mock_off_define": "--dart-define=SECUREWAVE_USE_MOCK_API=false"
        in build,
        "config_loads_dotenv_without_release_guard": "dotenv.load(fileName: '.env'"
        in config
        and "if (!_isReleaseBuild)" not in config,
        "config_has_release_dotenv_guard": "if (!_isReleaseBuild)" in config
        and "final env = !_isReleaseBuild && dotenv.isInitialized" in config,
        "login_storage_facts": _login_storage_facts(
            auth_service,
            auth_session,
            secure_storage,
        ),
    }


def _installed_runtime_record(
    installed_root: Path | None,
    package_payload: dict[str, bytes],
) -> dict[str, Any]:
    """Compare fixed installed paths with the corresponding package bytes.

    The optional root is an operator-supplied local filesystem root.  Only the
    two known executable paths are read; no package scripts are executed and
    the root path itself is not written to evidence.
    """

    if installed_root is None:
        return {
            "present": False,
            "classification": "UNKNOWN",
            "comparison": "INSTALLED_ROOT_NOT_SUPPLIED",
        }
    root = ensure_external_path(str(installed_root), ROOT, "installed_root")
    if not root.is_dir():
        return {
            "present": False,
            "classification": "UNKNOWN",
            "comparison": "INSTALLED_ROOT_NOT_A_DIRECTORY",
        }

    files: list[dict[str, Any]] = []
    for relative in INSTALLED_RUNTIME_PATHS:
        installed = root / relative
        package_bytes = package_payload.get(relative)
        package_sha = (
            hashlib.sha256(package_bytes).hexdigest()
            if package_bytes is not None
            else None
        )
        if not installed.is_file():
            files.append(
                {
                    "path": relative,
                    "installed_present": False,
                    "package_present": package_bytes is not None,
                    "sha256_match": False,
                }
            )
            continue
        installed_sha = _sha256_file(installed)
        files.append(
            {
                "path": relative,
                "installed_present": True,
                "package_present": package_bytes is not None,
                "installed_size_bytes": installed.stat().st_size,
                "package_size_bytes": len(package_bytes) if package_bytes is not None else None,
                "installed_sha256": installed_sha,
                "package_sha256": package_sha,
                "sha256_match": package_sha is not None and installed_sha == package_sha,
            }
        )
    all_match = bool(files) and all(
        item["installed_present"]
        and item["package_present"]
        and item["sha256_match"]
        for item in files
    )
    return {
        "present": True,
        "classification": "CURRENT_RUNTIME_FACT",
        "comparison": "INSTALLED_FILES_MATCH_PACKAGE"
        if all_match
        else "INSTALLED_FILES_DO_NOT_MATCH_PACKAGE",
        "files": files,
    }


def _keyring_dependency_facts(*, depends: str, plugin_bytes: bytes) -> dict[str, Any]:
    """Compare the package's keyring linkage with its declared dependency.

    The Flutter Linux secure-storage plugin is native code.  A package can
    contain that plugin while omitting the shared-library runtime dependency
    needed by the target operating system.  Record only boolean contract
    facts; do not execute the plugin or copy arbitrary strings into evidence.
    """

    plugin_strings = _ascii_strings(plugin_bytes)
    plugin_links_libsecret = "libsecret-1.so.0" in plugin_strings
    declared_libsecret = any(
        item.strip().split("(", 1)[0].split(" ", 1)[0] == "libsecret-1-0"
        for item in depends.split(",")
    )
    if plugin_links_libsecret and declared_libsecret:
        status = "PASS_KEYRING_DEPENDENCY_DECLARED"
    elif plugin_links_libsecret and not declared_libsecret:
        status = "BLOCKED_KEYRING_DEPENDENCY_UNDECLARED"
    elif not plugin_links_libsecret and declared_libsecret:
        status = "UNKNOWN_PLUGIN_LINKAGE"
    else:
        status = "NOT_OBSERVED"
    return {
        "secure_storage_plugin_libsecret_linkage_present": plugin_links_libsecret,
        "libsecret_runtime_dependency_declared": declared_libsecret,
        "keyring_runtime_dependency_status": status,
    }


def _debian_artifact_record(
    path_value: Path,
    runtime_log: Path | None = None,
    installed_root: Path | None = None,
) -> dict[str, Any]:
    """Inspect one exact .deb without launching or installing it."""

    path = ensure_external_path(str(path_value), ROOT, "deb_artifact")
    if not path.is_file():
        return {"artifact_present": False, "classification": "UNKNOWN", "filename": path.name}

    record: dict[str, Any] = {
        "artifact_present": True,
        "classification": "CURRENT_ARTIFACT_FACT",
        "filename": path.name,
        "artifact_path": str(path),
        "size_bytes": path.stat().st_size,
        "sha256": _sha256_file(path),
        "executed": False,
        "installed": False,
    }
    manifest_record = _manifest_artifact_record()
    expected_manifest_sha = manifest_record.get("checksum_sha256")
    if isinstance(expected_manifest_sha, str):
        record["manifest_checksum_present"] = True
        record["manifest_checksum_match"] = (
            record["sha256"].lower() == expected_manifest_sha.lower()
        )
    else:
        record["manifest_checksum_present"] = False
        record["manifest_checksum_match"] = None
    try:
        control_text, member_names, payload = _safe_deb_components(path)
    except Exception as exc:
        record.update(
            {
            "parseable": False,
            "classification": "UNKNOWN",
            "inspection_blocker": type(exc).__name__,
            "runtime_log": _runtime_log_record(runtime_log),
            "installed_runtime": {
                "present": False,
                "classification": "UNKNOWN",
                "comparison": "PACKAGE_NOT_PARSEABLE",
            },
        }
        )
        return record

    control = _parse_deb_control(control_text)
    source_sha = payload.get("usr/share/securewave/release/source-sha", b"").decode("ascii", "ignore").strip()
    source_tree_state = payload.get("usr/share/securewave/release/source-tree-state", b"").decode("ascii", "ignore").strip()
    app_bytes = payload.get("usr/lib/securewave/lib/libapp.so", b"")
    keyring_dependency_facts = _keyring_dependency_facts(
        depends=control.get("Depends", ""),
        plugin_bytes=payload.get(
            "usr/lib/securewave/lib/libflutter_secure_storage_linux_plugin.so",
            b"",
        ),
    )
    app_text = "\n".join(_ascii_strings(app_bytes))
    api_candidates = sorted(
        set(re.findall(r"https?://[^\s\"'<>]+/api(?:/)?", app_text))
    )
    current_constant = _file_text("securewave_app/lib/core/constants/app_constants.dart")
    fallback_match = re.search(r"baseUrlFallback\s*=\s*['\"]([^'\"]+)", current_constant)
    current_fallback = fallback_match.group(1) if fallback_match else ""
    template_text = _file_text(".env.example.flutter")
    template_match = re.search(r"^SECUREWAVE_API_BASE_URL=(\S+)", template_text, flags=re.MULTILINE)
    historical_template = template_match.group(1) if template_match else ""
    api_fingerprints = sorted(
        {
            fingerprint_api_base(candidate)
            for candidate in api_candidates
        }
    )
    if current_fallback and current_fallback in api_candidates:
        api_configuration = "CURRENT_RELEASE_FALLBACK"
    elif historical_template and historical_template in api_candidates:
        api_configuration = "HISTORICAL_TEMPLATE"
    elif any(candidate.startswith(("http://localhost", "http://127.", "https://localhost")) for candidate in api_candidates):
        api_configuration = "LOCAL_OR_NONPRODUCTION"
    elif api_candidates:
        api_configuration = "UNRECOGNIZED_EXPLICIT_API"
    else:
        api_configuration = "API_VALUE_NOT_OBSERVED"

    try:
        current_head = current_git_identity(ROOT)["head"]
    except Exception:
        current_head = ""
    source_sha_valid = bool(re.fullmatch(r"[0-9a-fA-F]{40}", source_sha))
    source_api_facts = _source_commit_api_facts(source_sha) if source_sha_valid else {
        "classification": "UNKNOWN",
        "source_commit_present": False,
    }
    source_fallback_fingerprint = source_api_facts.get("fallback_fingerprint")
    source_fallback_matches_embedded = (
        isinstance(source_fallback_fingerprint, str)
        and source_fallback_fingerprint in api_fingerprints
    )
    source_matches_current = bool(source_sha_valid and current_head and source_sha.lower() == current_head.lower())
    source_commit_present, source_commit_relationship = _source_commit_relationship(
        source_sha,
        current_head,
    )
    app_architecture = _elf_architecture(payload.get("usr/lib/securewave/securewave_app", b""))
    release_architecture = payload.get("usr/share/securewave/release/package-architecture", b"").decode("ascii", "ignore").strip()
    if release_architecture == "amd64" and app_architecture == "x86_64" and source_sha_valid and not source_matches_current:
        release_safety = "BLOCKED_SOURCE_SHA_MISMATCH"
    elif api_configuration == "HISTORICAL_TEMPLATE":
        release_safety = "BLOCKED_EMBEDDED_API_TEMPLATE"
    elif api_configuration == "CURRENT_RELEASE_FALLBACK" and source_matches_current:
        release_safety = "CURRENT_HEAD_STATIC_ONLY"
    else:
        release_safety = "UNKNOWN"

    record.update(
        {
            "parseable": True,
            "package_name": control.get("Package"),
            "package_version": control.get("Version"),
            "package_architecture": control.get("Architecture"),
            "package_depends": control.get("Depends"),
            "payload_member_count": len(member_names),
            "source_sha": source_sha if source_sha_valid else None,
            "source_commit_present_locally": source_commit_present,
            "source_commit_relationship": source_commit_relationship,
            "source_tree_state": source_tree_state or None,
            "current_checkout_head": current_head or None,
            "source_matches_current_checkout": source_matches_current,
            "app_architecture": app_architecture,
            "release_architecture": release_architecture or None,
            "flutter_env_asset_present": "usr/lib/securewave/data/flutter_assets/.env" in payload,
            "embedded_api_value_present": bool(api_candidates),
            "embedded_api_value_fingerprints": api_fingerprints,
            "embedded_api_candidate_count": len(api_candidates),
            "embedded_api_configuration": api_configuration,
            "source_commit_api_facts": {
                key: value
                for key, value in source_api_facts.items()
                if key != "fallback_fingerprint"
            }
            | {
                "fallback_fingerprint": source_fallback_fingerprint,
                "fallback_matches_embedded_api": source_fallback_matches_embedded,
            },
            "auth_login_route_marker_present": "/auth/login" in app_text,
            "auth_me_route_marker_present": "/auth/me" in app_text,
            "mock_api_marker_present": "SECUREWAVE_USE_MOCK_API" in app_text,
            "mock_api_explicit_false_marker_present": "SECUREWAVE_USE_MOCK_API=false" in app_text,
            "secure_storage_plugin_present": "usr/lib/securewave/lib/libflutter_secure_storage_linux_plugin.so" in payload,
            **keyring_dependency_facts,
            "release_safety": release_safety,
            "runtime_log": _runtime_log_record(runtime_log),
            "installed_runtime": _installed_runtime_record(installed_root, payload),
        }
    )
    return record


def _file_text(relative_path: str) -> str:
    path = ROOT / relative_path
    try:
        return path.read_text(encoding="utf-8")
    except OSError:
        return ""


def _manifest_artifact_record() -> dict[str, Any]:
    """Return non-network evidence for the repository's x64 .deb record."""

    path = ROOT / "static/downloads/manifest.json"
    try:
        manifest = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {"record_present": False, "classification": "UNKNOWN"}
    for entry in manifest.get("downloads", []):
        if (
            isinstance(entry, dict)
            and entry.get("platform") == "linux"
            and entry.get("architecture") == "x64"
            and entry.get("filename") == "securewave-linux-x64.deb"
        ):
            url = str(entry.get("url", ""))
            return {
                "record_present": True,
                "classification": "CURRENT_SOURCE_FACT",
                "filename": entry.get("filename"),
                "status": entry.get("status"),
                "checksum_sha256": entry.get("checksum_sha256"),
                "evidence_reference_present": bool(entry.get("evidence_url")),
                "evidence_reference_fingerprint": hashlib.sha256(
                    url.encode("utf-8")
                ).hexdigest()
                if url
                else None,
                "local_file_present": (ROOT / "static/downloads" / entry["filename"]).is_file(),
            }
    return {"record_present": False, "classification": "UNKNOWN"}


def _portable_linux_artifact_record() -> dict[str, Any]:
    """Inspect the tracked x64 portable artifact without executing it.

    The repository currently contains a portable tarball in addition to the
    manifest's x64 Debian evidence record.  Reading its Flutter asset gives
    exact artifact evidence for the historical login configuration while
    keeping URLs and account values out of the report.
    """

    artifact = ROOT / "static/downloads/securewave-linux-x64.tar.gz"
    if not artifact.is_file():
        return {"artifact_present": False, "classification": "UNKNOWN"}

    digest = hashlib.sha256()
    with artifact.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    artifact_commit_result = run_git(
        "log",
        "-1",
        "--format=%H",
        "--",
        "static/downloads/securewave-linux-x64.tar.gz",
        repository_root=ROOT,
    )
    artifact_source_commit = artifact_commit_result.stdout.strip()

    def member_named(tar: tarfile.TarFile, suffix: str) -> tarfile.TarInfo | None:
        for member in tar.getmembers():
            if member.name.rstrip("/") == suffix or member.name.rstrip("/") == f"./{suffix}":
                return member
        return None

    try:
        with tarfile.open(artifact, mode="r:gz") as tar:
            env_member = member_named(tar, "data/flutter_assets/.env")
            version_member = member_named(tar, "data/flutter_assets/version.json")
            binary_member = member_named(tar, "securewave_app")
            env_text = (
                tar.extractfile(env_member).read().decode("utf-8", errors="replace")
                if env_member is not None
                else ""
            )
            version_text = (
                tar.extractfile(version_member).read().decode("utf-8", errors="replace")
                if version_member is not None
                else ""
            )
            binary_prefix = (
                tar.extractfile(binary_member).read(20)
                if binary_member is not None
                else b""
            )
    except (OSError, tarfile.TarError):
        return {
            "artifact_present": True,
            "classification": "UNKNOWN",
            "sha256": digest.hexdigest(),
            "source_commit": artifact_source_commit or None,
            "parseable": False,
        }

    env_values: dict[str, str] = {}
    for raw_line in env_text.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        env_values[key.strip()] = value.strip().strip("\"").strip("'")

    try:
        version = json.loads(version_text) if version_text else {}
    except json.JSONDecodeError:
        version = {}

    elf_machine: str | None = None
    if binary_prefix[:4] == b"\x7fELF" and len(binary_prefix) >= 20:
        machine = int.from_bytes(binary_prefix[18:20], byteorder="little")
        elf_machine = {62: "x86_64", 183: "aarch64"}.get(machine, "unknown")

    api_value = env_values.get("SECUREWAVE_API_BASE_URL", "")
    return {
        "artifact_present": True,
        "classification": "CURRENT_ARTIFACT_FACT",
        "filename": artifact.name,
        "sha256": digest.hexdigest(),
        "source_commit": artifact_source_commit or None,
        "size_bytes": artifact.stat().st_size,
        "parseable": True,
        "binary_architecture": elf_machine,
        "version": version.get("version") if isinstance(version, dict) else None,
        "build_number": version.get("build_number") if isinstance(version, dict) else None,
        "flutter_env_asset_present": env_member is not None,
        "embedded_api_value_present": bool(api_value),
        "embedded_api_value_fingerprint": hashlib.sha256(api_value.encode("utf-8")).hexdigest()
        if api_value
        else None,
        "embedded_api_matches_historical_template": api_value
        == "https://api.your-domain.com/api",
        "embedded_api_matches_current_release_fallback": api_value
        == "https://api.securewaveapp.com/api",
        "embedded_api_matches_local_dev": api_value == "http://localhost:8000/api",
        "embedded_mock_value_present": "SECUREWAVE_USE_MOCK_API" in env_values,
        "embedded_mock_value_is_false": env_values.get("SECUREWAVE_USE_MOCK_API") == "false",
        "release_safety": (
            "BLOCKED_EMBEDDED_API_TEMPLATE"
            if api_value == "https://api.your-domain.com/api"
            else "UNKNOWN"
        ),
    }


def _history_matches(term: str, paths: list[str]) -> list[dict[str, str]]:
    result = run_git(
        "log",
        "--all",
        "--oneline",
        "-G",
        term,
        "--",
        *paths,
        repository_root=ROOT,
    )
    if result.returncode != 0:
        return []
    matches: list[dict[str, str]] = []
    for line in result.stdout.splitlines()[:20]:
        commit, _, subject = line.partition(" ")
        if re.fullmatch(r"[0-9a-f]{7,40}", commit):
            matches.append({"commit": commit, "subject": subject[:160]})
    return matches


def _historical_x64_build_facts() -> dict[str, Any]:
    """Inspect the earliest repository version of the x64 package workflow."""

    history = run_git(
        "log",
        "--all",
        "--reverse",
        "--format=%H",
        "--",
        ".github/workflows/linux-x64-deb-release.yml",
        repository_root=ROOT,
    )
    commit = history.stdout.splitlines()[0].strip() if history.returncode == 0 else ""
    if not commit:
        return {"classification": "UNKNOWN", "source_commit_present": False}

    def historical_file(path: str) -> str:
        result = run_git("show", f"{commit}:{path}", repository_root=ROOT)
        return result.stdout if result.returncode == 0 else ""

    build = historical_file("securewave_app/scripts/build_deb.sh")
    config = historical_file("securewave_app/lib/core/config/app_config.dart")
    pubspec = historical_file("securewave_app/pubspec.yaml")
    template = historical_file(".env.example.flutter")
    return {
        "classification": "HISTORICAL_SOURCE_FACT",
        "source_commit": commit,
        "source_commit_present": True,
        "build_has_explicit_api_define": "--dart-define=SECUREWAVE_API_BASE_URL=" in build,
        "build_has_explicit_mock_off_define": "--dart-define=SECUREWAVE_USE_MOCK_API=false"
        in build,
        "pubspec_declares_env_asset": "- .env" in pubspec,
        "config_loads_dotenv_without_release_guard": "dotenv.load(fileName: '.env'" in config
        and "if (!_isReleaseBuild)" not in config,
        "template_contains_nonproduction_api_placeholder": "api.your-domain.com/api"
        in template,
    }


def build_report(
    *,
    deb_artifact: Path | None = None,
    runtime_log: Path | None = None,
    installed_root: Path | None = None,
) -> dict[str, Any]:
    app_config = _file_text("securewave_app/lib/core/config/app_config.dart")
    api_client = _file_text("securewave_app/lib/services/api_client.dart")
    auth_routes = _file_text("routes/auth.py")
    main_py = _file_text("main.py")
    deb_build = _file_text("securewave_app/scripts/build_deb.sh")
    apps_build = _file_text("scripts/build_apps.sh")
    pubspec = _file_text("securewave_app/pubspec.yaml")
    auth_service = _file_text("securewave_app/lib/services/auth_service.dart")
    auth_session = _file_text("securewave_app/lib/core/services/auth_session.dart")
    secure_storage = _file_text("securewave_app/lib/core/services/secure_storage.dart")

    current_facts = {
        "app_config_exists": bool(app_config),
        "app_uses_live_fallback": "AppConstants.baseUrlFallback" in app_config,
        "release_forces_mock_off": "if (_isReleaseBuild && useMock)" in app_config
        and "useMock = false" in app_config,
        "app_login_route": "/auth/login" in api_client,
        "app_authenticated_user_route": "/auth/me" in api_client,
        "backend_requires_email_verification": "if not user.email_verified" in auth_routes
        and "Please verify your email before logging in" in auth_routes,
        "backend_supports_2fa_challenge": "requires_2fa=True" in auth_routes,
        "health_route_present": '"/api/health"' in main_py or '@app.get("/api/health")' in main_py,
        "ready_route_present": '"/api/ready"' in main_py or '@app.get("/api/ready")' in main_py,
        "email_health_route_present": '"/api/health/email"' in main_py
        or '@app.get("/api/health/email")' in main_py,
    }
    current_auth_storage_facts = _login_storage_facts(
        auth_service,
        auth_session,
        secure_storage,
    )

    packaging_facts = {
        "deb_build_passes_api_define": "--dart-define=SECUREWAVE_API_BASE_URL="
        in deb_build,
        "apps_build_passes_api_define": "--dart-define=SECUREWAVE_API_BASE_URL="
        in apps_build,
        "release_build_disables_mock_api": "--dart-define=SECUREWAVE_USE_MOCK_API=false"
        in deb_build,
        "release_config_skips_dotenv": "if (!_isReleaseBuild)" in app_config
        and "final env = !_isReleaseBuild && dotenv.isInitialized" in app_config,
        "flutter_env_asset_declared": "- .env" in pubspec,
    }
    historical_packaging_facts = _historical_x64_build_facts()
    portable_artifact_facts = _portable_linux_artifact_record()
    deb_artifact_facts = (
        _debian_artifact_record(
            deb_artifact,
            runtime_log=runtime_log,
            installed_root=installed_root,
        )
        if deb_artifact is not None
        else {"artifact_present": False, "classification": "UNKNOWN"}
    )

    history_paths = [
        "securewave_app/lib/core/config/app_config.dart",
        "securewave_app/lib/services/api_client.dart",
        "securewave_app/lib/app.dart",
        "routes/auth.py",
        "main.py",
    ]
    terms = {
        "skip_login_for_development": "skipLoginForDevelopment",
        "debug_auto_login": "debugAutoLogin",
        "mock_api": "SECUREWAVE_USE_MOCK_API",
        "api_base_url": "SECUREWAVE_API_BASE_URL",
        "email_verification": "email_verified",
        "deb_api_define": "--dart-define=SECUREWAVE_API_BASE_URL",
        "release_dotenv_guard": "_isReleaseBuild",
        "flutter_env_template": "SECUREWAVE_API_BASE_URL=https://api.your-domain.com/api",
    }
    historical_facts = {
        name: _history_matches(term, history_paths) for name, term in terms.items()
    }

    test_paths = [
        path
        for path in (
            "securewave_app/test/login_api_contract_test.dart",
            "securewave_app/test/app_config_test.dart",
            "securewave_app/test/api_client_fallback_test.dart",
            "tests/unit/test_auth.py",
        )
        if (ROOT / path).is_file()
    ]
    test_coverage = {
        "flutter_login_contract_test_present": "securewave_app/test/login_api_contract_test.dart"
        in test_paths,
        "flutter_config_test_present": "securewave_app/test/app_config_test.dart" in test_paths,
        "flutter_mock_fallback_test_present": "securewave_app/test/api_client_fallback_test.dart"
        in test_paths,
        "backend_auth_test_present": "tests/unit/test_auth.py" in test_paths,
    }

    inference: list[str] = []
    if historical_facts["skip_login_for_development"] or historical_facts["debug_auto_login"]:
        inference.append(
            "The repository history contains development-login symbols; this does not prove an early downloaded artifact used them."
        )
    if current_facts["release_forces_mock_off"] and current_facts["backend_requires_email_verification"]:
        inference.append(
            "The current release path is live-only and the current backend requires verified email before normal login."
        )
    if (
        packaging_facts["deb_build_passes_api_define"]
        and packaging_facts["release_config_skips_dotenv"]
    ):
        inference.append(
            "The current package source explicitly supplies the API base and prevents the Flutter .env asset from overriding it in release builds."
        )
    if (
        historical_packaging_facts.get("pubspec_declares_env_asset")
        and historical_packaging_facts.get("config_loads_dotenv_without_release_guard")
        and not historical_packaging_facts.get("build_has_explicit_api_define")
        and historical_packaging_facts.get("template_contains_nonproduction_api_placeholder")
    ):
        inference.append(
            "The earliest x64 package-workflow source could embed the template API value: the .env asset was packaged, release config loaded it, the template used a non-production placeholder, and the build supplied no explicit API define. This is a build-path explanation, not proof of the missing binary's bytes."
        )
    if portable_artifact_facts.get("release_safety") == "BLOCKED_EMBEDDED_API_TEMPLATE":
        inference.append(
            "The tracked x64 portable artifact contains an embedded API value matching the historical template and is therefore stale login evidence; its exact artifact bytes are known, but this macOS host cannot execute the Linux binary."
        )
    if deb_artifact_facts.get("source_matches_current_checkout") is False:
        inference.append(
            "The supplied .deb carries a source SHA different from the current checkout; it is exact static evidence for that package, not evidence for the current candidate."
        )
    if deb_artifact_facts.get("source_commit_api_facts", {}).get(
        "fallback_matches_embedded_api"
    ):
        inference.append(
            "The inspected .deb embedded API fingerprint matches the fallback in its own source commit; static package evidence does not show an API-base mismatch, although the source build did not pass an explicit API define."
        )
    if (
        deb_artifact_facts.get("package_depends")
        and "libsecret-1-0" not in deb_artifact_facts["package_depends"]
        and "libsecret-1-0" in _file_text("securewave_app/scripts/build_deb.sh")
    ):
        inference.append(
            "The inspected package control metadata does not declare libsecret-1-0, while the current Debian build source does; this is a historical package dependency gap, not proof that a keyring daemon was absent on the test host."
        )
    if (
        deb_artifact_facts.get("keyring_runtime_dependency_status")
        == "BLOCKED_KEYRING_DEPENDENCY_UNDECLARED"
    ):
        inference.append(
            "The inspected secure-storage plugin directly references libsecret-1.so.0 while the package control metadata omits libsecret-1-0; this is direct artifact contract evidence for a missing declared keyring runtime dependency, but it does not prove whether the library was absent on the machine that ran the package."
        )
    if (
        deb_artifact_facts.get("runtime_log", {}).get("runtime_result")
        == "KEYRING_ACCESS_FAILURE_OBSERVED"
    ):
        inference.append(
            "The supplied launch log records a Linux secure-storage keyring-unlock failure before any login request signal; this supports a local keyring blocker but does not prove the API login response."
        )
    if (
        current_auth_storage_facts["login_calls_api_before_local_session_work"]
        and current_auth_storage_facts["session_persists_before_memory_authentication"]
    ):
        inference.append(
            "The current source calls the live login API before local session work and persists tokens before marking the session authenticated; a keyring failure can therefore block desktop login after an HTTP success, but this source fact does not prove the supplied artifact followed the current flow."
        )
    if not inference:
        inference.append("No historical explanation was sufficient to identify the old artifact behavior.")

    findings: dict[str, dict[str, Any]] = {
        name: {"classification": "CURRENT_SOURCE_FACT", "value": value}
        for name, value in current_facts.items()
    }
    findings.update(
        {
            name: {
                "classification": "HISTORICAL_SOURCE_FACT" if value else "UNKNOWN",
                "value": value,
            }
            for name, value in historical_facts.items()
        }
    )
    findings["test_coverage"] = {
        "classification": "CURRENT_SOURCE_FACT",
        "value": test_coverage,
    }
    findings["current_auth_storage_facts"] = {
        "classification": "CURRENT_SOURCE_FACT",
        "value": current_auth_storage_facts,
    }
    findings["historical_explanation"] = {
        "classification": "HISTORICAL_INFERENCE",
        "value": inference,
    }
    findings["original_artifact"] = {
        "classification": (
            "CURRENT_ARTIFACT_FACT"
            if deb_artifact_facts.get("artifact_present")
            else "UNKNOWN"
        ),
        "value": (
            "an exact external .deb was inspected read-only"
            if deb_artifact_facts.get("artifact_present")
            else "not present in current repository evidence"
        ),
    }

    unknowns = [
        "The original downloaded binary and its build-time defines are not present in the current repository evidence.",
        "The current external API login result is not tested by this local report.",
    ]
    if deb_artifact_facts.get("artifact_present"):
        unknowns.append(
            "Static .deb inspection does not prove that a Linux keyring, account, backend response, or authenticated desktop login succeeded."
        )

    return {
        "classification": "CURRENT_SOURCE_FACT",
        "current_git": current_git_identity(ROOT),
        "current_source_facts": current_facts,
        "current_auth_storage_facts": current_auth_storage_facts,
        "packaging_facts": packaging_facts,
        "historical_packaging_facts": historical_packaging_facts,
        "manifest_artifact_record": _manifest_artifact_record(),
        "portable_linux_artifact_record": portable_artifact_facts,
        "debian_artifact_record": deb_artifact_facts,
        "historical_source_facts": historical_facts,
        "test_coverage": test_coverage,
        "historical_inferences": inference,
        "findings": findings,
        "unknowns": unknowns,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--evidence-dir", required=True, type=Path)
    parser.add_argument(
        "--deb-artifact",
        type=Path,
        help="Optional external .deb to inspect without installing or executing it.",
    )
    parser.add_argument(
        "--runtime-log",
        type=Path,
        help="Optional external launch log; only safe signal flags are recorded.",
    )
    parser.add_argument(
        "--installed-root",
        type=Path,
        help="Optional external local filesystem root for fixed installed-file comparison.",
    )
    args = parser.parse_args(argv)

    try:
        report = build_report(
            deb_artifact=args.deb_artifact,
            runtime_log=args.runtime_log,
            installed_root=args.installed_root,
        )
        destination = write_json_evidence(args.evidence_dir, "login-provenance.json", report)
    except Exception as exc:  # pragma: no cover - defensive CLI boundary
        print(f"LOGIN_PROVENANCE_STATUS=FAIL:{type(exc).__name__}", file=sys.stderr)
        return 1

    print("LOGIN_PROVENANCE_STATUS=PASS")
    print(f"LOGIN_PROVENANCE_EVIDENCE={destination}")
    print("LOGIN_PROVENANCE_RESULT=HISTORICAL_BEHAVIOR_REQUIRES_ARTIFACT_PROOF")
    return 0


if __name__ == "__main__":
    sys.exit(main())
