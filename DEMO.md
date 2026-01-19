# SecureWave Demo Flow

## Preconditions
- App running on Azure App Service
- WG server reachable at `WG_ENDPOINT`
- `WG_MOCK_MODE=false` for real config generation

## Demo Steps (Recommended)
1) Register a new account
2) Log in and open `/dashboard`
3) Navigate to `/vpn`
4) Generate a configuration and scan the QR code
5) Import the config in the WireGuard app and connect
6) Return to `/vpn` and run the VPN test (optional)
7) Revoke the device in Settings when finished

## Known Limits (Demo-Safe)
- Device limits enforced by plan
- Telemetry is metadata-only
- No browser-based VPN tunnel

## Deferred Items
- Native apps
- Usage-based billing
- Multi-region routing
