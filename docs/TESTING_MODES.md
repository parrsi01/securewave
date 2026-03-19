# Testing Modes

## Development

Use mock VPN mode for deterministic local runs:

```bash
flutter test integration_test/session_lifecycle_test.dart \
  -d linux \
  --dart-define=SECUREWAVE_MOCK_VPN=true
```

Behavior:

- no routing changes
- no WireGuard/OpenVPN/IKEv2 system calls
- no dependency on a healthy local VPN runtime
- normal backend auth/profile coverage remains

## Staging

Recommended split:

- run app smoke/integration in mock mode for deterministic UI coverage
- run explicit real-VPN validation separately against staging infrastructure

This keeps application regressions separate from infrastructure regressions.

## Production

Do not enable mock mode in production.

Production uses:

- `RealVpnAdapter`
- the existing `VpnService` and native Linux bridge
- normal runtime capability and tunnel verification logic

## Mock Tuning

- `SECUREWAVE_MOCK_VPN=true`
- `SECUREWAVE_MOCK_VPN_FORCE_FAILURE=true`
- `SECUREWAVE_MOCK_VPN_LATENCY_MS=3000`
- `SECUREWAVE_MOCK_VPN_UNSTABLE=true`

Recommended CI setting:

- `SECUREWAVE_MOCK_VPN=true`
- `FORCE_FAILURE=false`
- `UNSTABLE=false`
- latency near the default for stable runs
