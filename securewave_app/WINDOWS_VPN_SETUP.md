# Windows VPN Setup (Native Integration)

SecureWave includes a Windows MethodChannel handler that returns a
"vpn_not_configured" error until a WireGuard backend is added.

## Steps

1. Decide on backend:
   - WireGuard for Windows (Wintun + wireguard.exe)
   - Go-based embedded backend
2. Implement a native bridge in `windows/runner`:
   - Accept the WireGuard config string
   - Start/stop a tunnel
   - Report status back to Flutter
3. Ensure the app runs with the required privileges to add a tunnel.

## Current Bridge

`securewave/vpn` MethodChannel exists in `windows/runner/flutter_window.cpp`
and returns a clear error if no backend is configured.
