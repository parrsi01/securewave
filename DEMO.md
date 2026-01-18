# SecureWave Demo Scope (Phase 1)

## Complete
- Registration and login flow
- JWT session persistence and logout
- Dashboard and settings pages
- Subscription UI and mock payment flows
- VPN config generation and QR codes
- Device management (add/revoke)
- WireGuard server registration (control-plane)
- VPN test suite (OS-level tunnel tests)
- Azure deployment scripts

## Deferred
- Native mobile/desktop apps
- Automated peer registration via SSH/Run Command
- Multi-region load balancing
- Usage-based billing
- Push notifications

## Demo Notes
- VPN tests only measure the active WireGuard tunnel on the device running the tests.
- In demo mode, some back-end services run with safe defaults and mock data.
