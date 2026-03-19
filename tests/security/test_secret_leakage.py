from __future__ import annotations

import re
from pathlib import Path

from config.security_config import redact_env_mapping
from utils.structured_logging import sanitize_value


REPO_ROOT = Path(__file__).resolve().parents[2]
TRACKED_ENV_EXAMPLES = (
    REPO_ROOT / ".env.example",
    REPO_ROOT / ".env.example.backend",
    REPO_ROOT / ".env.production.example",
    REPO_ROOT / ".env.example.flutter",
)
SENSITIVE_REPO_PATHS = (
    REPO_ROOT / ".env",
    REPO_ROOT / ".env.hetzner",
    REPO_ROOT / "securewave_private" / "keys_and_storage_configurations" / ".env.keys",
    REPO_ROOT / "securewave_private" / "keys_and_storage_configurations" / ".env.production",
)
SECRET_PATTERNS = (
    re.compile(r"sk_live_[0-9A-Za-z]{16,}"),
    re.compile(r"sk_test_[0-9A-Za-z]{16,}"),
    re.compile(r"whsec_[0-9A-Za-z]{16,}"),
    re.compile(r"JWT_SECRET\s*=\s*[A-Za-z0-9_-]{16,}"),
    re.compile(r"SECRET_KEY\s*=\s*[A-Za-z0-9_-]{16,}"),
)


def test_secret_bearing_env_files_are_not_kept_in_repo_tree():
    leaked = [str(path.relative_to(REPO_ROOT)) for path in SENSITIVE_REPO_PATHS if path.exists()]
    assert leaked == []


def test_env_examples_do_not_contain_live_secret_literals():
    for path in TRACKED_ENV_EXAMPLES:
        content = path.read_text(encoding="utf-8")
        for pattern in SECRET_PATTERNS:
            assert pattern.search(content) is None, f"{path} matched {pattern.pattern}"


def test_log_and_env_redaction_cover_secret_values():
    env = {
        "JWT_SECRET": "super-secret-value",
        "STRIPE_SECRET_KEY": "sk_test_fixture1",
        "NORMAL_FLAG": "enabled",
    }
    redacted = redact_env_mapping(env)
    assert redacted["JWT_SECRET"] == "[redacted]"
    assert redacted["STRIPE_SECRET_KEY"] == "[redacted]"
    assert redacted["NORMAL_FLAG"] == "enabled"

    assert sanitize_value("message", "Authorization: Bearer abc.def.ghi") == "Authorization: Bearer [redacted]"
    assert sanitize_value("message", "email=tester@example.com") == "email=[redacted-email]"
