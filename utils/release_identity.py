"""Resolve the deployed SecureWave release identity without exposing secrets."""

from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Tuple


PROJECT_ROOT = Path(__file__).resolve().parent.parent
RELEASE_METADATA_PATH = PROJECT_ROOT / ".release.json"


def _metadata() -> dict[str, str]:
    try:
        payload = json.loads(RELEASE_METADATA_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
    if not isinstance(payload, dict):
        return {}
    return {
        key: value.strip()
        for key, value in payload.items()
        if key in {"version", "commit"} and isinstance(value, str) and value.strip()
    }


def get_release_identity(default_version: str = "dev") -> Tuple[str, str]:
    """Return version and commit, preferring explicit environment values."""
    metadata = _metadata()
    version = os.getenv("APP_VERSION", "").strip() or metadata.get("version", default_version)
    commit = os.getenv("GIT_SHA", "").strip() or metadata.get("commit", "")
    return version, commit
