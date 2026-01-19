# SecureWave Architecture (High-Level)

## Components
- **Web UI (static)**: HTML/CSS/JS served from `/static`
- **API (FastAPI)**: Auth, subscription logic, device management, VPN config generation
- **WireGuard Servers**: OS-level VPN data plane managed externally
- **Database**: SQLite for demo; Postgres for production
- **Background Workers**: Health monitor, policy engine, key rotation

## Data Flow (Control Plane)
1) User registers and logs in
2) User requests a VPN config
3) API generates WireGuard config + QR
4) User imports config into WireGuard client
5) Optional telemetry is submitted to `/api/diagnostics/telemetry`
6) Optimizer uses metrics to recommend servers

## Security Boundaries
- VPN tunnel runs in WireGuard client only
- Private keys are encrypted at rest
- API uses JWT-based auth
- Rate limiting on auth and config generation

## Deployment
- Azure App Service (Linux, Python)
- Startup: `bash /home/site/wwwroot/startup.sh`
- Health: `/health`
