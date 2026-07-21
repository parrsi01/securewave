from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
COLLECTOR = ROOT / "scripts" / "collect_linux_tester_diagnostics.sh"
RUNBOOK = ROOT / "docs" / "LINUX_WIREGUARD_PRERELEASE_TESTER_RUNBOOK.md"
BUILDER = ROOT / "securewave_app" / "scripts" / "build_deb.sh"


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


def test_x64_evidence_workflow_does_not_mutate_tree_before_packager_snapshot():
    source = (
        ROOT / ".github" / "workflows" / "linux-x64-deb-release.yml"
    ).read_text()
    build_step = source.split("- name: Build Linux x64 deb", maxsplit=1)[1].split(
        "- name: Collect generated deb", maxsplit=1
    )[0]

    assert "flutter pub get" not in build_step
    assert "bash scripts/build_deb.sh" in build_step


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
