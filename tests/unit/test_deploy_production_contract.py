from __future__ import annotations

import os
import stat
import subprocess
from pathlib import Path

import pytest


REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "scripts" / "deploy_production.sh"
VALID_DIGEST = "a" * 64
VALID_COMMIT_TAG = "b" * 40


def _write_fake_command(path: Path, command: str) -> None:
    if command == "ssh":
        body = """#!/usr/bin/env bash
set -euo pipefail
{
  printf 'ssh\\n'
  printf '<%s>\\n' "$@"
} >> "$TRACE_FILE"
printf 'transport-invoked\\n' > "$MARKER_FILE"
cat >> "$TRACE_INPUT"
"""
    else:
        body = """#!/usr/bin/env bash
set -euo pipefail
{
  printf 'scp\\n'
  printf '<%s>\\n' "$@"
} >> "$TRACE_FILE"
printf 'transport-invoked\\n' > "$MARKER_FILE"
"""
    path.write_text(body, encoding="utf-8")
    path.chmod(path.stat().st_mode | stat.S_IXUSR)


def _base_environment(tmp_path: Path) -> tuple[dict[str, str], Path, Path]:
    compose_template = tmp_path / "compose.yaml"
    compose_template.write_text("services: {}\n", encoding="utf-8")

    fake_bin = tmp_path / "bin"
    fake_bin.mkdir()
    _write_fake_command(fake_bin / "ssh", "ssh")
    _write_fake_command(fake_bin / "scp", "scp")

    trace_file = tmp_path / "trace.txt"
    trace_input = tmp_path / "remote-input.txt"
    env = os.environ.copy()
    env.update(
        {
            "CONFIRM_DEPLOY": "securewave-production",
            "SECUREWAVE_COMPOSE_TEMPLATE": str(compose_template),
            "SECUREWAVE_PRODUCTION_HOST": "prod.example.com",
            "SECUREWAVE_PRODUCTION_IMAGE": (
                f"ghcr.io/securewave/app@sha256:{VALID_DIGEST}"
            ),
            "SECUREWAVE_PRODUCTION_USER": "securewave",
            "SECUREWAVE_REMOTE_APP_DIR": "/opt/securewave",
            "TRACE_FILE": str(trace_file),
            "TRACE_INPUT": str(trace_input),
            "MARKER_FILE": str(tmp_path / "unexpected-command.marker"),
            "PATH": f"{fake_bin}:{env.get('PATH', '')}",
        }
    )
    return env, trace_file, trace_input


