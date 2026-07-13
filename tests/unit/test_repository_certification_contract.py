from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def test_pillow_security_floor_is_consistent() -> None:
    for requirements_file in ("requirements.txt", "requirements_production.txt"):
        requirements = (ROOT / requirements_file).read_text(encoding="utf-8")
        assert "pillow==12.3.0" in requirements
        assert "pillow==12.2.0" not in requirements


def test_local_certification_is_platform_aware() -> None:
    script = (ROOT / "scripts/certify_repository.sh").read_text(encoding="utf-8")

    assert "mktemp --suffix" not in script
    assert 'migration_dir="$(mktemp -d -t securewave-certification)"' in script
    assert '[[ "$(uname -s)" == "Linux" ]]' in script
    assert "ANDROID_HOME" in script
    assert "ANDROID_SDK_ROOT" in script
