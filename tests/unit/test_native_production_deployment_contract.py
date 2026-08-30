from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[2]


def test_native_deploy_writes_json_and_systemd_release_identity() -> None:
    script = (PROJECT_ROOT / "scripts" / "deploy_native_production.sh").read_text(
        encoding="utf-8"
    )

    assert '"$release/.release.json"' in script
    assert "APP_VERSION=%s\\nGIT_SHA=%s\\n" in script
    assert '"$release/.release.env"' in script


def test_native_production_requirements_cover_import_time_dependencies() -> None:
    requirements = (
        PROJECT_ROOT / "requirements_production.txt"
    ).read_text(encoding="utf-8").splitlines()

    assert "PyJWT==2.13.0" in requirements
    assert "pyotp==2.9.0" in requirements
    assert "Jinja2==3.1.6" in requirements


def test_native_deploy_prefers_shared_immutable_downloads() -> None:
    script = (PROJECT_ROOT / "scripts" / "deploy_native_production.sh").read_text(
        encoding="utf-8"
    )

    shared_source = 'download_source="$shared/downloads"'
    legacy_source = 'download_source="$previous/static/downloads"'
    assert shared_source in script
    assert legacy_source in script
    assert script.index(shared_source) < script.index(legacy_source)


def test_native_deploy_retries_service_startup_connection_refusals() -> None:
    script = (PROJECT_ROOT / "scripts" / "deploy_native_production.sh").read_text(
        encoding="utf-8"
    )
    workflow = (
        PROJECT_ROOT / ".github" / "workflows" / "deploy-production.yml"
    ).read_text(encoding="utf-8")

    assert script.count("--retry-connrefused") >= 2
    assert "--retry-connrefused" in workflow