def _run_deploy(env: dict[str, str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", str(SCRIPT)],
        cwd=REPO_ROOT,
        env=env,
        capture_output=True,
        text=True,
        check=False,
        timeout=10,
    )


def _assert_rejected(
    result: subprocess.CompletedProcess[str],
    env: dict[str, str],
    trace_file: Path,
    trace_input: Path,
) -> None:
    assert result.returncode == 2
    assert not trace_file.exists()
    assert not trace_input.exists()
    assert not Path(env["MARKER_FILE"]).exists()


def test_missing_host_rejects_without_execution(tmp_path: Path) -> None:
    env, trace_file, trace_input = _base_environment(tmp_path)
    env.pop("SECUREWAVE_PRODUCTION_HOST")

    result = _run_deploy(env)

    _assert_rejected(result, env, trace_file, trace_input)


@pytest.mark.parametrize(
    "host",
    [
        "",
        "https://prod.example.com",
        "/opt/production",
        "prod.example.com/path",
        "prod.example.com with-space",
        "prod.example.com;id",
        "prod.example.com$(id)",
        "prod.example.com`id`",
        "'prod.example.com'",
        '"prod.example.com"',
        "prod.example.com\nsecond-line",
        "localhost",
        "localhost.localdomain",
        "localhost6",
        "127.0.0.1",
        "127.1",
        "0",
        "0.0.0.0",
        "::1",
        "::",
        "*",
    ],
)
def test_production_host_rejects_unsafe_values(tmp_path: Path, host: str) -> None:
    env, trace_file, trace_input = _base_environment(tmp_path)
    env["SECUREWAVE_PRODUCTION_HOST"] = host

    result = _run_deploy(env)

    _assert_rejected(result, env, trace_file, trace_input)


@pytest.mark.parametrize(
    "host",
    ["prod.example.com", "203.0.113.10", "2001:db8::10"],
)
def test_valid_production_hosts_reach_only_fake_ssh(
    tmp_path: Path, host: str
) -> None:
    env, trace_file, trace_input = _base_environment(tmp_path)
    env["SECUREWAVE_PRODUCTION_HOST"] = host

    result = _run_deploy(env)

    assert result.returncode == 0
    assert trace_file.exists()
    assert trace_input.exists()


def test_missing_image_rejects_without_execution(tmp_path: Path) -> None:
    env, trace_file, trace_input = _base_environment(tmp_path)
    env.pop("SECUREWAVE_PRODUCTION_IMAGE")

    result = _run_deploy(env)

    _assert_rejected(result, env, trace_file, trace_input)


@pytest.mark.parametrize(
    "image",
    [
        f"securewave/app@sha256:{VALID_DIGEST}",
        "ghcr.io/securewave/app:latest",
        "ghcr.io/securewave/app:main",
        "ghcr.io/securewave/app:test",
        f"ghcr.io/securewave/app:{'c' * 39}",
        f"ghcr.io/securewave/app@sha256:{'d' * 63}",
        f"ghcr.io/securewave/app@sha256:{'e' * 65}",
        f"ghcr.io/securewave/app@sha512:{VALID_DIGEST}",
        "ghcr.io/securewave//app:" + VALID_COMMIT_TAG,
        "ghcr.io/securewave/App:" + VALID_COMMIT_TAG,
        "ghcr.io/securewave/app",
        "ghcr.io/securewave/app:$(id)",
        "ghcr.io/securewave/app:'tag'",
        "ghcr.io/securewave/app:tag with-space",
        "ghcr.io/securewave/app;id:" + VALID_COMMIT_TAG,
    ],
)
def test_image_reference_rejects_unqualified_mutable_or_malformed_values(
    tmp_path: Path, image: str
) -> None:
    env, trace_file, trace_input = _base_environment(tmp_path)
    env["SECUREWAVE_PRODUCTION_IMAGE"] = image

    result = _run_deploy(env)

    _assert_rejected(result, env, trace_file, trace_input)


@pytest.mark.parametrize(
    "image",
    [
        f"ghcr.io/securewave/app@sha256:{VALID_DIGEST}",
        "registry.example.com:5000/securewave/app:" + VALID_COMMIT_TAG,
    ],
)
def test_image_reference_accepts_only_immutable_forms(
    tmp_path: Path, image: str
) -> None:
    env, trace_file, _ = _base_environment(tmp_path)
    env["SECUREWAVE_PRODUCTION_IMAGE"] = image

    result = _run_deploy(env)

    assert result.returncode == 0
    assert trace_file.exists()


@pytest.mark.parametrize(
    ("user", "directory"),
    [
        ("", "/opt/securewave"),
        ("secure wave", "/opt/securewave"),
        ("securewave;id", "/opt/securewave"),
        ("securewave$(id)", "/opt/securewave"),
        ("-securewave", "/opt/securewave"),
        ("securewave", "opt/securewave"),
        ("securewave", "/opt//securewave"),
        ("securewave", "/opt/../etc"),
        ("securewave", "/opt/./securewave"),
        ("securewave", "/opt/securewave/"),
        ("securewave", "/opt/secure wave"),
        ("securewave", "/opt/securewave;id"),
        ("securewave", "/"),
    ],
)
def test_remote_user_and_directory_reject_unsafe_values(
    tmp_path: Path, user: str, directory: str
) -> None:
    env, trace_file, trace_input = _base_environment(tmp_path)
    env["SECUREWAVE_PRODUCTION_USER"] = user
    env["SECUREWAVE_REMOTE_APP_DIR"] = directory

    result = _run_deploy(env)

    _assert_rejected(result, env, trace_file, trace_input)


def test_required_guards_and_static_remote_scripts_are_preserved(
    tmp_path: Path,
) -> None:
    env, trace_file, trace_input = _base_environment(tmp_path)
    env.pop("CONFIRM_DEPLOY")

    result = _run_deploy(env)

    _assert_rejected(result, env, trace_file, trace_input)

    source = SCRIPT.read_text(encoding="utf-8")
    assert "SECUREWAVE_ALLOW_AMBIGUOUS_TAG" not in source
    assert "test -s .env" in source
    assert "docker compose --env-file .env config --quiet" in source
    assert "BatchMode=yes" in source
    assert "/bin/bash -s --" in source
    assert "docker pull '${SECUREWAVE_PRODUCTION_IMAGE}'" not in source


def test_ambiguous_tag_override_cannot_bypass_immutable_image_guard(
    tmp_path: Path,
) -> None:
    env, trace_file, trace_input = _base_environment(tmp_path)
    env["SECUREWAVE_ALLOW_AMBIGUOUS_TAG"] = "true"
    env["SECUREWAVE_PRODUCTION_IMAGE"] = "ghcr.io/securewave/app:latest"

    result = _run_deploy(env)

    _assert_rejected(result, env, trace_file, trace_input)


def test_missing_compose_template_rejects_without_execution(tmp_path: Path) -> None:
    env, trace_file, trace_input = _base_environment(tmp_path)
    env["SECUREWAVE_COMPOSE_TEMPLATE"] = str(tmp_path / "missing-compose.yaml")

    result = _run_deploy(env)

    _assert_rejected(result, env, trace_file, trace_input)


def test_injection_payloads_cannot_execute_or_create_marker(tmp_path: Path) -> None:
    env, trace_file, trace_input = _base_environment(tmp_path)
    marker = env["MARKER_FILE"]
    payloads = [
        ("SECUREWAVE_PRODUCTION_HOST", f"prod.example.com$(touch {marker})"),
        (
            "SECUREWAVE_PRODUCTION_IMAGE",
            f"ghcr.io/securewave/app:$(touch {marker})",
        ),
        ("SECUREWAVE_PRODUCTION_USER", f"securewave$(touch {marker})"),
        ("SECUREWAVE_REMOTE_APP_DIR", f"/opt/securewave$(touch {marker})"),
    ]

    for variable, payload in payloads:
        case_env = env.copy()
        case_env[variable] = payload
        result = _run_deploy(case_env)

        _assert_rejected(result, case_env, trace_file, trace_input)


def test_valid_deploy_passes_values_as_arguments_not_remote_shell_source(
    tmp_path: Path,
) -> None:
    env, trace_file, trace_input = _base_environment(tmp_path)
    image = env["SECUREWAVE_PRODUCTION_IMAGE"]
    directory = env["SECUREWAVE_REMOTE_APP_DIR"]

    result = _run_deploy(env)

    assert result.returncode == 0
    trace = trace_file.read_text(encoding="utf-8")
    remote_source = trace_input.read_text(encoding="utf-8")
    assert "BatchMode=yes" in trace
    assert "securewave@prod.example.com" in trace
    assert "/bin/bash" in trace
    assert image not in remote_source
    assert directory not in remote_source
    assert 'remote_dir="$1"' in remote_source
    assert 'image="$2"' in remote_source
    assert 'docker pull "$image"' in remote_source
