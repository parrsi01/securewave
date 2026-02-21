# VPN Profile & Credential Schema

Primary endpoints:
- `POST /api/vpn/profile`
- `GET /api/vpn/protocols`
- `POST /api/vpn/credentials/provision`
- `GET /api/vpn/credentials`
- `POST /api/vpn/credentials/{credential_id}/revoke`
- `POST /api/vpn/credentials/{credential_id}/rotate`

## `POST /api/vpn/profile` request
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

## `POST /api/vpn/profile` success (WireGuard)
```json
{
  "device_id": 123,
  "device_name": "Work Laptop",
  "device_type": "linux",
  "protocol": "wireguard",
  "server_id": "hel1-01",
  "server_location": "Helsinki, Finland",
  "key_version": 2,
  "issued_at": "2026-02-21T18:00:00+00:00",
  "expires_at": "2026-02-21T19:00:00+00:00",
  "wireguard_config": "[Interface]...",
  "profile": {
    "type": "wireguard",
    "wireguard_config": "[Interface]..."
  },
  "dns": {
    "mode": "tunnel",
    "servers": ["94.140.14.14", "94.140.15.15"],
    "ad_malware_blocking": "on",
    "enforcement": "config"
  },
  "kill_switch": {
    "mode": "enabled",
    "enforcement": "wg-quick hooks",
    "notes": "Linux WireGuard profiles include wg-quick iptables hooks for kill-switch behavior."
  },
  "peer_registered": true,
  "registration_status": "Peer registered"
}
```

## `POST /api/vpn/profile` success (OpenVPN mTLS)
```json
{
  "protocol": "openvpn",
  "profile": {
    "type": "openvpn",
    "auth_method": "mtls",
    "ovpn_config": "client\\n...",
    "username": "sw-ovpn-u12-d54-r3",
    "cert_serial": "13A2",
    "cert_fingerprint_sha256": "8f3..."
  }
}
```

## `POST /api/vpn/profile` success (IKEv2 EAP-TLS)
```json
{
  "protocol": "ikev2",
  "profile": {
    "type": "ikev2",
    "auth_method": "eap-tls",
    "server": "vpn.example.securewave",
    "remote_id": "vpn.example.securewave",
    "username": "sw-ikev2-u12-d54-r4",
    "ca_cert_pem": "-----BEGIN CERTIFICATE-----...",
    "client_pkcs12_base64": "MII...",
    "client_pkcs12_password": "x7...",
    "cert_serial": "219C",
    "cert_fingerprint_sha256": "91f..."
  }
}
```

## `POST /api/vpn/credentials/provision` request
```json
{
  "protocol": "openvpn",
  "device_name": "Work Laptop",
  "device_type": "windows",
  "server_id": "hel1-01",
  "rotate_if_exists": false
}
```

## `POST /api/vpn/credentials/provision` response
```json
{
  "status": "credential_provisioned",
  "credential": {
    "id": 77,
    "protocol": "openvpn",
    "credential_type": "client_certificate",
    "device_id": 123,
    "server_id": 4,
    "username": "sw-ovpn-u12-d123-r5",
    "cert_serial": "13A2",
    "cert_fingerprint_sha256": "8f3...",
    "profile_expires_at": "2026-03-23T18:00:00+00:00",
    "revoked_at": null,
    "revision": 5
  },
  "profile": {
    "type": "openvpn",
    "auth_method": "mtls",
    "ovpn_config": "client\\n..."
  }
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
