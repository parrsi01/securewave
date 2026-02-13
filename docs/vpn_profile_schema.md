# VPN Profile Schema (`POST /api/vpn/profile`)

## Request
```json
{
  "device_id": 123,
  "device_name": "Work Laptop",
  "device_type": "linux",
  "protocol": "wireguard",
  "server_id": "hel1-01",
  "force_rotate_keys": false
}
```

## Success response
```json
{
  "device_id": 123,
  "device_name": "Work Laptop",
  "device_type": "linux",
  "protocol": "wireguard",
  "server_id": "hel1-01",
  "server_location": "Helsinki, Finland",
  "key_version": 2,
  "issued_at": "2026-02-12T01:00:00+00:00",
  "expires_at": "2026-02-12T02:00:00+00:00",
  "wireguard_config": "[Interface]...",
  "dns": {
    "mode": "tunnel",
    "servers": ["94.140.14.14", "94.140.15.15"],
    "ad_malware_blocking": "on",
    "enforcement": "config"
  },
  "kill_switch": {
    "mode": "enabled",
    "enforcement": "best effort",
    "notes": "Enable Always-on VPN / block-without-VPN where supported."
  },
  "peer_registered": true,
  "registration_status": "Peer registered"
}
```

## Error format
All API errors follow:
```json
{
  "error": {
    "code": "server_not_found",
    "message": "Server not found",
    "details": null
  },
  "request_id": "b5de..."
}
```
