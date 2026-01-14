SecureWave handoff notes (Codex → Claude)

Project direction
- Goal: Privado-style VPN service with iOS-first client using WireGuard.
- Control plane stays in this FastAPI app; VPN servers run on Azure VMs.
- Optimizer: services/vpn_optimizer.py (MARL + XGBoost) is primary selection logic.

Recent changes
- Added a Privado-style settings page: static/settings.html + static/js/settings.js
- Linked Settings in dashboard nav and authenticated nav links.
- iOS scaffolding: ios/SecureWaveApp/* SwiftUI views + API client placeholders.

Key endpoints (current backend)
- POST /api/auth/login, /api/auth/register
- GET /api/optimizer/servers
- POST /api/vpn/connect (returns config + connection_id + qr_base64)
- POST /api/vpn/disconnect
- POST /api/vpn/config/download (server-aware)
- GET /api/vpn/config/qr?server_id=...

iOS app scaffolding
- SwiftUI views: LoginView, RegisterView, DashboardView, SettingsView
- APIClient uses /api endpoints; VPNService is placeholder
- Needs Xcode project + Network Extension entitlement to run WireGuard
- Update baseURL in ios/SecureWaveApp/Services/APIClient.swift

Settings (web)
- LocalStorage-based settings for protocol, kill switch, auto-connect, preferred country/region.
- No API persistence yet.

Open TODOs
- Implement WireGuard on iOS (NetworkExtension / WireGuardKit).
- Real connection status (handshake/latency) + always-on/killswitch enforcement.
- Automate VPN server peer provisioning (apply configs to WireGuard server).
- Azure VM check: az login required to confirm VM/subscription.
- Add settings persistence API if desired.
