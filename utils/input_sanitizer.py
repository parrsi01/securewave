"""
Input sanitization utilities for external-facing APIs.
"""

from __future__ import annotations

import re

from config.settings import get_settings

SAFE_IDENTIFIER_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:-]{1,63}$")
SAFE_REGION_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9 ._-]{1,63}$")
SAFE_DEVICE_NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9 ._\-()]{0,63}$")
SAFE_ENDPOINT_RE = re.compile(
    r"^([A-Za-z0-9.-]{1,253}|\[[0-9A-Fa-f:]+\]):([1-9][0-9]{0,4})$"
)
SAFE_ALLOWED_IPS_RE = re.compile(r"^[A-Za-z0-9:.,/\s]{3,128}$")
SAFE_WG_KEY_RE = re.compile(r"^[A-Za-z0-9+/=]{43,44}$")
SETTINGS = get_settings()


def normalize_whitespace(value: str) -> str:
    return " ".join(value.strip().split())


def sanitize_device_name(value: str) -> str:
    candidate = normalize_whitespace(value)
    if not SAFE_DEVICE_NAME_RE.fullmatch(candidate):
        raise ValueError(
            "device_name must start with an alphanumeric character and only include letters, "
            "numbers, spaces, dot, underscore, dash, and parentheses"
        )
    return candidate


def sanitize_identifier(value: str, *, field_name: str = "identifier") -> str:
    candidate = value.strip()
    if not SAFE_IDENTIFIER_RE.fullmatch(candidate):
        raise ValueError(
            f"{field_name} must be 2-64 chars and only include letters, numbers, dot, underscore, colon, and dash"
        )
    return candidate


def sanitize_region(value: str) -> str:
    candidate = normalize_whitespace(value)
    if not SAFE_REGION_RE.fullmatch(candidate):
        raise ValueError("region contains unsupported characters")
    return candidate


def sanitize_endpoint(value: str) -> str:
    candidate = value.strip()
    match = SAFE_ENDPOINT_RE.fullmatch(candidate)
    if not match:
        raise ValueError("endpoint must be host:port or [ipv6]:port")
    port = int(match.group(2))
    if port < 1 or port > 65535:
        raise ValueError("endpoint port out of range")
    return candidate


def sanitize_allowed_ips(value: str) -> str:
    candidate = normalize_whitespace(value)
    if not SAFE_ALLOWED_IPS_RE.fullmatch(candidate):
        raise ValueError("allowed_ips contains unsupported characters")
    return candidate


def sanitize_wireguard_key(value: str, *, field_name: str = "wg_key") -> str:
    candidate = value.strip()
    if not SAFE_WG_KEY_RE.fullmatch(candidate):
        if SETTINGS.testing:
            if re.fullmatch(r"^[A-Za-z0-9+/=]{16,128}$", candidate):
                return candidate
        raise ValueError(f"{field_name} must be a valid WireGuard base64 key")
    return candidate
