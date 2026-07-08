import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github/workflows/linux-deb-release.yml"
MANIFEST = ROOT / "static/downloads/manifest.json"


def test_linux_deb_release_workflow_is_manual_only():
    workflow = WORKFLOW.read_text()

    assert "workflow_dispatch:" in workflow
    assert "\n  push:" not in workflow
    assert "\n  pull_request:" not in workflow
    assert "git commit" not in workflow
    assert "git push" not in workflow
    assert "static/downloads" not in workflow
    assert "manifest.json" not in workflow


def test_linux_deb_release_workflow_supports_architecture_truth():
    workflow = WORKFLOW.read_text()

    assert "- x64" in workflow
    assert "- arm64" in workflow
    assert "ubuntu-latest" in workflow
    assert "ubuntu-24.04-arm" in workflow
    assert "expected_uname=\"x86_64\"" in workflow
    assert "expected_dpkg=\"amd64\"" in workflow
    assert "expected_uname=\"aarch64\"" in workflow
    assert "expected_dpkg=\"arm64\"" in workflow
    assert "uname -m" in workflow
    assert "dpkg --print-architecture" in workflow


def test_linux_deb_release_workflow_uploads_evidence_only():
    workflow = WORKFLOW.read_text()

    assert "bash scripts/build_deb.sh" in workflow
    assert "libsecret-1-dev" in workflow
    assert "securewave-linux-x64.deb" in workflow
    assert "securewave-linux-arm64.deb" in workflow
    assert ".sha256" in workflow
    assert ".dpkg-info.txt" in workflow
    assert ".dpkg-contents.txt" in workflow
    assert "evidence-summary.md" in workflow
    assert "actions/upload-artifact@v4" in workflow
    assert "does not commit artifacts" in workflow
    assert "mark manifest entries available" in workflow


def test_download_manifest_keeps_linux_debs_coming_soon():
    manifest = json.loads(MANIFEST.read_text())
    downloads = {
        (item["platform"], item["architecture"], item["filename"]): item
        for item in manifest["downloads"]
    }

    x64_deb = downloads[("linux", "x64", "securewave-linux-x64.deb")]
    assert x64_deb["status"] == "coming_soon"

    assert ("linux", "arm64", "securewave-linux-arm64.deb") not in downloads
