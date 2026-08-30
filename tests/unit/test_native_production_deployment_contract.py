from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[2]


def test_native_deploy_writes_json_and_systemd_release_identity() -> None:
    script = (PROJECT_ROOT / "scripts" / "deploy_native_production.sh").read_text(
        encoding="utf-8"
    )

    assert '"$release/.release.json"' in script
    assert "APP_VERSION=%s\\nGIT_SHA=%s\\n" in script
    assert '"$release/.release.env"' in script
