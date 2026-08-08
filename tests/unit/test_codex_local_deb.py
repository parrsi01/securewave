import json
import subprocess
from argparse import Namespace
from pathlib import Path

import pytest

from scripts import codex_cli_controller, codex_local_deb
from scripts.cli_operation_common import fingerprint_api_base


ROOT = Path(__file__).resolve().parents[2]


def test_local_api_base_requires_http_loopback_api_path():
    assert (
        codex_local_deb.validate_loopback_api_base("http://127.0.0.1:18080/api")
        == "http://127.0.0.1:18080/api"
    )
    with pytest.raises(codex_local_deb.LocalDebBlocked):
        codex_local_deb.validate_loopback_api_base("https://127.0.0.1/api")
    with pytest.raises(codex_local_deb.LocalDebBlocked):
        codex_local_deb.validate_loopback_api_base("http://staging.example.test/api")
    with pytest.raises(codex_local_deb.LocalDebBlocked):
        codex_local_deb.validate_loopback_api_base("http://127.0.0.1:18080/not-api")


def test_local_builder_rejects_unavailable_docker_without_leaking_input(
    monkeypatch, tmp_path: Path
):
    monkeypatch.setattr(
        codex_local_deb,
        "_docker_server_platform",
        lambda: (_ for _ in ()).throw(
            codex_local_deb.LocalDebBlocked("Docker is not available on PATH")
        ),
    )
    result, evidence_path = codex_local_deb.run_local_deb(
        api_base="http://127.0.0.1:18080/api",
        output_dir=tmp_path / "artifacts",
        evidence_dir=tmp_path / "evidence",
    )

    assert result == "BLOCKED_LOCAL_BUILD"
    evidence = json.loads(evidence_path.read_text(encoding="utf-8"))
    serialized = json.dumps(evidence, sort_keys=True)
    assert evidence["result"] == "BLOCKED_LOCAL_BUILD"
    assert "127.0.0.1" not in serialized
    assert "password" not in serialized.lower()
    assert "token" not in serialized.lower()


def test_validation_output_is_structured_without_raw_provider_data():
    fields, contents = codex_local_deb._parse_validation_output(
        "package_filename=securewave-vpn-codex-local_4.0.0+1_arm64.deb\n"
        "package=securewave-vpn-codex-local\n"
        "version=4.0.0+1\n"
        "architecture=arm64\n"
        "depends=wireguard-tools, libsecret-1-0\n"
        "contents_begin\n"
        "./usr/bin/securewave-vpn\n"
        "contents_end\n"
        "provenance_package-profile=codex-local\n"
    )

    assert fields["package"] == "securewave-vpn-codex-local"
    assert fields["architecture"] == "arm64"
    assert "usr/bin/securewave-vpn" in contents
    assert "password" not in json.dumps(fields).lower()


def test_package_metadata_validation_checks_provenance_and_helper_contract(
    monkeypatch, tmp_path: Path
):
    package = tmp_path / "securewave-vpn-codex-local_4.0.0+1_arm64.deb"
    package.write_bytes(b"test-package")
    source_sha = subprocess.run(
        ["git", "rev-parse", "HEAD"],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=True,
    ).stdout.strip()
    contract = (ROOT / "securewave_app/packaging/linux/securewave-wg-quick.contract").read_text(
        encoding="utf-8"
    ).strip()
    api_base = "http://127.0.0.1:18080/api"
    output = "\n".join(
        [
            f"package_filename={package.name}",
            "package=securewave-vpn-codex-local",
            "version=4.0.0+1",
            "architecture=arm64",
            "depends=wireguard-tools, libsecret-1-0",
            "contents_begin",
            *[f"./{path}" for path in codex_local_deb.REQUIRED_PACKAGE_CONTENTS],
            "contents_end",
            f"provenance_source-sha={source_sha}",
            "provenance_source-tree-state=clean",
            "provenance_app-version=4.0.0+1",
            "provenance_package-architecture=arm64",
            "provenance_package-profile=codex-local",
            f"provenance_api-base-fingerprint={fingerprint_api_base(api_base)}",
            f"provenance_helper-contract={contract}",
        ]
    )
    monkeypatch.setattr(
        codex_local_deb,
        "_run_docker",
        lambda _arguments, timeout: subprocess.CompletedProcess(
            args=[], returncode=0, stdout=output, stderr=""
        ),
    )
    monkeypatch.setattr(codex_local_deb, "_application_version", lambda: "4.0.0+1")

    evidence = codex_local_deb._validate_package(api_base, tmp_path, source_sha)

    assert evidence["package"] == "securewave-vpn-codex-local"
    assert evidence["architecture"] == "arm64"
    assert evidence["profile"] == "codex-local"
    assert evidence["depends_libsecret"] is True
    assert evidence["mock_api"] is False


def test_controller_exposes_local_deb_as_fixed_operation(monkeypatch, tmp_path: Path):
    monkeypatch.setattr(codex_cli_controller, "_evidence_dir", lambda _path: tmp_path)
    monkeypatch.setattr(
        codex_cli_controller,
        "run_local_deb",
        lambda **_kwargs: ("LOCAL_PACKAGE_READY", tmp_path / "local-deb.json"),
    )
    monkeypatch.setattr(
        codex_cli_controller,
        "_write_controller_evidence",
        lambda _directory, _payload: tmp_path / "controller-result.json",
    )

    result = codex_cli_controller._local_deb(
        Namespace(
            api_base="http://127.0.0.1:18080/api",
            output_dir=tmp_path / "artifacts",
            evidence_dir=tmp_path / "evidence",
        )
    )

    assert result == 0


def test_controller_parser_has_no_builder_image_or_command_passthrough():
    parser = codex_cli_controller._build_parser()
    args = parser.parse_args(
        [
            "local-deb",
            "--api-base",
            "http://127.0.0.1:18080/api",
            "--output-dir",
            "/tmp/securewave-local-artifacts",
            "--evidence-dir",
            "/tmp/securewave-local-evidence",
        ]
    )

    assert args.command == "local-deb"
    assert not hasattr(args, "builder_image")
    assert not hasattr(args, "command_passthrough")
