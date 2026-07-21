from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
COLLECTOR = ROOT / "scripts" / "collect_linux_tester_diagnostics.sh"
RUNBOOK = ROOT / "docs" / "LINUX_WIREGUARD_PRERELEASE_TESTER_RUNBOOK.md"
BUILDER = ROOT / "securewave_app" / "scripts" / "build_deb.sh"
ARM64_WORKFLOW = ROOT / ".github" / "workflows" / "linux-arm64-deb-release.yml"


def test_collector_is_allowlisted_and_never_captures_secret_sources():
    source = COLLECTOR.read_text()
    forbidden = (
        "printenv",
        "env >",
        "journalctl",
        "wg show sw-wg dump",
        "wg showconf",
        "/home/",
        "Authorization",
        "access_token",
        "refresh_token",
        "PrivateKey",
    )
    assert all(value not in source for value in forbidden)
    assert "latest-handshakes" in source
    assert "wg show sw-wg transfer" in source
    assert "package_sha256" in source


def test_collector_rejects_checksum_and_architecture_mismatch():
    source = COLLECTOR.read_text()
    assert 'actual_checksum" != "$expected_checksum' in source
    assert 'package_arch" != "$host_arch' in source
    assert "^(amd64|arm64)$" in source


def test_collector_libc_probe_is_pipefail_safe():
    source = COLLECTOR.read_text()

    assert "ldd --version 2>&1 | head" not in source
    assert "ldd --version 2>&1 | sed -n" in source


def test_arm64_package_evidence_uses_native_pinned_lifecycle_gate():
    source = ARM64_WORKFLOW.read_text()

    assert "runs-on: ubuntu-24.04-arm" in source
    assert "actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0" in source
    assert "actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a" in source
    assert "ff37bef603469fb030f2b72995ab929ccfc227f0" in source
    assert "https://github.com/flutter/flutter.git" in source
    assert "subosito/flutter-action" not in source
    assert "SOURCE_SHA: ${{ github.event.pull_request.head.sha || github.sha }}" in source
    assert "ref: ${{ github.event.pull_request.head.sha || github.sha }}" in source
    assert 'source-sha\")\" = \"$SOURCE_SHA\"' in source
    assert 'test "$(uname -m)" = "aarch64"' in source
    assert 'test "$(dpkg --print-architecture)" = "arm64"' in source
    assert 'Architecture)" = "arm64"' in source
    assert "ELF 64-bit LSB pie executable, ARM aarch64" in source
    assert "Install, launch, verify, purge, and inspect cleanup" in source
    assert "source-tree-state" in source
    assert 'helper-contract")" = "13"' in source
    assert "openvpn strongswan network-manager" in source
    assert 'SUDO_USER="$USER"' in source
    assert "malformed helper IPC was not rejected" in source
    assert "unauthorized helper IPC was not rejected" in source
    assert "securewave-vpn-predecessor.deb" in source
    assert "Version: 4.0.0+2" in source
    assert "sudo apt-get remove -y securewave-vpn" in source


def test_both_architecture_gates_cover_install_restart_upgrade_remove_and_purge():
    for name in ("linux-x64-deb-release.yml", "linux-arm64-deb-release.yml"):
        source = (ROOT / ".github" / "workflows" / name).read_text()
        for marker in (
            'sudo env SUDO_USER="$USER" dpkg -i "$DEB_OUTPUT"',
            "sudo systemctl restart securewave-helper.service",
            "sudo apt-get remove -y securewave-vpn",
            'dpkg -i "$predecessor_deb"',
            "sudo apt-get purge -y securewave-vpn",
        ):
            assert marker in source


def test_package_embeds_release_identity_and_dirty_tree_marker():
    source = BUILDER.read_text()
    for name in (
        "source-sha",
        "app-version",
        "package-architecture",
        "helper-contract",
        "source-tree-state",
    ):
        assert name in source
    assert source.index('source_tree_state="clean"') < source.index("flutter pub get")
    assert source.count("':(exclude)artifacts/**'") == 2


def test_x64_evidence_workflow_does_not_mutate_tree_before_packager_snapshot():
    source = (
        ROOT / ".github" / "workflows" / "linux-x64-deb-release.yml"
    ).read_text()
    build_step = source.split("- name: Build Linux x64 deb", maxsplit=1)[1].split(
        "- name: Collect generated deb", maxsplit=1
    )[0]

    assert "flutter pub get" not in build_step
    assert "bash scripts/build_deb.sh" in build_step


def test_x64_evidence_host_has_runtime_verifier_tools_not_package_dependencies():
    source = (
        ROOT / ".github" / "workflows" / "linux-x64-deb-release.yml"
    ).read_text()
    install_step = source.split(
        "- name: Install Linux build and runtime dependency set", maxsplit=1
    )[1].split("- name: Set up Flutter", maxsplit=1)[0]
    metadata_step = source.split(
        "- name: Verify helper payload and dependency metadata", maxsplit=1
    )[1].split(
        "- name: Install, launch, verify, purge, and inspect cleanup", maxsplit=1
    )[0]

    assert "network-manager" in install_step
    assert "forbidden in openvpn strongswan network-manager" in metadata_step


def test_x64_evidence_allows_only_absent_legacy_protocol_prerequisites():
    source = (
        ROOT / ".github" / "workflows" / "linux-x64-deb-release.yml"
    ).read_text()
    lifecycle_step = source.split(
        "- name: Install, launch, verify, purge, and inspect cleanup", maxsplit=1
    )[1].split("- name: Check manifest syntax and status", maxsplit=1)[0]

    assert "allowed_unavailable_secondary_protocol_checks" in lifecycle_step
    for check in (
        "tool:openvpn",
        "tool:charon-nm",
        "tool:nm-strongswan-service.name",
        "tool:libstrongswan-eap-mschapv2.so",
        "privilege:strongswan_routing_config",
    ):
        assert check in lifecycle_step
    assert "unexpected_failures" in lifecycle_step


def test_runbook_covers_wireguard_tester_acceptance_without_production():
    source = RUNBOOK.read_text()
    required = (
        "Ubuntu/Debian",
        "amd64",
        "arm64",
        "SHA256",
        "securewave-helper.service",
        "/run/securewave/helper.sock",
        "contract exactly `13`",
        "authorized staging API",
        "create exactly one",
        "device count remains one",
        "sw-wg",
        "latest-handshakes",
        "table 51820",
        "resolvectl",
        "HTTPS",
        "usage gauge",
        "Reconnect",
        "apt purge",
    )
    assert all(value in source for value in required)
    assert "Do not test production with this runbook" in source
