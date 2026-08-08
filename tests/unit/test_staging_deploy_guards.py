import os
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def test_staging_deploy_requires_explicit_inputs():
    env = os.environ.copy()
    env.pop("SECUREWAVE_STAGING_HOST", None)
    env.pop("SECUREWAVE_STAGING_IMAGE", None)
    env.pop("SECUREWAVE_STAGING_USER", None)
    env.pop("SECUREWAVE_STAGING_REMOTE_APP_DIR", None)
    env.pop("CONFIRM_DEPLOY", None)
    completed = subprocess.run(
        ["bash", "scripts/deploy_staging.sh"],
        cwd=ROOT,
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )
    assert completed.returncode == 2
    assert "SECUREWAVE_STAGING_HOST" in completed.stderr
    assert "staging-fleet" not in completed.stderr


def test_compose_defaults_to_production_and_accepts_explicit_environment():
    compose = (ROOT / "deploy/hetzner/compose.yaml").read_text(encoding="utf-8")
    assert "ENVIRONMENT: ${SECUREWAVE_ENVIRONMENT:-production}" in compose
    assert 'DEMO_MODE: "false"' in compose
    assert 'WG_MOCK_MODE: "false"' in compose


def _staging_env() -> dict[str, str]:
    env = os.environ.copy()
    env.update(
        {
            "SECUREWAVE_STAGING_HOST": "staging-fleet-01.example.test",
            "SECUREWAVE_STAGING_IMAGE": "registry.example.test/securewave@sha256:" + "a" * 64,
            "SECUREWAVE_STAGING_USER": "securewave",
            "SECUREWAVE_STAGING_REMOTE_APP_DIR": "/opt/securewave",
            "CONFIRM_DEPLOY": "securewave-staging",
        }
    )
    return env


def test_staging_rejects_local_or_url_shaped_host():
    env = _staging_env()
    env["SECUREWAVE_STAGING_HOST"] = "https://staging.example.test"
    completed = subprocess.run(
        ["bash", "scripts/deploy_staging.sh"],
        cwd=ROOT,
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )
    assert completed.returncode == 2
    assert "SECUREWAVE_STAGING_HOST" in completed.stderr
    assert "Staging deployment started" not in completed.stdout


def test_staging_rejects_mutable_image_tag():
    env = _staging_env()
    env["SECUREWAVE_STAGING_IMAGE"] = "registry.example.test/securewave:latest"
    completed = subprocess.run(
        ["bash", "scripts/deploy_staging.sh"],
        cwd=ROOT,
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )
    assert completed.returncode == 2
    assert "complete sha256 digest" in completed.stderr


def test_staging_requires_signed_approval_inputs_after_image_validation():
    env = _staging_env()
    env["SECUREWAVE_DEPLOY_TARGET_REFERENCE"] = "staging-fleet-01"
    completed = subprocess.run(
        ["bash", "scripts/deploy_staging.sh"],
        cwd=ROOT,
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )
    assert completed.returncode == 2
    assert "staging approval variable" in completed.stderr
    assert "Staging deployment started" not in completed.stdout


def test_production_wrapper_remains_fail_closed_without_confirmation():
    env = os.environ.copy()
    env.update(
        {
            "SECUREWAVE_PRODUCTION_HOST": "production-fleet-01.example.test",
            "SECUREWAVE_PRODUCTION_IMAGE": "registry.example.test/securewave:release-20260807",
        }
    )
    env.pop("CONFIRM_DEPLOY", None)
    completed = subprocess.run(
        ["bash", "scripts/deploy_production.sh"],
        cwd=ROOT,
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )
    assert completed.returncode == 2
    assert "CONFIRM_DEPLOY" in completed.stderr
    assert "Production deployment started" not in completed.stdout
