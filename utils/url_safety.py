from __future__ import annotations

from urllib.parse import urljoin, urlparse

from utils.api_errors import ApiException


def require_safe_redirect_url(*, base_url: str, candidate: str, field_name: str = "return_url") -> str:
    """
    Enforce that a redirect URL is same-origin (or a root-relative path).

    Stripe requires absolute URLs for success/cancel/return URLs. This helper allows
    callers to pass either:
    - "/path" (root-relative), which is normalized to an absolute URL using base_url
    - "https://<same-origin>/path" (absolute same-origin)
    """
    base = urlparse(base_url)
    if not base.scheme or not base.netloc:
        raise ApiException(
            status_code=500,
            code="invalid_base_url",
            message="Server misconfigured: base URL is invalid.",
        )

    raw = (candidate or "").strip()
    if not raw:
        raise ApiException(
            status_code=400,
            code="invalid_redirect_url",
            message=f"{field_name} is required.",
        )

    # Disallow schema-relative URLs.
    if raw.startswith("//"):
        raise ApiException(
            status_code=400,
            code="invalid_redirect_url",
            message=f"{field_name} must be same-origin or a root-relative path.",
        )

    parsed = urlparse(raw)
    if parsed.scheme or parsed.netloc:
        # Absolute URL: require same scheme + host.
        if parsed.scheme != base.scheme or parsed.netloc != base.netloc:
            raise ApiException(
                status_code=400,
                code="invalid_redirect_url",
                message=f"{field_name} must be same-origin.",
            )
        return raw

    # Relative URL: require root-relative path.
    if not raw.startswith("/"):
        raise ApiException(
            status_code=400,
            code="invalid_redirect_url",
            message=f"{field_name} must start with '/'.",
        )

    return urljoin(f"{base.scheme}://{base.netloc}", raw)

