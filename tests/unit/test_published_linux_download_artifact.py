import json
import subprocess
from pathlib import Path


def test_published_linux_download_artifact_matches_package_contract():
    root = Path(__file__).resolve().parents[2]
    manifest_path = root / "static" / "downloads" / "version.json"
    verify_script = root / "securewave_app" / "scripts" / "verify_linux_package_artifact.sh"

    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    linux_artifacts = [
        artifact
        for artifact in manifest.get("artifacts", [])
        if isinstance(artifact, dict)
        and str(artifact.get("platform", "")).lower() == "linux"
        and str(artifact.get("status", "")).lower() == "available"
        and str(artifact.get("format", "")).lower() == "deb"
        and str(artifact.get("filename") or "").strip()
    ]

    assert linux_artifacts, "Expected at least one published Linux .deb artifact."

    for artifact in linux_artifacts:
        package_path = (root / "static" / "downloads" / artifact["filename"]).resolve()
        assert package_path.is_file(), f"Published Linux package missing: {package_path}"
        result = subprocess.run(
            ["bash", str(verify_script), str(package_path)],
            cwd=root,
            capture_output=True,
            text=True,
            check=False,
        )
        assert result.returncode == 0, result.stdout + "\n" + result.stderr
