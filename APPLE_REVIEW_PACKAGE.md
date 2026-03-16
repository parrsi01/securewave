# SecureWave VPN — Apple Review Package

## App Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│  iOS / macOS Host App (Flutter or native SwiftUI)                │
│                                                                  │
│  ┌──────────────────┐     ┌──────────────────────────────────┐  │
│  │  Flutter UI      │     │  SecureWaveVPNManager.swift      │  │
│  │  (Dart/Riverpod) │────▶│  NETunnelProviderManager wrapper │  │
│  └──────────────────┘     └────────────┬─────────────────────┘  │
│                                        │ saveToPreferences       │
│                                        │ startVPNTunnel          │
└────────────────────────────────────────┼─────────────────────────┘
                                         │  XPC IPC
              ┌──────────────────────────▼─────────────────────────┐
              │  Packet Tunnel Extension (separate process)         │
              │  com.securewave.app.PacketTunnel                   │
              │                                                    │
              │  PacketTunnelProvider: NEPacketTunnelProvider      │
              │  WireGuardKit (WireGuardAdapter)                   │
              │  ↕ App Group UserDefaults (state, counters)        │
              └────────────────────┬───────────────────────────────┘
                                   │  WireGuard UDP 51820
              ┌────────────────────▼───────────────────────────────┐
              │  SecureWave Gateway (Hetzner VPS)                  │
              │  Frankfurt: de-fra-1 / Nuremberg: de-nue-1         │
              │  WireGuard + OpenVPN + IKEv2 (multi-protocol)      │
              └────────────────────────────────────────────────────┘
```

## Network Extension

### Extension type
`packet-tunnel-provider` — operates entirely in user space. The extension
does not use a System Extension (no kernel code) and runs sandboxed.

### Process separation
The extension runs as a separate process, managed by `nesessionmanager`.
It communicates with the host app via:
- `NETunnelProviderSession.sendProviderMessage(_:responseHandler:)` for status polls
- App Group `UserDefaults` for persistent state (connection status, byte counters)

### Entitlements required
| Entitlement | Purpose |
|---|---|
| `com.apple.developer.networking.networkextension` → `packet-tunnel-provider` | Creates/controls the tunnel |
| `com.apple.security.application-groups` | Shared UserDefaults between app + extension |
| `keychain-access-groups` | Auth token readable in both processes |
| `com.apple.developer.networking.vpn.api` → `allow-vpn` | macOS only — NETunnelProviderManager |

### Third-party package
WireGuardKit from `https://git.zx2c4.com/wireguard-apple` (Apache 2.0).
This is the official WireGuard iOS/macOS library by Jason Donenfeld (zx2c4).

## VPN Protocol: WireGuard

WireGuard is a modern VPN protocol using:
- **Key exchange**: Noise_IKpsk2 handshake (Curve25519 ECDH)
- **Encryption**: ChaCha20-Poly1305 AEAD
- **Hash**: BLAKE2s
- **Transport**: UDP (default port 51820)

Credentials are never sent to the server. The client generates an ephemeral
Curve25519 key pair; the public key is registered with the API, and the
server returns the peer configuration. The private key never leaves the device.

## Server Infrastructure

| Server | Location | Protocols |
|---|---|---|
| de-fra-1 | Frankfurt, Germany | WireGuard, OpenVPN, IKEv2 |
| de-nue-1 | Nuremberg, Germany | WireGuard, OpenVPN, IKEv2 |

Provider: Hetzner Cloud (ISO 27001 certified, EU data centres).
All servers run Ubuntu LTS with automatic security updates.

## API Endpoint

Base URL: `https://securewaveapp.com/api`

All API communication uses TLS 1.2+. The client uses iOS/macOS default
`URLSession` with no certificate pinning bypass. Certificate validation
follows the standard system trust store.

Relevant endpoints used by the app:
- `POST /auth/login` — username/password → JWT access token
- `GET /vpn/servers` — list available server locations
- `GET /vpn/connect/{server_id}` — obtain WireGuard peer config for the device

## Privacy Policy

`https://securewaveapp.com/privacy`

The app:
- Collects: email address (account registration only)
- Does not log: VPN traffic, DNS queries, browsing history, IP addresses of connected users
- Stores auth token: Keychain only (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`)
- No analytics SDK embedded

## Test Instructions for Reviewers

### Account
```
Email:    reviewer@securewave.test
Password: [provided separately via App Store Connect review notes]
```
These credentials have an active subscription. **Replace the placeholder with
real demo credentials before submission.**

### Test flow
1. Launch the app.
2. Log in with the reviewer account.
3. Tap "Connect" — a system VPN permission dialog appears.
4. Approve the dialog. The tunnel connects to Frankfurt (de-fra-1) by default.
5. Open Safari and navigate to `https://ipleak.net` — confirm the IP is in Germany.
6. Return to the app and tap "Disconnect".

### Simulator note
VPN functionality requires a **physical device**. The app detects the
simulator at runtime and shows a human-readable error:
> "VPN requires a physical iOS device. Network Extension is unavailable on Simulator."

### Background / entitlement note
The `com.apple.developer.networking.networkextension` entitlement is
required for `NEPacketTunnelProvider`. It is a standard App Store entitlement
(not requiring special review) that any VPN app obtains through the
Certificates, Identifiers & Profiles portal.

## File Manifest

```
apple/
  shared/
    api_client/SecureWaveAPIClient.swift     — HTTPS API, Keychain token storage
    config/VPNConfiguration.swift            — WireGuard config model + wg-quick renderer
    vpn_profile_manager/VPNProfileManager.swift — NETunnelProviderManager wrapper (SwiftUI)
  ios/
    SecureWavePacketTunnel/
      PacketTunnelProvider.swift             — NEPacketTunnelProvider (reference copy)
      Info.plist                             — Extension metadata
      SecureWavePacketTunnel.entitlements    — Extension entitlements
  macos/
    SecureWaveMac/
      SecureWaveMacApp.swift                 — SwiftUI @main, MenuBarExtra, AuthModel
      ContentView.swift                      — Login, server list, connection panel
      Info.plist                             — macOS bundle metadata
      SecureWaveMac.entitlements             — macOS app entitlements

Production iOS implementation (do not modify independently):
  securewave_app/ios/PacketTunnel/PacketTunnelProvider.swift
  securewave_app/ios/Runner/VPNManager.swift
  securewave_app/ios/Runner/AppDelegate.swift
```
