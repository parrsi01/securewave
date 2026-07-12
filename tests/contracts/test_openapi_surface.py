"""Reviewable lock for the public auth, device, VPN, usage, and download API."""

from main import app


EXPECTED_METHODS = {
    "/api/auth/register": {"post"},
    "/api/auth/login": {"post"},
    "/api/auth/logout": {"post"},
    "/api/auth/refresh": {"post"},
    "/api/auth/session": {"get"},
    "/api/vpn/profile": {"post"},
    "/api/vpn/devices": {"get", "post"},
    "/api/vpn/devices/{device_id}": {"get", "patch", "delete"},
    "/api/vpn/devices/{device_id}/rotate-keys": {"post"},
    "/api/vpn/protocols": {"get"},
    "/api/vpn/usage/sessions/start": {"post"},
    "/api/vpn/usage/sessions/{session_id}/increment": {"post"},
    "/api/vpn/usage/sessions/{session_id}/disconnect": {"post"},
    "/api/downloads": {"get"},
    "/api/downloads/detect": {"get"},
    "/api/downloads/file/{filename}": {"get"},
}

EXPECTED_JSON_BODY_REFS = {
    ("/api/auth/register", "post"): "#/components/schemas/RegisterRequest",
    ("/api/auth/login", "post"): "#/components/schemas/LoginRequest",
    ("/api/vpn/profile", "post"): "#/components/schemas/VpnProfileRequest",
    ("/api/vpn/devices", "post"): "#/components/schemas/DeviceCreate",
    ("/api/vpn/devices/{device_id}", "patch"): "#/components/schemas/DeviceRename",
    ("/api/vpn/usage/sessions/start", "post"): "#/components/schemas/UsageSessionStartRequest",
    ("/api/vpn/usage/sessions/{session_id}/increment", "post"): "#/components/schemas/UsageIncrementRequest",
    ("/api/vpn/usage/sessions/{session_id}/disconnect", "post"): "#/components/schemas/UsageFinalizeRequest",
}

REQUIRED_RESPONSE_SCHEMAS = {
    "DownloadEntry",
    "DownloadListResponse",
    "PlatformDetectResponse",
    "DeviceCreate",
    "DeviceRename",
    "DeviceResponse",
    "UsageSessionStartRequest",
    "UsageIncrementRequest",
    "UsageFinalizeRequest",
    "VpnProfileRequest",
    "VpnProfileResponse",
    "VpnProtocolAvailability",
    "VpnProtocolsResponse",
}


def _http_methods(path_item: dict) -> set[str]:
    return set(path_item) & {"get", "post", "put", "patch", "delete"}


def test_critical_public_path_and_method_surface_is_stable():
    schema = app.openapi()

    for path, expected_methods in EXPECTED_METHODS.items():
        assert path in schema["paths"], f"public API path removed: {path}"
        assert _http_methods(schema["paths"][path]) == expected_methods


def test_critical_json_request_schema_names_are_stable():
    schema = app.openapi()

    for (path, method), expected_ref in EXPECTED_JSON_BODY_REFS.items():
        body_schema = schema["paths"][path][method]["requestBody"]["content"]["application/json"]["schema"]
        assert body_schema == {"$ref": expected_ref}


def test_critical_response_schema_names_and_status_codes_are_stable():
    schema = app.openapi()
    components = set(schema["components"]["schemas"])

    assert REQUIRED_RESPONSE_SCHEMAS <= components
    assert set(schema["paths"]["/api/auth/register"]["post"]["responses"]) == {"201", "422"}
    assert set(schema["paths"]["/api/vpn/devices"]["post"]["responses"]) == {"201", "422"}
    assert set(schema["paths"]["/api/vpn/devices/{device_id}"]["delete"]["responses"]) == {"204", "422"}
    assert set(schema["paths"]["/api/downloads"]["get"]["responses"]) == {"200"}
