# SecureWave Multi-Node VPN Architecture

## Overview

SecureWave runs a fleet of VPN servers ("nodes") managed through a central
FastAPI backend. Each node runs WireGuard (primary), with optional OpenVPN and
IKEv2 support. The backend acts as the control plane: it stores node metadata,
monitors health, provisions client profiles, and routes users to the best
available node.

```
┌──────────────┐      ┌──────────────┐      ┌──────────────┐
│  VPN Node 1  │      │  VPN Node 2  │      │  VPN Node N  │
│  de-fra-1    │      │  de-nue-1    │      │  xx-yyy-N    │
│  WG + OVPN   │      │  WG + IKEv2  │      │  WG          │
└──────┬───────┘      └──────┬───────┘      └──────┬───────┘
       │                     │                     │
       └─────────────┬───────┘─────────────────────┘
                     │
              ┌──────┴───────┐
              │  Control     │
              │  Plane API   │
              │  (FastAPI)   │
              └──────┬───────┘
                     │
              ┌──────┴───────┐
              │  PostgreSQL  │
              │  / SQLite    │
              │  vpn_servers │
              └──────────────┘
```

## Node Registry

All nodes are stored in the `vpn_servers` table. Key fields:

| Column | Type | Purpose |
|--------|------|---------|
| `id` | int (PK) | Internal ID |
| `server_id` | string (unique) | Human-readable identifier, e.g. `de-fra-1` |
| `public_ip` | string | Node's public IPv4 address |
| `region` | string | Geographic region (Europe, Americas, Asia) |
| `wg_listen_port` | int | WireGuard UDP port (default 51820) |
| `load_score` | float | Composite load metric 0.0–1.0 |
| `status` | string | `provisioning`, `active`, `maintenance`, `offline`, `decommissioned` |
| `health_status` | string | `healthy`, `degraded`, `unstable`, `unhealthy`, `unreachable` |
| `last_health_check` | datetime | Timestamp of last health probe |
| `supports_wireguard` | bool | WireGuard capability flag |
| `supports_openvpn` | bool | OpenVPN capability flag |
| `supports_ikev2` | bool | IKEv2/IPsec capability flag |
| `tier_restriction` | string | `NULL` = all users, `premium` = premium only |

Full schema: [models/vpn_server.py](../models/vpn_server.py)

## Node Registration

### Bootstrap (dev/staging)

On startup, `services/server_bootstrap.py` seeds default server records. These
use placeholder keys and the control-plane IP. Suitable for development only.

### Manual (admin API)

```
POST /api/admin/servers
Authorization: Bearer <admin-token>

{
  "server_id": "fi-hel-1",
  "location": "Helsinki",
  "country": "Finland",
  "country_code": "FI",
  "city": "Helsinki",
  "region": "Europe",
  "hcloud_location": "hel1",
  "public_ip": "95.xxx.xxx.xxx",
  "wg_public_key": "<base64-key>",
  "wg_listen_port": 51820,
  "max_connections": 1000
}
```

### Automated (infrastructure sync)

For Hetzner deployments, run:

```bash
python3 infrastructure/hetzner/sync_vpn_servers.py
```

This queries the Hetzner Cloud API, provisions WireGuard on new VMs, and
registers them in the database.

## Load Score

Each node carries a composite `load_score` (0.0 = idle, 1.0 = saturated),
recomputed on every health update:

```
load_score = 0.4 × cpu_load + 0.3 × memory_usage + 0.3 × (connections / max_connections)
```

Implementation: `VPNServer.compute_load_score()` in
[models/vpn_server.py](../models/vpn_server.py).

The score is persisted in the database and returned by the public server list
API, enabling clients to display load indicators and the backend to prefer
lightly loaded nodes during auto-selection.

## Health Monitoring

Health checks run via:

1. **Background task** — periodic probe of all active nodes
2. **Admin trigger** — `POST /api/admin/servers/{server_id}/health-check`
3. **Fleet-wide** — `POST /api/admin/servers/health-check-all`

Each check updates `health_status` and `consecutive_health_failures`. After 3
consecutive failures, a node is marked `unhealthy` and excluded from
auto-selection.

## Public API

### `GET /api/vpn/servers`

Returns available nodes for the authenticated user, filtered by subscription
tier. Sorted by `load_score` ascending (least loaded first).

Response fields per node:

```json
{
  "server_id": "de-fra-1",
  "location": "Frankfurt",
  "country": "Germany",
  "country_code": "DE",
  "city": "Frankfurt",
  "region": "Europe",
  "load_score": 0.12,
  "load_percent": 8.5,
  "status": "active",
  "health_status": "healthy",
  "tier_restriction": null,
  "supported_protocols": ["wireguard", "openvpn"]
}
```

### `GET /api/vpn/servers/{server_id}`

Returns details for a single node, including real-time region health.

## Profile Generation & Server Selection

The profile endpoint (`POST /api/vpn/profile`) accepts an optional `server_id`:

- **Explicit selection** — client sends `server_id`, backend validates tier
  access and protocol support, then generates a profile for that node.
- **Auto-selection** — `server_id` omitted. Backend uses `VPNServerService
  .allocate_server_for_user()` which calls the latency optimizer and VPN
  optimizer to pick the best candidate. Falls back to the lowest-load
  available node.

The generated profile contains the selected node's public key, endpoint
(`public_ip:wg_listen_port`), and allowed IPs — everything the client needs
to establish the tunnel.

## Peer Registration on Nodes

When a profile is provisioned, the backend registers the client's WireGuard
public key on the target node via SSH:

```
wg set wg0 peer <client_pubkey> allowed-ips <client_ip>/32
```

This is managed by `WireGuardServerManager` in
[services/wireguard_server_manager.py](../services/wireguard_server_manager.py).

Peers are tracked in the `wireguard_peers` table with a `server_id` foreign
key linking each device to its assigned node.

## Adding a New Node (Checklist)

1. Provision VM (Hetzner `hcloud server create` or Terraform)
2. Install WireGuard, generate server keys
3. Configure `wg0.conf` with the server private key and listen port
4. Enable IP forwarding and NAT masquerade
5. Register the node via `POST /api/admin/servers` or infrastructure sync
6. Run `POST /api/admin/servers/{id}/health-check` to verify connectivity
7. Node appears in `GET /api/vpn/servers` and is available for client profiles

## Failover

Each node can declare a `failover_server_id`. When a node becomes unhealthy,
the profile endpoint automatically excludes it from candidates and existing
clients are expected to re-provision through the control plane (the app
detects handshake failures and calls `/api/vpn/profile` again).

## Security Considerations

- Server private keys are encrypted at rest (`wg_private_key_encrypted`)
  using Fernet with `WG_ENCRYPTION_KEY`.
- Peer registration uses SSH with a dedicated key (`WG_SSH_KEY_PATH`).
- The public API never exposes server private keys, SSH credentials, or
  internal IPs.
- Admin endpoints require `is_admin` flag on the user record.
- All API calls require authentication (JWT bearer token).

## Database Migrations

| Migration | Description |
|-----------|-------------|
| `0010` | Multi-protocol support columns |
| `0012` | Region group and priority columns |
| `0015` | `load_score` column |

Run migrations: `alembic upgrade head`
