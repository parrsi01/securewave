# Server Selection Algorithm

## Overview

When a client requests a VPN profile without specifying a `server_id` (auto
mode), the backend scores every eligible server and returns the best one.

The algorithm balances three factors:

| Factor | Weight | Why |
|--------|--------|-----|
| Latency | 50 % | Lowest round-trip time = best tunnel experience |
| Load | 30 % | Avoids packing users onto a saturated node |
| Region proximity | 20 % | Keeps traffic on a geographically close path |

Implementation: [services/server_ranker.py](../services/server_ranker.py)

## Composite Score

```
composite_score = W_LATENCY  × latency_score
                + W_LOAD     × load_score_inv
                + W_REGION   × region_score
```

All three components are normalised to **0.0 – 1.0** (higher = better).
The server with the highest composite score wins.

### Latency Score

```
latency_score = max(0, 1.0 − latency_ms / LATENCY_CAP_MS)
```

- `latency_ms` comes from the health monitor's ICMP ping probe.
- `LATENCY_CAP_MS` defaults to **500 ms**. Any server at or above this
  value scores 0.
- A server with 0 ms latency (localhost / same DC) scores 1.0.

### Load Score (inverted)

```
load_score_inv = 1.0 − load_score
```

`load_score` is a precomputed 0.0–1.0 metric stored on each server row,
updated every health check cycle:

```
load_score = 0.4 × cpu_load + 0.3 × memory_usage + 0.3 × (connections / max_connections)
```

An idle server (`load_score = 0.0`) scores 1.0.
A saturated server (`load_score = 1.0`) scores 0.0.

### Region Score

| Condition | Score |
|-----------|-------|
| Server region matches user's first-preference region | 1.0 |
| Server region matches second-preference region | 0.5 |
| Server region matches third-preference region | 0.25 |
| No region hint provided | 0.5 (neutral) |
| No match | 0.0 |

Region affinity table (hint → preferred regions in order):

| User hint | 1st preference | 2nd preference |
|-----------|----------------|----------------|
| `europe` / `eu` | Europe | — |
| `americas` / `caribbean` / `north_america` | Americas | Europe |
| `asia` | Asia | Europe |
| `oceania` | Asia | Americas |
| `africa` | Europe | Americas |

The hint is taken from the `X-Geo-Region` HTTP header sent by the client,
or from the `preferred_location` parameter on `allocate_server_for_user()`.

## Entry Points

### Profile endpoint (primary)

```
POST /api/vpn/profile
{
  "server_id": null,          ← triggers auto-selection
  "protocol": "auto",
  "device_name": "Laptop"
}
```

The endpoint filters candidates by tier, protocol support, and region
health, then calls `server_ranker.select_best(candidates, region_hint=...)`.

### allocate_server_for_user()

Called by internal services that need to assign a server to a user:

```python
from services.vpn_server_service import VPNServerService

server = VPNServerService.allocate_server_for_user(db, user, preferred_location="europe")
```

## Tuning

All weights and thresholds are configurable via environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `VPN_RANK_W_LATENCY` | 0.50 | Latency weight |
| `VPN_RANK_W_LOAD` | 0.30 | Load weight |
| `VPN_RANK_W_REGION` | 0.20 | Region proximity weight |
| `VPN_RANK_LATENCY_CAP_MS` | 500 | Latency ceiling (scores 0 at this value) |

To prioritise load balancing over latency (e.g. during a traffic spike):

```bash
VPN_RANK_W_LATENCY=0.30 VPN_RANK_W_LOAD=0.50 VPN_RANK_W_REGION=0.20
```

## Fallback Behaviour

If the ranker throws an exception or returns no result, the system falls
back to the first available server from the tier-filtered list. Auto-
selection must **never** block VPN connectivity.

## Worked Example

Three servers, user region hint = `europe`:

| Server | latency_ms | load_score | region |
|--------|-----------|-----------|--------|
| de-fra-1 | 25 | 0.15 | Europe |
| us-nyc-1 | 120 | 0.05 | Americas |
| de-nue-1 | 30 | 0.60 | Europe |

Scores:

```
de-fra-1:
  latency = 1.0 − 25/500 = 0.95
  load    = 1.0 − 0.15   = 0.85
  region  = 1.0 (exact match)
  composite = 0.50×0.95 + 0.30×0.85 + 0.20×1.0 = 0.475 + 0.255 + 0.200 = 0.930

us-nyc-1:
  latency = 1.0 − 120/500 = 0.76
  load    = 1.0 − 0.05    = 0.95
  region  = 0.0 (no match for "europe" hint)
  composite = 0.50×0.76 + 0.30×0.95 + 0.20×0.0 = 0.380 + 0.285 + 0.000 = 0.665

de-nue-1:
  latency = 1.0 − 30/500 = 0.94
  load    = 1.0 − 0.60   = 0.40
  region  = 1.0 (exact match)
  composite = 0.50×0.94 + 0.30×0.40 + 0.20×1.0 = 0.470 + 0.120 + 0.200 = 0.790
```

**Winner: de-fra-1** (0.930) — lowest latency + low load + region match.
de-nue-1 lost despite good latency because it's heavily loaded.
