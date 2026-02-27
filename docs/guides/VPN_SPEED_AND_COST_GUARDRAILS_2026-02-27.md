# SecureWave Speed And Cost Guardrails (2026-02-27)

## What Was Implemented

1. Account UI now always shows a usage block for free-tier fallback (`5 GB`) even when `/api/user/plan` is temporarily unavailable.
2. Account UI now shows plan speed targets (down/up Mbps) returned by backend.
3. Backend `/api/user/plan` now returns per-tier speed target fields:
   - `speed_limit_mbps_down`
   - `speed_limit_mbps_up`
4. Backend now supports an optional premium data cap (`PREMIUM_TIER_MONTHLY_GB`) for cost protection.

## Environment Variables

Set in backend environment:

```bash
FREE_TIER_MONTHLY_GB=5
PREMIUM_TIER_MONTHLY_GB=0
FREE_TIER_SPEED_Mbps_DOWN=25
FREE_TIER_SPEED_Mbps_UP=10
PREMIUM_TIER_SPEED_Mbps_DOWN=250
PREMIUM_TIER_SPEED_Mbps_UP=100
```

Notes:
- `PREMIUM_TIER_MONTHLY_GB=0` means unlimited.
- Set `PREMIUM_TIER_MONTHLY_GB` to a positive value to enforce a visible cap in app UX.

## Important Limitation

These speed values are policy targets exposed to clients. They are not hard-enforced traffic shaping yet.

To hard-enforce per-user throughput limits, add server-side QoS (for example with `tc`/HTB + peer/IP classes for WireGuard, and equivalent controls for OpenVPN/IKEv2).

## Suggested Next DevOps Step

1. Add protocol-specific shaping scripts on VPN nodes.
2. Bind shaping classes to user/peer IP allocation ranges.
3. Add node-level alerts for egress bandwidth and connection saturation.
4. Fail closed in backend capability checks when a protocol runtime is unhealthy.

## Included Script

This repo now includes:

- `scripts/ops/apply_vpn_qos_policy.sh`

It applies Linux HTB classes for free vs premium source CIDR ranges on a VPN interface (`wg0`/`tun0`), with conservative defaults aligned to the current app policy targets.
