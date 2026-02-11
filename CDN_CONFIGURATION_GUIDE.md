# CDN Configuration Guide

SecureWave does not require a CDN by default. Add a CDN only when approved.

If you enable a CDN:

- Cache static assets (`/static`) aggressively
- Bypass cache for `/api/*`
- Ensure WebSocket support if used
