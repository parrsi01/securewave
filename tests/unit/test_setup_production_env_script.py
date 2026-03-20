from __future__ import annotations

import os
import stat
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def test_setup_production_env_writes_sourceable_file_with_generated_keys(
    tmp_path: Path,
) -> None:
    output_file = tmp_path / "securewave-release.env"

    result = subprocess.run(
        ["/bin/bash", "scripts/setup_production_env.sh", "--write-env-file", str(output_file)],
        cwd=ROOT,
        env={"PATH": os.environ["PATH"]},
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0, result.stderr
    assert output_file.exists()
    assert stat.S_IMODE(output_file.stat().st_mode) == 0o600

    content = output_file.read_text(encoding="utf-8")
    assert "export ENVIRONMENT=production" in content
    assert "export EMAIL_PROVIDER=" in content
    assert "export AUTH_ENCRYPTION_KEY=" in content
    assert "export WG_ENCRYPTION_KEY=" in content
    assert "# TODO: export STRIPE_SECRET_KEY=" in content
    assert "# TODO: export DATABASE_URL=" in content


def test_setup_production_env_preserves_existing_values() -> None:
    env = os.environ.copy()
    env.update(
        {
            "EMAIL_PROVIDER": "smtp",
            "DATABASE_URL": "postgresql+psycopg2://securewave:password@db.example.com:5432/securewave",
            "FROM_EMAIL": "ops@securewave.app",
            "AUTH_ENCRYPTION_KEY": "7jD1VRkjC3w69CxKkhj4ZmVn4-mp3ce6sUj7nXf9CBk=",
            "WG_ENCRYPTION_KEY": "K2yI29Q6aGmGVQ7Y4Y8CK7tt4FhTnms6yr7kyO4lVG4=",
            "STRIPE_SECRET_KEY": "sk_live_test",
            "STRIPE_PUBLISHABLE_KEY": "pk_live_test",
            "STRIPE_WEBHOOK_SECRET": "whsec_test",
            "STRIPE_PRICE_BASIC_MONTHLY": "price_basic",
            "STRIPE_PRICE_PREMIUM_MONTHLY": "price_premium",
            "STRIPE_PRICE_ULTRA_MONTHLY": "price_ultra",
        }
    )

    result = subprocess.run(
        ["/bin/bash", "scripts/setup_production_env.sh"],
        cwd=ROOT,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0, result.stderr
    assert "export DATABASE_URL=postgresql+psycopg2://securewave:password@db.example.com:5432/securewave" in result.stdout
    assert "export FROM_EMAIL=ops@securewave.app" in result.stdout
    assert "export STRIPE_SECRET_KEY=sk_live_test" in result.stdout
    assert "Generated AUTH_ENCRYPTION_KEY" not in result.stdout
