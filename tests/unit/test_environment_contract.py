from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def test_environment_examples_use_runtime_provider_names():
    production = (ROOT / ".env.production.example").read_text(encoding="utf-8")
    template = (ROOT / ".env.template").read_text(encoding="utf-8")

    assert "STRIPE_SECRET_KEY=" in production
    assert "STRIPE_SECRET=" not in production
    assert "EMAIL_PROVIDER=sendgrid" in production
    assert "APP_URL=" in production
    assert "APP_BASE_URL=" not in production
    assert "STRIPE_SECRET_KEY=" in template
    assert "STRIPE_SECRET=" not in template
