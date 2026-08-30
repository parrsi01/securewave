"""Shared application release metadata for backend and website surfaces."""

import os


DEFAULT_APP_VERSION = "4.0.0+10"


def get_app_version() -> str:
    """Return an operator override or the source-controlled release version."""
    configured = os.getenv("APP_VERSION", "").strip()
    return configured or DEFAULT_APP_VERSION
