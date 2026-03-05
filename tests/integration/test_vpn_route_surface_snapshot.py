from __future__ import annotations


EXPECTED_VPN_ROUTE_SURFACE = {
    ("POST", "/api/vpn/allocate"),
    ("GET", "/api/vpn/config"),
    ("GET", "/api/vpn/config/download/{server_id}"),
    ("GET", "/api/vpn/config/qr/{server_id}"),
    ("POST", "/api/vpn/connect"),
    ("POST", "/api/vpn/create-device"),
    ("GET", "/api/vpn/credentials"),
    ("POST", "/api/vpn/credentials/provision"),
    ("POST", "/api/vpn/credentials/{credential_id}/revoke"),
    ("POST", "/api/vpn/credentials/{credential_id}/rotate"),
    ("GET", "/api/vpn/debug/server-health/{server_id}"),
    ("POST", "/api/vpn/dev/region-health"),
    ("GET", "/api/vpn/devices"),
    ("POST", "/api/vpn/devices"),
    ("GET", "/api/vpn/devices/limits/info"),
    ("DELETE", "/api/vpn/devices/{device_id}"),
    ("GET", "/api/vpn/devices/{device_id}"),
    ("PATCH", "/api/vpn/devices/{device_id}"),
    ("GET", "/api/vpn/devices/{device_id}/config"),
    ("GET", "/api/vpn/devices/{device_id}/config/download"),
    ("POST", "/api/vpn/devices/{device_id}/rotate-keys"),
    ("PUT", "/api/vpn/devices/{device_id}/server"),
    ("GET", "/api/vpn/devices/{device_id}/usage"),
    ("POST", "/api/vpn/disconnect"),
    ("GET", "/api/vpn/download-config"),
    ("GET", "/api/vpn/health"),
    ("POST", "/api/vpn/meter/start"),
    ("POST", "/api/vpn/meter/stop"),
    ("GET", "/api/vpn/meter/usage/{user_id}"),
    ("GET", "/api/vpn/metrics/vpn"),
    ("GET", "/api/vpn/my-configs"),
    ("POST", "/api/vpn/profile"),
    ("GET", "/api/vpn/protocol-capabilities"),
    ("GET", "/api/vpn/protocol-health"),
    ("GET", "/api/vpn/protocols"),
    ("GET", "/api/vpn/recommended-server"),
    ("GET", "/api/vpn/regions"),
    ("GET", "/api/vpn/resolve-region"),
    ("POST", "/api/vpn/revoke-device"),
    ("GET", "/api/vpn/servers"),
    ("GET", "/api/vpn/servers/{server_id}"),
    ("POST", "/api/vpn/shaping/start"),
    ("POST", "/api/vpn/shaping/stop"),
    ("POST", "/api/vpn/simulate/failures"),
    ("POST", "/api/vpn/simulate/traffic"),
    ("GET", "/api/vpn/status"),
    ("GET", "/api/vpn/tests/history"),
    ("GET", "/api/vpn/tests/latest"),
    ("GET", "/api/vpn/tests/latest/full"),
    ("POST", "/api/vpn/tests/run"),
    ("POST", "/api/vpn/tests/run/sync"),
    ("GET", "/api/vpn/tests/status"),
    ("GET", "/api/vpn/usage"),
}


def _format_surface_diff(label: str, entries: set[tuple[str, str]]) -> str:
    if not entries:
        return f"{label}: none"
    formatted = "\n".join(f"  - {method} {path}" for method, path in sorted(entries))
    return f"{label}:\n{formatted}"


def test_vpn_route_surface_matches_snapshot(client):
    schema = client.app.openapi()
    actual = {
        (method.upper(), path)
        for path, operations in schema.get("paths", {}).items()
        if path.startswith("/api/vpn/")
        for method in operations.keys()
    }

    missing = EXPECTED_VPN_ROUTE_SURFACE - actual
    unexpected = actual - EXPECTED_VPN_ROUTE_SURFACE

    assert not missing and not unexpected, (
        "Mounted /api/vpn route surface drifted.\n"
        f"{_format_surface_diff('Missing endpoints', missing)}\n"
        f"{_format_surface_diff('Unexpected endpoints', unexpected)}"
    )
