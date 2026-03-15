# VPN Multi-Server Failover Design

## Overview

When a client requests a VPN profile, the response includes a **primary server**
plus up to **2 backup endpoints** (failover nodes). If the primary server
becomes unreachable, the client can reconnect to a backup without requesting a
new profile.

Implementation:
- Selection logic: [`routes/vpn.py` — `select_failover_servers()`](../routes/vpn.py)
- Ranking engine: [`services/server_ranker.py`](../services/server_ranker.py)

## Profile Response Structure

```jsonc
{
  "server_id": "de-fra-1",
  "server_location": "Frankfurt, Germany",
  "wireguard_config": "...",          // primary server only
  "failover_endpoints": [
    {
      "server_id": "de-nue-1",
      "endpoint": "49.13.x.x:51820",
      "public_key": "abc123==",
      "location": "Nuremberg, Germany"
    },
    {
      "server_id": "fi-hel-1",
      "endpoint": "65.108.x.x:51820",
      "public_key": "def456==",
      "location": "Helsinki, Finland"
    }
  ]
}
```

### Why metadata instead of multiple `[Peer]` sections?

WireGuard's INI config format supports only **one `Endpoint`** per `[Peer]`
block. Embedding multiple endpoints in the `.conf` file is not possible without
non-standard extensions. Instead, failover endpoints are delivered as structured
JSON metadata alongside the config. The client switches endpoints by rewriting
the `Endpoint =` line in the active config and restarting the tunnel.

## Backup Selection Algorithm

Backups are selected using the same weighted ranking as primary selection
(see [server_selection_algorithm.md](server_selection_algorithm.md)):

```
composite_score = 0.50 × latency_score + 0.30 × load_score_inv + 0.20 × region_score
```

The primary server is excluded from the candidate list, then the remaining
servers are ranked. The top N (default 2, configurable via
`MAX_FAILOVER_ENDPOINTS`) become the failover endpoints.

### Selection flow

```
candidates (all active, tier-filtered servers)
  │
  ├── primary = select_best(candidates, region_hint)
  │
  └── others = candidates − {primary}
        │
        └── ranked = rank_servers(others, region_hint)
              │
              └── failover_endpoints = ranked[:MAX_FAILOVER_ENDPOINTS]
```

## Client Failover Behaviour

The client should implement the following reconnection logic:

| Event | Action |
|-------|--------|
| WireGuard handshake timeout (≥ 25 s) | Switch to `failover_endpoints[0]` |
| Second consecutive handshake failure | Switch to `failover_endpoints[1]` |
| All endpoints exhausted | Request a fresh profile from the API |
| Successful handshake on backup | Stay on backup until next profile refresh |

### Reconnection steps (WireGuard)

1. Detect handshake failure (latest handshake timestamp not advancing).
2. Pick next failover endpoint from the list.
3. Update the active tunnel config:
   ```bash
   wg set wg0 peer <current_pubkey> remove
   wg set wg0 peer <backup_pubkey> endpoint <backup_endpoint> \
       allowed-ips 0.0.0.0/0,::/0
   ```
4. Or restart via `wg-quick`:
   - Rewrite `Endpoint =` and `PublicKey =` in the `.conf` file.
   - `wg-quick down wg0 && wg-quick up wg0`

### Reconnection steps (OpenVPN / IKEv2)

For non-WireGuard protocols, the client uses the failover endpoint list to
construct a new connection attempt with the backup server's address. The
authentication credentials remain valid across all servers in the fleet.

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `MAX_FAILOVER_ENDPOINTS` | 2 | Number of backup endpoints per profile |

The constant is defined at the top of `routes/vpn.py`.

## Security Considerations

- Failover endpoints expose **public keys** and **public IPs** only — no
  private keys or credentials are included.
- Each backup endpoint's `public_key` is the server's WireGuard public key,
  already present in the server registry.
- Clients must validate that failover endpoints match the trusted server fleet
  before connecting (e.g. by pinning known public keys).

## Edge Cases

| Scenario | Behaviour |
|----------|-----------|
| Fleet has only 1 server | `failover_endpoints` is empty `[]` |
| Fleet has 2 servers | 1 failover endpoint returned |
| Primary server is the only healthy one | Backups may include degraded servers |
| All servers offline | Profile request fails with 503 before failover is relevant |
| Region hint provided | Backups prefer same-region servers via ranking weights |
