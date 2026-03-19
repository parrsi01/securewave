from __future__ import annotations

import os
import stat
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Mapping

from dotenv import load_dotenv


PROJECT_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_SHARED_ENV_FILES = (
    Path("/etc/securewave/env"),
    Path.home() / ".config" / "securewave" / "backend.env",
    Path.home() / ".config" / "securewave" / "secrets.env",
)
PROJECT_ENV_FILES = (
    PROJECT_ROOT / ".env.production",
    PROJECT_ROOT / ".env",
)

SENSITIVE_ENV_KEYS = frozenset(
    {
        "ACCESS_TOKEN_SECRET",
        "AUTH_ENCRYPTION_KEY",
        "AWS_SECRET_ACCESS_KEY",
        "DATABASE_URL",
        "HETZNER_API_TOKEN",
        "HCLOUD_TOKEN",
        "JWT_SECRET",
        "PAYPAL_CLIENT_SECRET",
        "REDIS_PASSWORD",
        "REDIS_URL",
        "REFRESH_TOKEN_SECRET",
        "SECRET_KEY",
        "SENDGRID_API_KEY",
        "SENTRY_DSN",
        "SMTP_PASSWORD",
        "STRIPE_PUBLISHABLE_KEY",
        "STRIPE_SECRET_KEY",
        "STRIPE_WEBHOOK_SECRET",
        "WG_API_KEY",
        "WG_ENCRYPTION_KEY",
        "WG_SSH_KEY_PATH",
    }
)

SENSITIVE_ENV_SUFFIXES = (
    "_API_KEY",
    "_CLIENT_SECRET",
    "_DSN",
    "_KEY",
    "_PASSWORD",
    "_SECRET",
    "_TOKEN",
)


@dataclass(frozen=True)
class PermissionResult:
    changed_paths: tuple[str, ...]
    warnings: tuple[str, ...]


def _clean(value: str | None) -> str | None:
    if value is None:
        return None
    cleaned = value.strip()
    return cleaned or None


def looks_like_sensitive_env_key(key: str) -> bool:
    normalized = key.strip().upper()
    if normalized in SENSITIVE_ENV_KEYS:
        return True
    return any(normalized.endswith(suffix) for suffix in SENSITIVE_ENV_SUFFIXES)


def redact_env_mapping(environ: Mapping[str, str]) -> dict[str, str]:
    redacted: dict[str, str] = {}
    for key, value in environ.items():
        redacted[key] = "[redacted]" if looks_like_sensitive_env_key(key) else value
    return redacted


def _path_exists(path: Path) -> bool:
    try:
        path.stat()
    except (FileNotFoundError, PermissionError, OSError):
        return False
    return True


def load_security_environment_files(
    *,
    project_root: Path | None = None,
    environ: Mapping[str, str] | None = None,
) -> tuple[str, ...]:
    resolved_project_root = project_root or PROJECT_ROOT
    env = environ or os.environ
    loaded: list[str] = []

    explicit_files: list[Path] = []
    for key in ("SECUREWAVE_ENV_FILE", "SECUREWAVE_SECRETS_FILE"):
        value = _clean(env.get(key))
        if value:
            explicit_files.append(Path(value).expanduser())

    for path in (*explicit_files, *DEFAULT_SHARED_ENV_FILES):
        if _path_exists(path):
            load_dotenv(path, override=False)
            loaded.append(str(path))

    # Project-local env files are allowed in non-production by default so
    # existing development flows and tests keep working. Production must opt in.
    environment = (_clean(os.environ.get("ENVIRONMENT")) or "").lower()
    allow_project_env = (_clean(os.environ.get("SECUREWAVE_ALLOW_PROJECT_ENV")) or "").lower() in {
        "1",
        "true",
        "yes",
        "on",
    }
    if environment != "production" or allow_project_env:
        for relative in PROJECT_ENV_FILES:
            path = relative if relative.is_absolute() else resolved_project_root / relative.name
            if _path_exists(path):
                load_dotenv(path, override=False)
                loaded.append(str(path))

    return tuple(dict.fromkeys(loaded))


def secret_file_candidates(*, project_root: Path | None = None) -> tuple[Path, ...]:
    root = project_root or PROJECT_ROOT
    candidates = [
        root / ".env",
        root / ".env.production",
        root / ".env.hetzner",
        root / "securewave_private" / "keys_and_storage_configurations" / ".env.keys",
        root / "securewave_private" / "keys_and_storage_configurations" / ".env.production",
        Path.home() / ".config" / "securewave" / "backend.env",
        Path.home() / ".config" / "securewave" / "secrets.env",
    ]
    return tuple(path for path in candidates if _path_exists(path))


def enforce_permission_policy(
    files: Iterable[Path],
    *,
    file_mode: int = 0o600,
    dir_mode: int = 0o700,
) -> PermissionResult:
    changed_paths: list[str] = []
    warnings: list[str] = []
    current_uid = os.getuid()

    for path in files:
        try:
            stat_result = path.stat()
        except FileNotFoundError:
            continue
        except OSError as exc:
            warnings.append(f"{path}: unable to inspect permissions ({exc})")
            continue

        if stat_result.st_uid != current_uid:
            warnings.append(f"{path}: owned by uid {stat_result.st_uid}, not updated")
            continue

        if path.is_dir():
            expected_mode = dir_mode
        else:
            expected_mode = file_mode

        current_mode = stat.S_IMODE(stat_result.st_mode)
        if current_mode == expected_mode:
            continue

        try:
            os.chmod(path, expected_mode)
            changed_paths.append(str(path))
        except OSError as exc:
            warnings.append(f"{path}: chmod failed ({exc})")

    return PermissionResult(tuple(changed_paths), tuple(warnings))
